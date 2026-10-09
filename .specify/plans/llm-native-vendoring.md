# Plan: Make the local LLM real (vendor llama.cpp + bind the token loop)

## Goal
Turn the placeholder `LlamaCppEngine` into a working on-device inference engine:
compile `libllama.so` from a pinned llama.cpp source, bind the modern C API in
Dart FFI, implement the grammar-constrained token loop, and bundle the
Qwen2.5-1.5B-Instruct Q4_K_M GGUF — so `EnrichmentPipeline` produces real
trilingual enrichment instead of `FailedEvent('grammar_violation')`.

Decisions locked (from user): **CMake-compiled pinned llama.cpp**, **modern
sampling API**, **Qwen2.5-1.5B-Instruct Q4_K_M** primary model.

## Verified facts driving the design
- llama.cpp grammar is **sampler-only** in the modern API. There is no
  `llama_grammar_init`. Constrained decoding is:
  `llama_sampler_init_grammar(vocab, grammar_str, grammar_root)` added to a
  `llama_sampler_chain`. `grammar_root` = `root` (matches `bantay-json-v1.gbnf`).
- `llama_sampler_chain_init(params)` returns a `llama_sampler*`; it is freed
  with `llama_sampler_free` (no `llama_sampler_chain_free` exists).
- `llama_model_default_params()` / `llama_context_default_params()` return
  **structs by value** — FFI must size them. This is the main ABI risk.
- `llama_batch` is returned by value from `llama_batch_get_one`; its field
  order is `n_tokens, token, embd, pos, n_seq_id, seq_id, logits`.
- Current build stack: AGP 9.0.1, Kotlin 2.3.20, Gradle 9.1.0, Java 17,
  Kotlin DSL (`build.gradle.kts`). CMake 3.22.1 + NDK 28.2 present on host.
  Network reachable (git clone works).

## Approach

### Phase A — vendor native llama.cpp (build wiring)
1. `git submodule add https://github.com/ggml-org/llama.cpp vendor/llama.cpp`
   pinned to a release tag; commit `.gitmodules`.
2. New `apps/mobile/android/app/src/main/cpp/CMakeLists.txt`:
   - `add_subdirectory(vendor/llama.cpp ...)` with `BUILD_SHARED_LIBS` off,
     tests/examples/tools off (`LLAMA_BUILD_TESTS=OFF`, `LLAMA_BUILD_EXAMPLES=OFF`,
     `LLAMA_BUILD_SERVER=OFF`, `BUILD_SHARED_LIBS=OFF`), CPU-only
     (`GGML_NATIVE=OFF`, `GGML_BLAS=OFF`).
   - Produce one shared lib target; set output name `llama` so the artifact is
     `libllama.so`. Link `log` (Android).
3. `android/app/build.gradle.kts`:
   - `externalNativeBuild { cmake { path = ...; version = "3.22.1" } }`
   - `defaultConfig.ndk.abiFilters += listOf("arm64-v8a")` (A53 is arm64; keeps
     the .so small — no armeabi-v7a/x86 bloat).
   - Source dir points at the app cpp folder; llama.cpp referenced by relative
     path into `vendor/`.
4. Verify: `flutter build apk --debug` produces `libllama.so` in the APK and
   the build does not regress the existing Kotlin build.

### Phase B — Dart FFI: struct layout + bindings
New file `lib/inference/llama_bindings.dart` (raw `dart:ffi` typedefs, kept
separate from the engine logic):
1. **Struct size constants** — the ABI risk. Define
   `LlamaModelParams`, `LlamaContextParams`, `LlamaSamplerChainParams`,
   `LlamaBatch`, `LlamaTokenData`, `LlamaTokenDataArray` as `Struct` with the
   exact field order from `llama.h`. Pin to the submodule commit; if
   `sizeOf<LlamaModelParams>()` mismatches, generation silently corrupts — so
   add a **runtime self-check**: call `llama_model_default_params()` into a
   scratch buffer and compare a few known fields (e.g. `n_gpu_layers == 0`,
   `vocab_only == false`) to confirm layout before first load.
2. Bind (modern names, keep existing legacy `alt` probing as fallback):
   - lifecycle: `llama_backend_init/free` (already bound)
   - model: `llama_model_default_params`, `llama_model_load_from_file`,
     `llama_model_free`, `llama_model_get_vocab` (already partly bound)
   - context: `llama_context_default_params`, `llama_init_from_model`,
     `llama_free`
   - tokenize: `llama_tokenize`, `llama_vocab_n_tokens`
   - decode: `llama_batch_get_one`, `llama_decode`, `llama_get_logits_ith`
   - piece: `llama_token_to_piece` (6-arg)
   - sampler: `llama_sampler_chain_default_params`, `llama_sampler_chain_init`,
     `llama_sampler_chain_add`, `llama_sampler_init_dist` (seed),
     `llama_sampler_init_temp`, `llama_sampler_init_top_p`,
     `llama_sampler_init_grammar`, `llama_sampler_sample`, `llama_sampler_accept`,
     `llama_sampler_free`
3. `struct llama_batch` handling: use `llama_batch_get_one(tokens, n)` which
   returns the struct by value; capture it into a Dart `Struct` and pass its
   address to `llama_decode`. Free any heap token buffer after.

