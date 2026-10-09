# Implementation Plan: SignalReady Pocket — Offline Emergency Co-Pilot

**Branch**: `001-offline-emergency-copilot` | **Date**: 2026-10-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-offline-emergency-copilot/spec.md`

## Summary

Build a single-codebase mobile app (Flutter/Dart, Android primary, iOS secondary) that analyzes raw emergency advisories (pasted text or screenshot OCR) **entirely on-device** using a 4-bit quantized small LLM (`Qwen2.5-1.5B-Instruct` GGUF, `Llama-3.2-1B` fallback) bound in-process via llama.cpp FFI — no server, no cloud, no accounts. A hybrid two-stage pipeline satisfies the <2s requirement: a deterministic fast-path classifies crisis type/severity and renders a structured brief skeleton instantly, while a grammar-constrained LLM stream enriches it with plain-language trilingual summaries, contextual checklists, and missing-info red flags. Output follows a versioned JSON contract consumed by the Bantay mascot/theming UI, persisted in local SQLite, with DB-backed re-check alarms reconciled at boot/launch.

## Technical Context

**Language/Version**: Dart 3.x / Flutter 3.24+ (stable channel)

**Primary Dependencies**: `llama.cpp` native library via Dart FFI (in-process GGUF inference, GBNF-constrained JSON decoding, token streaming); `google_mlkit_text_recognition` (offline OCR, Android + iOS); `flutter_local_notifications` (+ exact alarms); `sqflite` (SQLite); `flutter_test` / `integration_test` / golden tests

**Storage**: SQLite in app-private storage (incidents, checklist state, alarms, cached protocol guides, household profile); GGUF model (~1.0 GB) bundled as an app asset. No cloud storage, no sync (SQLCipher hardening deferred — see research R7)

**Testing**: `flutter_test` unit + golden theming tests; contract tests validating inference output against `contracts/bantay-analysis.schema.json`; `integration_test` on emulator/device in airplane mode against a golden corpus of ~20–50 advisories; CI uses a 0.5B smoke model (nightly runs use the full 1.5B model)

**Target Platform**: Android 8.0+ (API 26) primary — hackathon demo device; iOS 15+ secondary build

**Project Type**: mobile-app (deliberately no backend — the "Tarsi" formula forbids cloud servers)

**Performance Goals**: structured brief (category/severity/location/checklist skeleton) displayed ≤2s; full LLM-enriched brief streamed, p95 ≤15s on mid-range Android (≈6 GB RAM); OCR extraction ≤1s; 60 fps theme transitions; inference RAM ≤1.5 GB

**Constraints**: 100% offline — zero network egress at any point (verifiable in airplane mode); no accounts/auth; five fixed crisis categories × three severity states × three languages (EN/TL/CEB); hackathon build ≈1.2 GB APK (model bundled; see research R11)

**Scale/Scope**: single device, single user; ~7 screens; 5 crisis types, 3 severity states, 3 languages; golden test corpus of 20+ advisories; history retained until user deletion

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Source**: `.specify/memory/constitution.md` is an **unfilled template** (placeholder principles only — no ratified project principles). No constitution-defined gates are enforceable. Substituted spec-derived gates below; any constitution ratified later must be re-checked against this plan.

| # | Gate (from spec) | Design answer | Status |
|---|------------------|---------------|--------|
| G1 | Zero network egress during any workflow (FR-012, SC-007) | In-process FFI inference; no HTTP client in the analysis path; OCR and notifications fully local | PASS |
| G2 | No accounts, auth, or registration (FR-012) | No identity primitives anywhere in the data model | PASS |
| G3 | All user data local, deletable (FR-010, FR-015) | SQLite in app-private storage; delete = row removal, no backups off-device | PASS |
| G4 | Instant trilingual switch without re-analysis (FR-009) | Single-pass trilingual JSON contract (`contracts/bantay-analysis.schema.json`) | PASS |
| G5 | Structured brief ≤2s with no connectivity (FR-013, SC-001) | Two-stage hybrid: deterministic fast-path skeleton <2s + streamed LLM enrichment (research R4) | PASS |
| G6 | Never fabricate missing details (FR-005, SC-002) | Grammar-constrained decoding + schema validation + source-grounded prompt; fast-path emits only extracted/template content; golden-corpus fabrication review | PASS |

**Post-Phase-1 re-check**: all six gates remain PASS against the delivered designs (schema, data model, contracts, quickstart). No violations → **Complexity Tracking remains empty**.

## Project Structure

### Documentation (this feature)

```text
specs/001-offline-emergency-copilot/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── bantay-analysis.schema.json
│   ├── local-inference.md
│   └── ui-actions.md
├── checklists/
│   └── requirements.md  # From /speckit.specify
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
apps/
└── mobile/                      # Flutter app (Android + iOS)
    ├── lib/
    │   ├── main.dart
    │   ├── core/                # theme (crimson/amber/slate tokens), constants, errors
    │   ├── inference/           # llama.cpp FFI bindings, grammar, streaming pipeline, fast-path classifier
    │   ├── ingest/              # paste intake, ML Kit OCR capture
    │   ├── domain/              # entities, use-cases (analyze, checklist, alarms, history)
    │   ├── data/                # SQLite repositories, model-asset loader
    │   ├── notifications/       # scheduling + boot/launch reconciliation
    │   └── ui/                  # screens: home, brief, history, guides, settings; Bantay mascot widget
    ├── assets/
    │   ├── models/              # Qwen2.5-1.5B-Instruct Q4_K_M .gguf (+ Llama-3.2-1B fallback)
    │   ├── bantay/              # mascot art: alert / caution / info states
    │   └── guides/              # cached emergency protocol guides (EN/TL/CEB)
    └── test/                    # unit, golden, contract tests
        └── integration/         # airplane-mode end-to-end scenarios

docs/                            # project_idea.md (blueprint), techstack.md
specs/001-offline-emergency-copilot/
```

**Structure Decision**: Single offline mobile project at `apps/mobile/`. The pre-existing empty `apps/backend/` and `apps/frontend/` placeholders do not fit a zero-server product — `apps/backend/` is intentionally **not created** (no cloud per the Tarsi formula) and `apps/frontend/` should be removed in favor of `apps/mobile/` (a mobile app is neither frontend nor backend of anything). Documentation stays under `docs/` and `specs/`.

## Complexity Tracking

No constitution violations to justify (see Constitution Check — all gates PASS, constitution itself is an unfilled template).
