import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show MethodChannel, rootBundle;
import 'package:path/path.dart' as p;

import 'inference_types.dart';

// Flat, primitive-only C API exported by libllama.so
// (android/app/src/main/cpp/llama_shim.cpp). No C structs cross the FFI
// boundary, so there is no ABI-layout risk on the Dart side.

typedef _CreateNative = Pointer<Void> Function(
    Pointer<Utf8> modelPath, Int32 nCtx, Int32 nThreads, Pointer<Int32> err);
typedef _CreateDart = Pointer<Void> Function(
    Pointer<Utf8>, int, int, Pointer<Int32>);

typedef _SetupNative = Int32 Function(Pointer<Void> engine, Pointer<Utf8> grammar,
    Pointer<Utf8> root, Int32 seed, Float temp, Float topP);
typedef _SetupDart = int Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, int, double, double);

typedef _FeedNative = Int32 Function(Pointer<Void> engine, Pointer<Utf8> prompt);
typedef _FeedDart = int Function(Pointer<Void>, Pointer<Utf8>);

typedef _SampleNative = Int32 Function(
    Pointer<Void> engine, Pointer<Uint8> out, Int32 outCap);
typedef _SampleDart = int Function(Pointer<Void>, Pointer<Uint8>, int);

typedef _FreeNative = Void Function(Pointer<Void> engine);
typedef _FreeDart = void Function(Pointer<Void>);

/// Resolved shim bindings for one loaded libllama.so. Lookups are cheap
/// (dlsym), so they are redone per generation rather than cached per isolate.
class _Shim {
  _Shim(DynamicLibrary lib)
      : create = lib.lookupFunction<_CreateNative, _CreateDart>('sr_create'),
        setup = lib.lookupFunction<_SetupNative, _SetupDart>('sr_setup'),
        feed = lib.lookupFunction<_FeedNative, _FeedDart>('sr_feed'),
        sample = lib.lookupFunction<_SampleNative, _SampleDart>('sr_sample'),
        free = lib.lookupFunction<_FreeNative, _FreeDart>('sr_free');

  final _CreateDart create;
  final _SetupDart setup;
  final _FeedDart feed;
  final _SampleDart sample;
  final _FreeDart free;
}

int _threadsForRequest() {
  final n = Platform.numberOfProcessors;
  return n > 1 ? n - 1 : 1;
}

int _nCtxFor(InferenceRequest request) {
  // Room for the prompt (~a few hundred tokens) + generation + headroom.
  final ctx = request.sampling.maxTokens + 1536;
  return ctx < 2048 ? 2048 : ctx;
}

/// T017 — llama.cpp engine, bound in-process via Dart FFI to the native shim.
///
/// Contract (contracts/local-inference.md):
/// - Opens **zero sockets** — inference is in-process (SC-007).
/// - `tryCreate` returns null when the native library or shim symbols are
///   absent, so callers degrade to skeleton-only analysis (FR-014).
/// - `ensureModelAsset` extracts the bundled GGUF to app storage.
///
/// The heavy llama.cpp work (model load, sampler chain, GBNF grammar, token
/// loop) lives in the C++ shim; this class only drives it and turns sampled
/// pieces into the [InferenceEvent] stream.
class LlamaCppEngine implements InferenceEngine {
  LlamaCppEngine._(this.lib, this.modelPath);

  final DynamicLibrary lib;
  final String modelPath;

  static String? _grammarCache;

  /// Probes platform library names; returns null when llama.cpp is not
  /// packaged (or an older build without the shim), so callers degrade
  /// gracefully (FR-014). Host tests hit this path and get null.
  static DynamicLibrary? openLibrary({
    List<String> libraryCandidates = const [],
  }) {
    final candidates = <String>[
      ...libraryCandidates,
      if (Platform.isAndroid) 'libllama.so',
      if (Platform.isIOS) 'llama.framework/llama',
      if (Platform.isWindows) 'llama.dll',
      if (Platform.isMacOS) 'libllama.dylib',
      'libllama.so',
    ];
    for (final name in candidates.toSet()) {
      try {
        final lib = DynamicLibrary.open(name);
        // Validate the shim surface before handing the engine out.
        lib.lookupFunction<_CreateNative, _CreateDart>('sr_create');
        lib.lookupFunction<_SampleNative, _SampleDart>('sr_sample');
        return lib;
      } on ArgumentError {
        continue;
      } on OSError {
        continue;
      }
    }
    return null;
  }

  static Future<LlamaCppEngine?> tryCreate({
    required String modelPath,
    List<String> libraryCandidates = const [],
  }) async {
    final lib = openLibrary(libraryCandidates: libraryCandidates);
    return lib == null ? null : LlamaCppEngine._(lib, modelPath);
  }

  /// Extracts `assetName` from the bundle to app documents (chunked write so
  /// a ~1GB GGUF never holds the whole file in one buffer). Idempotent.
  /// Returns null when the asset is not bundled (research R11).
  ///
  /// On Android, extraction is delegated to the platform's `AssetManager`
  /// via a MethodChannel: `rootBundle.load()` would materialize the entire
  /// GGUF as one Dart `ByteData`, which OOMs on low-RAM devices. The channel
  /// path streams straight from the APK to disk with a small buffer.
  static const MethodChannel _assetChannel =
      MethodChannel('signalready/model_asset');

