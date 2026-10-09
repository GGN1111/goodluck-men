# Phase 0 Research: SignalReady Pocket — Offline Emergency Co-Pilot

**Branch**: `001-offline-emergency-copilot` | **Date**: 2026-10-09
**Input**: [plan.md](./plan.md) Technical Context · [spec.md](./spec.md)

All Technical Context unknowns resolved below — **zero open NEEDS CLARIFICATION items**.

---

## R1. On-device LLM runtime

**Decision**: Bind `llama.cpp` as a native library through Dart FFI, running inference **in-process** inside the Flutter app (Android `.so` / iOS `.xcframework`). No local HTTP server.

**Rationale**: The blueprint's "Ollama at localhost:11434" assumes a desktop/server process — Ollama does not run on stock Android, and hosting an HTTP loopback server on iOS violates App Store expectations and adds lifecycle, port, and RAM overhead. In-process FFI gives the lowest latency, works identically in airplane mode, and llama.cpp natively supports GGUF 4-bit models, token streaming, and GBNF grammar-constrained decoding (critical for JSON reliability, R3).

**Alternatives considered**:
- *Ollama / llama.cpp HTTP server* — rejected: no supported Android packaging path; extra process + RAM; server startup delay on cold open conflicts with the <2s goal.
- *MLC-LLM* — rejected: heavier build toolchain (Vulkan/TVM), steeper hackathon risk.
- *sherpa-onnx* — rejected: primary strength is ASR/TTS, chat-LLM support thinner than llama.cpp.
- *Cloud API* — rejected: violates FR-012/SC-007 outright.

---

## R2. Model selection

**Decision**: Primary `Qwen2.5-1.5B-Instruct` GGUF **Q4_K_M** (~1.0 GB) bundled as an app asset; fallback `Llama-3.2-1B-Instruct` Q4_K_M for low-RAM (≤3 GB) devices. Capability preflight at first launch picks the variant.

**Rationale**: Qwen2.5's multilingual coverage (including Philippine languages) and instruction/JSON adherence at the 1–1.5B scale outperform Llama-3.2-1B, which matters for Tagalog/Cebuano generation and strict schema output. Q4_K_M keeps a 1.5B model inside the RAM budget of mid-range (4–6 GB) Android phones, the realistic target user's device.

**Alternatives considered**:
- *Llama-3.2-1B only (blueprint default)* — kept as fallback, not primary: weaker multilingual generation.
- *Gemma-2-2B / Phi-3.5* — rejected: larger/slower or English-centric; miss latency budget.
- *Qwen2.5-0.5B only* — rejected as primary: noticeably weaker summaries and red-flag reasoning; retained as the CI smoke model (R10).

---

## R3. Structured-output (JSON) reliability

**Decision**: Three-layer defense: (1) llama.cpp **GBNF grammar** derived from the output schema constrains decoding so emitted tokens are always valid JSON; (2) post-generation **schema validation** (enums, required fields, trilingual presence); (3) on validation failure, **one targeted repair retry**, then a **degraded deterministic brief** from the fast-path (R4) with a visible "analysis limited" notice (FR-014).

**Rationale**: Small models otherwise wrap JSON in markdown, truncate, or hallucinate enum values. Grammar constraints make malformed JSON structurally impossible; validation catches semantic violations (wrong enum, missing Cebuano field); the degraded path guarantees the user still gets safety-critical classification rather than a spinner forever.

**Alternatives considered**:
- *Prompt-only "return JSON"* — rejected: ~70–80% reliable at this model size.
- *Function calling / tool APIs* — rejected: unsupported or unreliable for sub-2B open models.
- *Regex cleanup of free text* — rejected: fragile against truncation.

---

## R4. Latency strategy (resolves the <2s requirement)

**Decision**: **Two-stage hybrid pipeline with progressive rendering.**
- **Stage 1 — fast path (<100 ms, deterministic)**: keyword/pattern heuristics + lightweight extraction classify `crisis_type`, `bantay_state`, `location`, `time_or_status`, and emit a **template checklist** for the crisis type → UI immediately renders the full structured brief skeleton (theme, Bantay state, checklist, status line). This satisfies FR-013/SC-001 as written: *a structured brief is displayed within 2 seconds, offline.*
- **Stage 2 — LLM enrichment (streamed, p95 ≤15s)**: llama.cpp streams grammar-constrained tokens for plain-language summaries (EN/TL/CEB), Bantay speech, refined contextual steps, and `missing_warnings`; validated output atomically replaces the skeleton fields (status: `enriched`).