### Phase C — implement the token loop in `llama_engine.dart`
Replace the placeholder in `generateStream` (currently yields
`FailedEvent('grammar_violation')` at lines ~201–208):
1. Load model + vocab (already partly there) → `FailedEvent('model_missing')`
   on null.
2. Build context with `n_ctx` sized for prompt + `maxTokens` (e.g. 4096),
   `n_batch`/`n_ubatch` reasonable, `n_threads`/`n_threads_batch` from
   `Platform.numberOfProcessors`. OOM → `FailedEvent('oom')`.
3. Assemble prompt: system prompt + user text (reuse `kBantaySystemPrompt` +
   `BantayPrompt.userTurn`/`repairTurn` — already provided in
   `request.systemPrompt`/`request.userText`; no change needed there).
4. Tokenize prompt (`add_special: true`), build batch, `llama_decode`.
5. Build sampler chain: `dist(seed ?? random)` → `temp(temperature)` →
   `top_p(topP, 1)` → `grammar(vocab, grammarStr, "root")`. Load grammar text
   from `assets/models/bantay-json-v1.gbnf` via `rootBundle` (map
   `request.grammarId` → asset path; `grammarId` is currently dead data — this
   is where it becomes live). Cache the loaded grammar string.
6. Loop: `llama_sampler_sample(chain, ctx, -1)` → `llama_token_to_piece` →
   emit `TokenEvent(text)` + periodic `ProgressEvent(tokens, elapsedMs)` →
   `llama_sampler_accept` → single-token `llama_decode`. Stop on EOS
   (`token == -1`/vocab EOS), `maxTokens`, or a wall-clock timeout
   (map to `FailedEvent('timeout')` — currently unenforced anywhere; add a
   `Stopwatch` guard, e.g. 30s hard cap).
7. On finish: `CompletedEvent(raw)`. On any native throw: map to
   `FailedEvent` with the right code (`oom`/`timeout`/`grammar_violation`/
   `lib_missing`). `finally`: free context, model, sampler chain, backend.
8. **Cancellation**: honor stream-listener cancel between yields (the
   `async*` already stops on cancel; ensure `finally` frees promptly).
   Optional: an abort flag checked each iteration → `FailedEvent('cancelled')`.

### Phase D — model asset + wiring
1. Add a download script (PowerShell) to fetch
   `qwen2.5-1.5b-instruct-q4_k_m.gguf` into `apps/mobile/assets/models/`
   (git-ignored, per existing README). Document in `assets/models/README.md`.
2. `AppGraph.primaryModelAsset` already points at the right filename — no change.
3. Confirm `ensureModelAsset` chunked extraction still works at 1 GB (it
   already writes in 4 MiB chunks). Watch first-launch extraction time; the
   cold `loadModel` is outside the ≤2s brief budget per the contract.

### Phase E — validation
1. Unit/host: `flutter analyze` clean; existing 151 tests still pass.
2. New host test: with engine absent, `tryCreate` returns null (already
   covered). Add a test asserting the grammar asset string is non-empty and
   the `grammarId`→asset mapping resolves.
3. Device (`flutter run` on A53, airplane mode):
   - App boots (no splash hang), Settings shows `model_variant: primary`.
   - Paste the Marikina flood advisory → enrichment flips to `enriched` with
     trilingual summary + refined checklist.
   - Record SC-001(b) enrichment p95 (target ≤15s) into
     `specs/001-offline-emergency-copilot/validation-results.md`.
   - Confirm the "verify translations" badge behavior on Cebuano (R5).
4. Degradation: rename the GGUF → `model_missing` path still boots + Guides/
   History work (FR-014). Unplug/not-bundle the `.so` → `lib_missing` graceful.

## Risks & mitigations
- **Struct-by-value ABI mismatch** (highest risk): mitigate with the runtime
  self-check in Phase B.3 + a debug-only assert comparing `sizeOf` against a
  known-good value for the pinned commit.
- **First native build is slow** (llama.cpp compile): one-time; Gradle caches.
  `-Xmx8G` already set in gradle.properties.
- **1 GB asset + first-run extraction** on device storage: mmap-friendly; keep
  extraction chunked; document that cold load is not in the 2s budget.
- **Grammar forces ≥1 warning** in `bantay-json-v1.gbnf` while the validator
  allows empty `missing_warnings` — pre-existing mismatch (noted in research);
  out of scope here but flag it, since constrained decoding will always emit
  ≥1 warning.

## Out of scope (flagged, not doing)
- iOS `.xcframework` (Android-first; iOS later).
- GPU/Vulkan offload (CPU-only build).
- The `missing_warnings` grammar-vs-validator empty-array mismatch.
- Play Asset Delivery for production model delivery (R11 documents it; v1
  sideloads the APK).

## Files touched
- **New:** `vendor/llama.cpp` (submodule), `android/app/src/main/cpp/CMakeLists.txt`,
  `lib/inference/llama_bindings.dart`, `tool/download_model.ps1`.
- **Edit:** `android/app/build.gradle.kts`, `lib/inference/llama_engine.dart`,
  `assets/models/README.md`, `specs/.../validation-results.md` (T056 numbers).
- **Verify-only:** `lib/inference/enrichment_pipeline.dart`,
  `lib/core/app_graph.dart` (should need no change).
