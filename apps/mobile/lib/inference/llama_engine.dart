import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import 'inference_types.dart';

/// T017 — llama.cpp engine bound in-process via Dart FFI (research R1).
///
/// Design contract (contracts/local-inference.md):
/// - Opens **zero sockets** — inference is in-process (SC-007).
/// - `tryCreate` returns null when the native library is absent so callers
///   degrade to skeleton-only analysis (`model_missing`, FR-014).
/// - `ensureModelAsset` extracts the bundled GGUF to app storage (llama.cpp
///   needs a real filesystem path to mmap).
///
/// NOTE: C symbol signatures must match the vendored llama.cpp revision
/// (research R1). Symbol lookups are probed defensively — a missing symbol
/// surfaces as a `FailedEvent`, never a load-time crash.
class LlamaCppEngine implements InferenceEngine {
  LlamaCppEngine._(this._lib, this.modelPath);

  final DynamicLibrary _lib;
  final String modelPath;

  // --- lifecycle bindings --------------------------------------------------
  late final void Function() _backendInit = _probe0('llama_backend_init');
  late final void Function() _backendFree = _probe0('llama_backend_free');

  // --- model / context bindings (legacy C API names; newer builds renamed
  //     llama_model_load_from_file / llama_model_free — probe both) --------
  late final Pointer<Void> Function(Pointer<Utf8>, Pointer<Void>) _loadModel =
      _probe2('llama_load_model_from_file', alt: 'llama_model_load_from_file');
  late final void Function(Pointer<Void>) _freeModel =
      _probe1('llama_free_model', alt: 'llama_model_free');
  late final Pointer<Void> Function(Pointer<Void>, Pointer<Void>) _newContext =
      _probe2p('llama_new_context_with_model');
  late final void Function(Pointer<Void>) _freeContext =
      _probe1('llama_free_context');

  static const String _fallbackLibrary = 'libllama.so';

  /// Probes platform library names; returns null when llama.cpp is not
  /// packaged (the normal state before native vendoring — T017 native step).
  static Future<LlamaCppEngine?> tryCreate({
    required String modelPath,
    List<String> libraryCandidates = const [],
  }) async {
    final candidates = <String>[
      ...libraryCandidates,
      if (Platform.isAndroid) 'libllama.so',
      if (Platform.isIOS) 'llama.framework/llama',
      if (Platform.isWindows) 'llama.dll',
      if (Platform.isMacOS) 'libllama.dylib',
      _fallbackLibrary,
    ];
    for (final name in candidates.toSet()) {
      try {
        final lib = DynamicLibrary.open(name);
        return LlamaCppEngine._(lib, modelPath);
      } on ArgumentError {
        continue;
      } on OSError {
        continue;
      }
    }
    return null;
  }

  /// Extracts `assetName` from the bundle to app documents (chunked write so
  /// a ~1GB GGUF never holds the whole file in one buffer). Idempotent.
  /// Returns null when the asset is not bundled (research R11).
  static Future<String?> ensureModelAsset({
    required String assetName,
    required String destinationDir,
  }) async {
    final destination = p.join(destinationDir, assetName);
    final file = File(destination);
    if (await file.exists() && await file.length() > 0) return destination;

    final ByteData data;
    try {
      data = await rootBundle.load('assets/models/$assetName');
    } catch (_) {
      return null;
    }
    await Directory(destinationDir).create(recursive: true);
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

  // --- probing helpers -----------------------------------------------------
  //
  // Concrete `lookupFunction` instantiations (the analyzer must see real
  // native signatures); a missing symbol (ArgumentError) falls back to
  // [alt] for llama.cpp revisions that renamed the API.

  void Function() _probe0(String name, {String? alt}) {
    try {
      return _lib.lookupFunction<Void Function(), void Function()>(name);
    } on ArgumentError {
      if (alt != null) {
        return _lib.lookupFunction<Void Function(), void Function()>(alt);
      }
      rethrow;
    }
  }

  void Function(Pointer<Void>) _probe1(String name, {String? alt}) {
    try {
      return _lib
          .lookupFunction<Void Function(Pointer<Void>),
              void Function(Pointer<Void>)>(name);
    } on ArgumentError {
      if (alt != null) {
        return _lib.lookupFunction<Void Function(Pointer<Void>),
            void Function(Pointer<Void>)>(alt);
      }
      rethrow;
    }
  }

  Pointer<Void> Function(Pointer<Utf8>, Pointer<Void>) _probe2(
    String name, {
    String? alt,
  }) {
    try {
      return _lib.lookupFunction<
          Pointer<Void> Function(Pointer<Utf8>, Pointer<Void>),
          Pointer<Void> Function(Pointer<Utf8>, Pointer<Void>)>(name);
    } on ArgumentError {
      if (alt != null) {
        return _lib.lookupFunction<
            Pointer<Void> Function(Pointer<Utf8>, Pointer<Void>),
            Pointer<Void> Function(Pointer<Utf8>, Pointer<Void>)>(alt);
      }
      rethrow;
    }
  }

  Pointer<Void> Function(Pointer<Void>, Pointer<Void>) _probe2p(
    String name, {
    String? alt,
  }) {
    try {
      return _lib.lookupFunction<
          Pointer<Void> Function(Pointer<Void>, Pointer<Void>),
          Pointer<Void> Function(Pointer<Void>, Pointer<Void>)>(name);
    } on ArgumentError {
      if (alt != null) {
        return _lib.lookupFunction<
            Pointer<Void> Function(Pointer<Void>, Pointer<Void>),
            Pointer<Void> Function(Pointer<Void>, Pointer<Void>)>(alt);
      }
      rethrow;
    }
  }

  // --- generation ----------------------------------------------------------

  @override
  Stream<InferenceEvent> generateStream(InferenceRequest request) async* {
    Pointer<Void> model = Pointer.fromAddress(0);
    Pointer<Void> context = Pointer.fromAddress(0);
    try {
      _backendInit();

      final cPath = modelPath.toNativeUtf8();
      try {
        model = _loadModel(cPath, Pointer.fromAddress(0));
      } finally {
        calloc.free(cPath);
      }
      if (model == Pointer.fromAddress(0)) {
        yield const FailedEvent('model_missing', 'Model failed to load.');
        return;
      }

      context = _newContext(model, Pointer.fromAddress(0));
      if (context == Pointer.fromAddress(0)) {
        yield const FailedEvent('oom', 'Context allocation failed.');
        return;
      }

      // Grammar-constrained token loop (research R3) is wired against the
      // vendored llama.cpp revision in the native step of T017 — until then
      // any successful load lands here as a graceful FailedEvent so the
      // pipeline degrades per FR-014 (degraded brief + retry offer).
      yield const FailedEvent(
        'grammar_violation',
        'Token loop not yet bound to vendored llama.cpp revision.',
      );
    } catch (e) {
      yield FailedEvent('lib_missing', 'Inference unavailable: $e');
    } finally {
      if (context != Pointer.fromAddress(0)) {
        try {
          _freeContext(context);
        } catch (_) {
          // best-effort teardown
        }
      }
      if (model != Pointer.fromAddress(0)) {
        try {
          _freeModel(model);
        } catch (_) {
          // best-effort teardown
        }
      }
      try {
        _backendFree();
      } catch (_) {
        // best-effort teardown
      }
    }
  }
}