**Rationale** (honest hardware math): a 1.5B Q4 model on mid-range Android generates ≈10–25 tok/s; a full 300–400-token trilingual JSON would take 12–40s if awaited — no prompt trick closes a 2s gap for *complete* LLM output. The hybrid makes safety-critical classification instant and robust (it works even if the model is slow or fails), while LLM quality arrives moments later. Skeleton→enriched state transition is an explicit UI pattern ("Bantay is analyzing…").

**Handling the risk**: If stakeholders require the *fully enriched* brief under 2s, the documented fallback is Qwen2.5-0.5B with outputs capped at ~120 tokens (shorter summaries) — accepted trade-off on summary quality. Recorded in quickstart so SC-001 and enrichment latency are measured as **two separate numbers**.

**Alternatives considered**:
- *Await full LLM before any render* — rejected: fails SC-001 by an order of magnitude.
- *Relax the spec to ≥15s* — rejected: spec change requires stakeholder decision, not plan-level.
- *Cloud offload* — rejected: violates the product's core constraint.

---

## R5. Trilingual single-pass contract (FR-009)

**Decision**: Extend the blueprint's JSON schema with Cebuano fields (`summary_cebuano`, `bantay_speech_cebuano`, `step_cebuano`, `warning_cebuano`) and request **all three languages in one generation pass**. Validation *warns* (does not fail) if Cebuano text is byte-identical to Tagalog/English (cheap copy-detection) — a warning surfaces an "unverified translation" badge rather than blocking the safety brief.

**Rationale**: FR-009 demands sub-1s switching with no re-analysis, which requires all languages present before the user toggles. Generation is the only offline moment where translation cost can be paid.

**Alternatives considered**:
- *On-demand translation on toggle* — rejected: violates FR-009 (re-processing delay).
- *Fall back to English for Cebuano* — rejected: violates FR-009; spec treats Bisaya/Cebuano as a first-class language.

---

## R6. Screenshot OCR

**Decision**: `google_mlkit_text_recognition` (offline, on-device) for **both** platforms via one plugin. VisionKit/Apple Vision remains the iOS alternative if plugin integration fails.

**Rationale**: Satisfies FR-007 with zero network use; one dependency for both targets; ML Kit handles the phone-photo conditions (perspective, compression artifacts) typical of Facebook-notice screenshots.

**Alternatives considered**:
- *Apple VisionKit only* — rejected: iOS-only, dual implementation cost.
- *Tesseract* — rejected: slower and weaker on noisy social-media screenshots.
- *Cloud OCR* — rejected: violates FR-012.

---

## R7. Local storage

**Decision**: Plain **SQLite** via `sqflite`, app-private directory, simple versioned SQL migrations. SQLCipher encryption deferred to a post-v1 hardening task.

**Rationale**: The privacy requirement (FR-012) is *zero data egress* — satisfied regardless of at-rest encryption. The device-screen-lock threat model plus no-cloud/no-account design makes encryption non-blocking for v1; blueprint's "encrypted cache" is honored as a documented follow-up, not a hackathon blocker (iOS SQLCipher build friction is a real schedule risk).

**Alternatives considered**:
- *Hive/Isar NoSQL* — rejected: relational structure (incident → steps/alarms/warnings) fits SQL naturally; raw SQL is easiest to verify in tests.
- *SQLCipher now* — deferred: noted as optional hardening task; revisit if household-profile sensitivity grows.

---

## R8. Re-check alarms & reboot resilience (SC-006, reboot edge case)

**Decision**: `flutter_local_notifications` with **exact alarms** on Android (`SCHEDULE_EXACT_ALARM`/`USE_EXACT_ALARM` permission) and time-interval notifications on iOS. Every alarm is a DB row; a reconciliation routine runs at **app launch and on `BOOT_COMPLETED`** (Android receiver) that cancels stale platform alarms and re-arms any DB alarm whose time hasn't passed — idempotent, so double-arming is impossible. If exact-alarm permission is denied or notifications are denied, the app shows the FR-008 graceful-degradation notice plus in-app re-check prompts.

**Rationale**: DB-backed alarms directly answer the spec's reboot edge case ("either re-arm or inform the user — no silent loss"). Reconciliation at two deterministic points covers both platforms without relying on OS persistence of pending notifications.

**Alternatives considered**:
- *WorkManager periodic tasks* — rejected: ≥15-minute minimum interval misses the one-minute firing window (SC-006).
- *Raw AlarmManager via platform channels* — rejected: reimplements what the plugin already does, more boilerplate, same permissions.
- *Trust OS to persist pending notifications* — rejected: silently fails after reboot on several Android OEMs.

---

## R9. App framework

**Decision**: **Flutter (Dart 3)** single codebase, Android primary / iOS secondary.