  static Future<String?> ensureModelAsset({
    required String assetName,
    required String destinationDir,
  }) async {
    final destination = p.join(destinationDir, assetName);
    final file = File(destination);
    if (await file.exists() && await file.length() > 0) return destination;

    await Directory(destinationDir).create(recursive: true);

    // Android: stream-copy via native AssetManager (bounded memory).
    // Never fall back to rootBundle here — the VM's NewExternalTypedData
    // caps single buffers at 1 GiB, so loading a >1 GiB GGUF through the
    // binary messenger throws and can leave the startup future unresolved
    // (splash hang). If the channel fails, degrade to skeleton-only.
    if (Platform.isAndroid) {
      try {
        final copied = await _assetChannel.invokeMethod<int>('extractAsset', {
          'asset': 'flutter_assets/assets/models/$assetName',
          'dest': destination,
        });
        if (copied != null && copied > 0 && await file.length() == copied) {
          return destination;
        }
        debugPrint('ensureModelAsset: channel copied=$copied, size mismatch');
      } catch (e) {
        debugPrint('ensureModelAsset: channel extraction failed: $e');
      }
      return null;
    }

    // Host tests / desktop: small assets only (rootBundle has a 1 GiB cap).
    final ByteData data;
    try {
      data = await rootBundle.load('assets/models/$assetName');
    } catch (_) {
      return null;
    }
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final sink = file.openWrite();
    try {
      const chunk = 4 * 1024 * 1024;
      for (var offset = 0; offset < bytes.length; offset += chunk) {
        final end =
            offset + chunk < bytes.length ? offset + chunk : bytes.length;
        sink.add(bytes.sublist(offset, end));
        await sink.flush();
      }
    } finally {
      await sink.close();
    }
    return destination;
  }

