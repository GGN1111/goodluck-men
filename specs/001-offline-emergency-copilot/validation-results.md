# Validation Results — 001-offline-emergency-copilot

**Date**: 2026-10-09
**Host**: Windows 11, Flutter 3.44.0 stable, Dart SDK bundled — no GGUF model
bundled yet (fast-path-only mode, research R11) and no demo device connected
(`adb devices` empty). All device-only measurements are marked **PENDING**.

---

## SC-001 — Two-number methodology (research R4)

| Metric | Target | Measured | Where |
|---|---|---|---|
| (a) Skeleton brief display | ≤ 2 s offline | **median 4 ms, max 5 ms** (10 runs, host sqflite_ffi) | `test/integration/offline_e2e_test.dart` V1 + host microbenchmark |
| (b) Enrichment completion | p95 ≤ 15 s (mid-range) | **PENDING device + bundled GGUF** | needs on-device run (V1 quickstart) |

Note: (a) is the fast-path skeleton only (see research R4). Once the
`qwen2.5-1.5b-instruct-q4_k_m.gguf` asset is bundled, re-run V1 on the demo
device in airplane mode and record (b) plus the enriched-status flip time.

## Quickstart scenarios

| Scenario | Host suite result | Device run |
|---|---|---|
| V1 Core offline parse (≤2 s skeleton) | PASS (`offline_e2e_test` V1) | PENDING |
| V2 Missing-info red flags, zero fabrication | PASS (V2 + `warnings_corpus_test`) | PENDING |
| V3 Screenshot ingestion (OCR seams) | PASS (V3 + `ocr_fallback_test`) | PENDING (real ML Kit) |
| V4 Checklist persistence across restart | PASS (V4 + `history_delete_theme_test`) | PENDING |
| V5 Re-check alarm + reboot reconciliation | PASS at seam level (V5 + `alarm_reconciler_test`) | PENDING (real notifications) |
| V6 Instant language switch <1 s | PASS (V6 + `language_switch_test`) | PENDING |
| V7 Zero-egress proof | PASS — `IOOverrides` guard, **0 socket opens** (`egress_guard_test` + whole V-suite) | PENDING (device data-usage) |
| V8 Degradation paths | PASS (V8: no model → skeleton + Guides/History usable) | PENDING (repair-retry injection) |
| V9 Blackout mode & delete cascade | PASS (V9 + `history_delete_theme_test`) | PENDING |
| V10 Odd inputs (empty/grocery/foreign/20k) | PASS (V10) | PENDING |

## Corpus contract tests (flutter test)

- `corpus/fastpath_corpus_test.dart` — PASS (crisis_type + bantay_state per fixture)
- `corpus/warnings_corpus_test.dart` — PASS (complete fixtures → exactly 0 warnings; incomplete → all required codes)
- `corpus/provenance_test.dart` — PASS (verbatim source provenance)
- `contract/analysis_schema_test.dart` — PASS (schema validation)
- **Pass rate on bundled `test/corpus/corpus.json`: 100%** (whole suite green:
  149/149 including goldens + integration)

## Performance budget

| Metric | Target | Status |
|---|---|---|
| Skeleton brief | ≤ 2 s | PASS host (4 ms median); device PENDING |
| Enrichment p95 | ≤ 15 s | PENDING device + model |
| Language switch | < 1 s | PASS (pure field selection, unit-measured) |
| Egress | 0 bytes | PASS host (IOOverrides guard) |
| UI theme transitions | 60 fps | golden tests pin the three states |

## Device checklist (remaining for full DoD)

1. Bundle GGUF assets into `apps/mobile/assets/models/`.
2. Connect demo device (≥6 GB RAM, airplane mode ON), `flutter run`.
3. Walk V1–V10 on-device; paste SC-001(b) enrichment p95 above.
4. Confirm V5 notification delivery (±1 min) and reboot re-arm.