**Rationale**: One codebase for both platforms; first-class plugin ecosystem for every dependency above (OCR, notifications, SQLite, FFI); declarative theming makes the ALERT/CAUTION/INFO state-driven theme switch (FR-003) trivial and golden-testable; 60 fps theming meets the performance goal. The demo target is Android, so Flutter's iOS path being secondary is acceptable risk.

**Alternatives considered**:
- *React Native* — rejected: FFI story for llama.cpp is weaker (native module bridging), plugin fragmentation across notifications/OCR.
- *Native Kotlin + Swift* — rejected: two implementations destroy hackathon timeline.
- *Kotlin Multiplatform* — rejected: UI layer still dual; higher ramp cost.

---

## R10. Testing & offline verification

**Decision**:
- **Unit/golden**: `flutter_test` for fast-path classifier, theming per severity, language switch; golden images for the three Bantay states.
- **Contract tests**: golden corpus of 20+ advisories (from the spec's flood example outward — floods, fires, blackouts, security, rumors, non-emergency, empty) run through the pipeline; assert schema validity, expected category/severity, required warnings present, and **no-fabrication review checklist** (SC-002's zero-fabrication clause is validated by schema + human review of corpus outputs).
- **Integration**: `integration_test` running the full paste→brief→checklist→alarm flow on an emulator with networking disabled (airplane mode), plus an egress assertion (no sockets open during workflow → SC-007).
- **CI cost control**: tests run against `Qwen2.5-0.5B` smoke model; nightly job uses the production 1.5B model.

**Rationale**: Keeps SC-001/002/006/007 verifiable without manual staging, and matches quickstart's validation scenarios.

**Alternatives considered**:
- *Device-lab only* — rejected: too slow for iteration.
- *Mocking the model always* — rejected: would never catch grammar/latency regressions (the riskiest parts, R3/R4).

---

## R11. Model packaging & distribution

**Decision**: Bundle the primary GGUF inside app assets → ~1.2 GB hackathon APK, **sideloaded** to demo devices. Document Play Asset Delivery (dynamic delivery of the model asset) as the production distribution path; the app must still boot and run its guides/history if the model asset is absent (shows "model not installed" state).

**Rationale**: Zero-setup, zero-download is a core selling point ("open and parse in <2s, free forever") — a first-run model download would itself need network, contradicting grid-proofing for first use. Sideloaded APKs have no store size limit. Production concern (store delivery) is documented, not built.

**Alternatives considered**:
- *First-run download* — rejected: breaks offline-first onboarding; needs connectivity.
- *Stripping to0.5B to shrink below 500 MB* — rejected: quality cost unnecessary for sideloaded demo (kept as the R4 fallback lever).

---

## R12. Bantay mascot rendering

**Decision**: Three static/vector mascot states (alert / caution / info) as Lottie animations or SVG assets with a simple state-driven widget; expression changes are theme-driven (colors `#C53030` / `#D69E2E` / `#1A202C`-blue) per FR-003. No runtime art generation.

**Rationale**: Mascot art is a design asset, not an engineering unknown; state-machine mapping (severity → art + theme) is deterministic and golden-testable.

**Alternatives considered**:
- *Procedural/generative mascot* — rejected: unnecessary complexity, inconsistent brand look.

---

## Resolution summary

| # | Unknown / choice | Status |
|---|------------------|--------|
| R1 | Inference runtime | Resolved — llama.cpp FFI in-process |
| R2 | Model | Resolved — Qwen2.5-1.5B Q4 primary, Llama-3.2-1B fallback |
| R3 | JSON reliability | Resolved — GBNF grammar + validation + repair + degraded path |
| R4 | <2s latency | Resolved — two-stage hybrid, streamed enrichment (risk documented) |
| R5 | Trilingual instant switch | Resolved — single-pass 3-language schema |
| R6 | OCR | Resolved — ML Kit both platforms |
| R7 | Storage | Resolved — plain SQLite, SQLCipher deferred |
| R8 | Alarms/reboot | Resolved — DB-backed exact alarms + boot/launch reconcile |
| R9 | Framework | Resolved — Flutter/Dart 3 |
| R10 | Testing/offline proof | Resolved — golden corpus + airplane-mode integration + egress assert |
| R11 | Distribution | Resolved — bundled model, sideload demo, PAD for production |
| R12 | Mascot | Resolved — asset-based state widget |

**Open items for stakeholders (non-blocking, tracked in quickstart)**: none block Phase 1; the R4 latency interpretation (structured brief vs. fully enriched brief under 2s) is the single item to confirm during `/speckit.clarify` or acceptance testing.