  /// Loads the GBNF grammar text for [grammarId] (cached after first read).
  /// Public so the isolate entry point can load it on the main isolate before
  /// spawning (rootBundle is main-isolate only).
  static Future<String?> loadGrammar(String grammarId) async {
    if (_grammarCache != null) return _grammarCache;
    try {
      final text = await rootBundle.loadString('assets/models/$grammarId.gbnf');
      _grammarCache = text;
      return text;
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<InferenceEvent> generateStream(InferenceRequest request) async* {
    final grammar = await loadGrammar(request.grammarId);
    if (grammar == null) {
      debugPrint('llm: grammar asset missing ${request.grammarId}');
      yield FailedEvent('grammar_violation',
          'Grammar asset "${request.grammarId}.gbnf" missing.');
      return;
    }
    yield* runGeneration(
      lib: lib,
      modelPath: modelPath,
      request: request,
      grammarText: grammar,
    );
  }

  /// Core llama.cpp token loop, extracted so the background-isolate entry
  /// point can reuse it. All FFI calls here are blocking native calls — the
  /// caller is responsible for running this off the UI thread.
  static Stream<InferenceEvent> runGeneration({
    required DynamicLibrary lib,
    required String modelPath,
    required InferenceRequest request,
    required String grammarText,
  }) async* {
    final shim = _Shim(lib);
    debugPrint('llm: generate start maxTokens=${request.sampling.maxTokens}');
    // 1) Bring up the native engine (model load + context).
    final errPtr = calloc<Int32>();
    Pointer<Void> engine = Pointer.fromAddress(0);
    try {
      final cPath = modelPath.toNativeUtf8();
      final sw = Stopwatch()..start();
      try {
        engine = shim.create(
            cPath, _nCtxFor(request), _threadsForRequest(), errPtr);
      } finally {
        calloc.free(cPath);
      }
      debugPrint(
          'llm: sr_create ${sw.elapsedMilliseconds}ms err=${errPtr.value}');
      if (engine == Pointer.fromAddress(0)) {
        final code = errPtr.value == 2 ? 'oom' : 'model_missing';
        yield FailedEvent(code, 'Engine failed to start (code ${errPtr.value}).');
        return;
      }
    } finally {
      calloc.free(errPtr);
    }

    try {
      // 2) Grammar-constrained sampler chain (GBNF + temp + top_p + dist).
      final gStr = grammarText.toNativeUtf8();
      final gRoot = 'root'.toNativeUtf8();
      int rc;
      try {
        rc = shim.setup(engine, gStr, gRoot, request.sampling.seed ?? -1,
            request.sampling.temperature, request.sampling.topP);
      } finally {
        calloc.free(gStr);
        calloc.free(gRoot);
      }
      debugPrint('llm: sr_setup rc=$rc');
      if (rc != 0) {
        yield const FailedEvent(
            'grammar_violation', 'Grammar failed to compile.');
        return;
      }

      // 3) Encode the prompt (system + user turn) and prime the KV cache.
      final prompt = '${request.systemPrompt}\n${request.userText}';
      final cPrompt = prompt.toNativeUtf8();
      try {
        rc = shim.feed(engine, cPrompt);
      } finally {
        calloc.free(cPrompt);
      }
      debugPrint('llm: sr_feed rc=$rc promptChars=${prompt.length}');
      if (rc != 0) {
        yield const FailedEvent('grammar_violation', 'Prompt decode failed.');
        return;
      }

      // 4) Grammar-constrained token loop: sample -> emit -> repeat.
      final stopwatch = Stopwatch()..start();
      const hardTimeout = Duration(seconds: 180);
      const outCap = 256;
      final outBuf = calloc<Uint8>(outCap);
      final rawBytes = <int>[];
      var steps = 0;
      try {
        while (steps < request.sampling.maxTokens) {
          steps++;
          if (stopwatch.elapsed > hardTimeout) {
            yield FailedEvent(
                'timeout', 'Generation exceeded ${hardTimeout.inSeconds}s.');
            return;
          }

          final n = shim.sample(engine, outBuf, outCap);
          if (n == 0) break; // EOS
          if (n == -3) continue; // empty piece (special token) — keep going
          if (n < 0) {
            debugPrint('llm: sr_sample failed n=$n at step $steps');
            yield FailedEvent('grammar_violation', 'Sampling failed ($n).');
            return;
          }

          final piece = outBuf.asTypedList(n);
          rawBytes.addAll(piece);
          yield TokenEvent(utf8.decode(piece, allowMalformed: true));
          if (steps % 8 == 0) {
            yield ProgressEvent(
                tokensGenerated: steps,
                elapsedMs: stopwatch.elapsedMilliseconds);
          }
        }
        debugPrint(
            'llm: done steps=$steps bytes=${rawBytes.length} in ${stopwatch.elapsedMilliseconds}ms');
        yield CompletedEvent(utf8.decode(rawBytes, allowMalformed: true));
      } finally {
        calloc.free(outBuf);
      }
    } finally {
      if (engine != Pointer.fromAddress(0)) {
        try {
          shim.free(engine);
        } catch (_) {
          // best-effort teardown
        }
      }
    }
  }
}

/// Runs [LlamaCppEngine]'s native llama.cpp calls on a background isolate so
/// the blocking FFI work (model load, prompt prefill, token decode) never
/// freezes the UI thread. Without this, tapping "Analyze offline" freezes the
/// app for the whole generation and Android raises an ANR.
class IsolateInferenceEngine implements InferenceEngine {
  IsolateInferenceEngine._(this.modelPath);

  final String modelPath;

  /// Probes the native library on the main isolate and returns an engine that
  /// runs inference off-thread, or null when the lib/model is unavailable.
  static Future<IsolateInferenceEngine?> create({
    required String modelPath,
    List<String> libraryCandidates = const [],
  }) async {
    final lib =
        LlamaCppEngine.openLibrary(libraryCandidates: libraryCandidates);
    if (lib == null) return null;
    return IsolateInferenceEngine._(modelPath);
  }

  @override
  Stream<InferenceEvent> generateStream(InferenceRequest request) {
    final controller = StreamController<InferenceEvent>();
    () async {
      try {
        final grammar = await LlamaCppEngine.loadGrammar(request.grammarId);
        if (grammar == null) {
          controller.add(FailedEvent('grammar_violation',
              'Grammar asset "${request.grammarId}.gbnf" missing.'));
          return;
        }
        final fromIsolate = ReceivePort();
        final isolate = await Isolate.spawn(
          _inferenceIsolateEntry,
          _InferenceIsolateArgs(
              fromIsolate.sendPort, modelPath, request, grammar),
          debugName: 'signalready-inference',
          errorsAreFatal: true,
        );
        try {
          await for (final message in fromIsolate) {
            if (message == null) break; // isolate signalled done
            if (message is InferenceEvent) {
              controller.add(message);
              if (message is CompletedEvent || message is FailedEvent) {
                break;
              }
            }
          }
        } finally {
          isolate.kill(priority: Isolate.immediate);
          fromIsolate.close();
        }
      } catch (e) {
        controller.add(FailedEvent('oom', 'Inference isolate failed: $e'));
      } finally {
        await controller.close();
      }
    }();
    return controller.stream;
  }
}

/// Sendable args for the background inference isolate (no closures, no
/// native handles — only primitives and plain objects).
class _InferenceIsolateArgs {
  const _InferenceIsolateArgs(
      this.replyTo, this.modelPath, this.request, this.grammarText);

  final SendPort replyTo;
  final String modelPath;
  final InferenceRequest request;
  final String grammarText;
}

/// Entry point for the background inference isolate. Reuses the same
/// [LlamaCppEngine.runGeneration] loop as the main-isolate path.
@pragma('vm:entry-point')
void _inferenceIsolateEntry(_InferenceIsolateArgs args) {
  final lib = DynamicLibrary.open('libllama.so');
  LlamaCppEngine.runGeneration(
    lib: lib,
    modelPath: args.modelPath,
    request: args.request,
    grammarText: args.grammarText,
  ).listen(
    args.replyTo.send,
    onDone: () => args.replyTo.send(null),
  );
}
