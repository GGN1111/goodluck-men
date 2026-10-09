# Tasks: SignalReady Pocket â€” Offline Emergency Co-Pilot

**Input**: Design documents from `/specs/001-offline-emergency-copilot/`

**Prerequisites**: [plan.md](./plan.md) (tech stack, structure), [spec.md](./spec.md) (7 user stories P1â€“P3), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: Included â€” explicitly required by plan.md testing strategy (golden corpus contract tests, airplane-mode integration tests, egress assertion) and quickstart.md validation scenarios V1â€“V10. They validate alongside implementation (not strict red-green TDD).

**Organization**: Tasks grouped by user story so each story is independently implementable and testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1â€“US7 per spec.md user stories
- Every task includes an exact file path under `apps/mobile/` (Flutter single project per plan.md)

## Path Conventions

Mobile single project: all source under `apps/mobile/` (`lib/`, `assets/`, `test/`). Repository-relative paths shown.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization per plan.md structure

- [X] T001 Scaffold Flutter project at `apps/mobile/` per plan.md tree (`lib/{core,inference,ingest,domain,data,notifications,ui}`, `assets/{models,bantay,guides}`, `test/{contract,corpus,unit,integration,golden}`)
- [X] T002 Add dependencies to `apps/mobile/pubspec.yaml`: `sqflite`, `path_provider`, `flutter_local_notifications`, `google_mlkit_text_recognition`, `image_picker`, `ffi`; enable lint via `apps/mobile/analysis_options.yaml`
- [X] T003 [P] Define design tokens (Primary Slate `#1A202C`, Alert Crimson `#C53030`, Warning Amber `#D69E2E`, low-power dark theme) in `apps/mobile/lib/core/theme/app_theme.dart`
- [X] T004 [P] Create asset directories and model-asset placement README in `apps/mobile/assets/models/README.md`, `apps/mobile/assets/bantay/`, `apps/mobile/assets/guides/`
- [X] T005 [P] Seed golden corpus (20+ advisories: floods, fires, blackouts, security, rumor, non-emergency, empty; with expected `crisis_type`/`bantay_state`/required warnings) in `apps/mobile/test/corpus/corpus.json`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Storage, entities, contracts, intake â€” every user story depends on these

**âš ï¸ CRITICAL**: No user story work can begin until this phase is complete

- [X] T006 Create SQLite schema + versioned migrations per data-model.md in `apps/mobile/lib/data/database.dart` and `apps/mobile/lib/data/migrations/`
- [X] T007 [P] Implement enums and entities (CrisisType, SeverityState, Language, AnalysisStatus, AlarmStatus, IncidentRecord, ActionStep, MissingWarning, ReCheckAlarm, EmergencyProtocolGuide, HouseholdProfile, Settings) in `apps/mobile/lib/domain/entities.dart`
- [X] T008 [P] Implement analysis validator against `bantay-analysis.schema.json` (enums, trilingual required fields, checklist 1â€“5 items, copy-detect warning hook) in `apps/mobile/lib/domain/analysis_validator.dart`
- [X] T009 Implement repositories (incident, checklist, warnings, alarms, guides, settings, profile â€” single-row CRUD, cascade delete) in `apps/mobile/lib/data/repositories/`
- [X] T010 [P] Bundle and seed emergency protocol guides (EN/TL/CEB) from `apps/mobile/assets/guides/` via `apps/mobile/lib/data/guide_seed.dart`
- [X] T011 Implement intake service (paste normalization, 20k-char truncation with notice, `source_type` assignment) in `apps/mobile/lib/ingest/intake.dart`
- [X] T012 Create app shell, navigation, and screen routing (Home/Brief, History, Guides, Settings) in `apps/mobile/lib/main.dart` and `apps/mobile/lib/ui/app_router.dart`

**Checkpoint**: Foundation ready â€” user story implementation can now begin (US1 first)

---

## Phase 3: User Story 1 - Instant Offline Alert Decoding (Priority: P1) ðŸŽ¯ MVP

**Goal**: Paste raw advisory in airplane mode â†’ structured brief (category, severity + theme + Bantay state, location/status, checklist skeleton) rendered â‰¤2s, then streamed LLM enrichment with plain-language trilingual summary â€” zero egress (spec US1, FR-001/002/003/005/013)

**Independent Test**: Airplane mode ON, paste the Marikina flood advisory â†’ ALERT-themed brief with skeleton within 2s (quickstart V1), enrichment completes with validated JSON (quickstart V1b), 0 bytes egress (quickstart V7)

### Tests for User Story 1

- [X] T013 [P] [US1] Contract test: validator accepts golden enriched payload / rejects malformed (wrong enum, missing language field) in `apps/mobile/test/contract/analysis_schema_test.dart`
- [X] T014 [P] [US1] Corpus test: fast-path classifies expected `crisis_type` + `bantay_state` for all 20+ corpus entries in `apps/mobile/test/corpus/fastpath_corpus_test.dart`

### Implementation for User Story 1

- [X] T015 [P] [US1] Implement deterministic fast-path classifier (keyword/pattern heuristics, location/time extraction with source-provenance only) in `apps/mobile/lib/inference/fastpath_classifier.dart`
- [X] T016 [P] [US1] Implement per-crisis template checklists (3 steps, distinct per FLOOD/FIRE/SECURITY/BLACKOUT/GENERAL) in `apps/mobile/lib/inference/template_checklists.dart`
- [X] T017 [US1] Bind llama.cpp via Dart FFI: `loadModel`/`unload`/`preflight` with primary Qwen2.5-1.5B and Llama-3.2-1B fallback (research R1/R2/R11) in `apps/mobile/lib/inference/llama_engine.dart`
- [X] T018 [P] [US1] Author Bantay system prompt (spec Â§5 extended: trilingual output, no fabrication, 5 types Ã— 3 states) and GBNF grammar `bantay-json-v1` in `apps/mobile/lib/inference/bantay_prompt.dart` and `apps/mobile/assets/models/bantay-json-v1.gbnf`
- [X] T019 [US1] Implement enrichment pipeline: `generateStream` â†’ schema validation â†’ single repair retry â†’ degraded `failed` status (research R3) in `apps/mobile/lib/inference/enrichment_pipeline.dart`
- [X] T020 [US1] Implement analyze use-case orchestration (intake â†’ skeleton â‰¤2s â†’ stream enrichment â†’ persist IncidentRecord) in `apps/mobile/lib/domain/analyze_advisory.dart`
- [X] T021 [US1] Build Home/Brief screen: paste box, Bantay mascot card with severity-driven theme/art swap, skeletonâ†’enriched progressive states (contracts/ui-actions.md A1/A5/A6) in `apps/mobile/lib/ui/home_screen.dart` and `apps/mobile/lib/ui/bantay_mascot.dart`
- [X] T022 [US1] Add latency probe recording skeleton-display and enrichment-completion times for the SC-001 two-number method (research R4) in `apps/mobile/lib/inference/latency_probe.dart`
- [X] T023 [US1] End-to-end smoke: airplane-mode paste scenario wired to quickstart V1 in `apps/mobile/test/integration/offline_parse_smoke_test.dart`

**Checkpoint**: US1 fully functional and independently testable (MVP)

---

## Phase 4: User Story 2 - Situation-Specific Action Checklist (Priority: P1)

**Goal**: Crisis-specific checklist rendered on the brief, tickable, tick state persists across restart; enrichment rewrites step text without losing user state (spec US2, FR-006)

**Independent Test**: Paste flood vs blackout advisory â†’ different step sets; tick steps 1â€“2, force-kill, relaunch offline â†’ ticks preserved (quickstart V4)

### Tests for User Story 2

- [X] T024 [P] [US2] Unit test: checklist toggle state round-trips through repository; flood vs blackout templates differ; max 5 steps enforced in `apps/mobile/test/unit/checklist_test.dart`

### Implementation for User Story 2

- [X] T025 [P] [US2] Build ActionChecklist widget (toggleable rows, done styling, priority order, trilingual text) in `apps/mobile/lib/ui/action_checklist.dart`
- [X] T026 [US2] Implement checklist repository interactions (toggle, persist, load by incident) in `apps/mobile/lib/data/repositories/checklist_repository.dart`
- [X] T027 [US2] Implement enrichment merge preserving step ids and user `state` while replacing `template` text with `llm` text (contracts/ui-actions.md A5) in `apps/mobile/lib/inference/merge_enriched.dart`

**Checkpoint**: US1 + US2 both work independently

---

## Phase 5: User Story 3 - Missing Information Red Flags (Priority: P2)

**Goal**: Omitted critical details (evacuation center, hotline, zone) surfaced as prominent amber warnings; zero fabricated warnings; no invented facts anywhere (spec US3, FR-004/005)

**Independent Test**: Paste evacuation order missing evac center + hotline â†’ both warnings shown in EN/TL/CEB; paste complete advisory â†’ zero warnings (quickstart V2)

### Tests for User Story 3

- [X] T028 [P] [US3] Corpus test: required warnings present for incomplete fixtures, zero warnings for complete fixtures in `apps/mobile/test/corpus/warnings_corpus_test.dart`
- [X] T029 [P] [US3] Provenance test: `location`/`time_or_status` values appear verbatim in `source_text` across corpus (FR-005/SC-002) in `apps/mobile/test/corpus/provenance_test.dart`

### Implementation for User Story 3

- [X] T030 [P] [US3] Implement fast-path warning rules (EVAC_CENTER/HOTLINE/ZONE detection by crisis type) in `apps/mobile/lib/inference/warning_rules.dart`
- [X] T031 [US3] Build MissingWarnings card (Warning Amber styling, always visible regardless of severity, trilingual) in `apps/mobile/lib/ui/missing_warnings_card.dart`
- [X] T032 [US3] Surface LLM-generated warnings through validation merge with `origin=llm` alongside fast-path warnings in `apps/mobile/lib/domain/analyze_advisory.dart`

**Checkpoint**: US1â€“US3 independently functional

---

## Phase 6: User Story 4 - Screenshot Ingestion (Priority: P2)

**Goal**: Load a notice screenshot â†’ same brief as pasted text; unreadable image â†’ clear fallback, never a fabricated brief (spec US4, FR-007/014)

**Independent Test**: Load clear FB-notice screenshot â†’ equivalent brief; load blurry image â†’ "couldn't read" + paste fallback (quickstart V3)

### Tests for User Story 4

- [X] T033 [P] [US4] Unit test: OCR failure path returns fallback notice and preserves source attempt, no record fabricated in `apps/mobile/test/unit/ocr_fallback_test.dart`

### Implementation for User Story 4

- [X] T034 [P] [US4] Implement offline OCR service (ML Kit text recognition, â‰¤1s target) in `apps/mobile/lib/ingest/ocr_service.dart`
- [X] T035 [US4] Build image intake flow (pick/photograph â†’ OCR â†’ intake as `source_type=ocr`) in `apps/mobile/lib/ui/image_intake.dart`
- [X] T036 [US4] Wire OCR failure/fallback UI state into Home screen (contracts/ui-actions.md A3) in `apps/mobile/lib/ui/home_screen.dart`

**Checkpoint**: US4 works independently (image input path joins paste path at intake)

---

## Phase 7: User Story 5 - Local Re-Check Alarms (Priority: P2)

**Goal**: Schedule re-check reminders from a brief; fire in airplane mode within Â±1 min; survive reboot via DB reconciliation; graceful degradation when notifications denied (spec US5, FR-008)

**Independent Test**: Schedule +1 min alarm in airplane mode â†’ fires within window; schedule, reboot, wait â†’ fires or explicit reschedule notice (quickstart V5)

### Tests for User Story 5

- [X] T037 [P] [US5] Unit test: reconciler is idempotent (re-arm only `scheduled` rows), fire time math correct, cancel path clears platform handle in `apps/mobile/test/unit/alarm_reconciler_test.dart`

### Implementation for User Story 5

- [X] T038 [P] [US5] Implement alarm scheduler (flutter_local_notifications, exact alarms, DB row + platform handle) in `apps/mobile/lib/notifications/alarm_scheduler.dart`
- [X] T039 [US5] Implement boot/launch alarm reconciliation (idempotent re-arm; Android `BOOT_COMPLETED` receiver + launch hook per research R8) in `apps/mobile/lib/notifications/alarm_reconciler.dart` and `apps/mobile/android/app/src/main/AndroidManifest.xml`
- [X] T040 [US5] Build schedule/cancel controls on Brief screen (15m/1h/custom chips, confirmation, cancel) in `apps/mobile/lib/ui/recheck_alarm_button.dart`
- [X] T041 [US5] Implement notifications-denied degradation (banner + in-app re-check prompt fallback) in `apps/mobile/lib/ui/permission_notice.dart`

**Checkpoint**: US5 works independently; alarms reliable offline

---

## Phase 8: User Story 6 - Instant Three-Language Switching (Priority: P3)

**Goal**: Toggle TAGALOG/EN/CEBUANO in <1s across summary, speech, steps, warnings with zero re-analysis; state untouched (spec US6, FR-009)

**Independent Test**: On enriched brief, toggle languages â†’ all text swaps <1s, no "analyzingâ€¦" reappears, tick state unchanged; Cebuano copy-detect badge behaves (quickstart V6)

### Tests for User Story 6

- [X] T042 [P] [US6] Unit test: language switch remaps every content triplet in <1s with no pipeline invocation and preserved checklist/severity state in `apps/mobile/test/unit/language_switch_test.dart`

### Implementation for User Story 6

- [X] T043 [P] [US6] Implement language lookup layer (content â†’ `en|tl|ceb` field selection for all brief entities) in `apps/mobile/lib/core/l10n.dart`
- [X] T044 [P] [US6] Build language switcher widget + default in Settings, wired to `Settings.language` in `apps/mobile/lib/ui/language_switcher.dart`
- [X] T045 [US6] Enforce trilingual single-pass in system prompt + implement byte-identical copy detection â†’ `model_notice` warning badge (research R5) in `apps/mobile/lib/inference/translation_copy_check.dart`
- [X] T046 [US6] Apply language layer across Home/Brief widgets (summary, speech, checklist, warnings) in `apps/mobile/lib/ui/home_screen.dart`

**Checkpoint**: US6 works independently; no regressions in US1â€“US5

---

## Phase 9: User Story 7 - Incident History & Blackout-Friendly Display (Priority: P3)

**Goal**: Browse past incidents offline with full brief/checklist state; permanent delete; high-contrast low-power mode across all screens (spec US7, FR-010/011/015)

**Independent Test**: Parse two advisories â†’ History shows both offline after restart; delete one â†’ gone permanently; toggle low-power â†’ dark high-contrast everywhere (quickstart V9)

### Tests for User Story 7

- [X] T047 [P] [US7] Unit/integration test: history survives restart, delete cascades steps/warnings/alarms permanently, low-power theme applies app-wide in `apps/mobile/test/unit/history_delete_theme_test.dart`

### Implementation for User Story 7

- [X] T048 [P] [US7] Build History screen (list, open record with full brief + checklist state) in `apps/mobile/lib/ui/history_screen.dart`
- [X] T049 [US7] Implement permanent delete use-case with cascade (FR-015) in `apps/mobile/lib/domain/delete_incident.dart`
- [X] T050 [P] [US7] Build Settings screen with low-power/high-contrast toggle persisted to Settings row (FR-011) in `apps/mobile/lib/ui/settings_screen.dart`
- [X] T051 [P] [US7] Build Guides screen from seeded cache, browsable by crisis type, fully offline in `apps/mobile/lib/ui/guides_screen.dart`

**Checkpoint**: All 7 user stories independently functional

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: Cross-story hardening, full quickstart validation, demo readiness

- [X] T052 [P] Build HouseholdProfile edit screen (append-only context, never alters source-derived fields) in `apps/mobile/lib/ui/household_profile_screen.dart`
- [X] T053 [P] Golden tests for the three Bantay severity states/themes (ALERT/CAUTION/INFO) in `apps/mobile/test/golden/bantay_states_test.dart`
- [X] T054 Implement automated egress guard (assert zero socket opens across workflow â†’ SC-007) in `apps/mobile/test/integration/egress_guard_test.dart`
- [X] T055 Implement full airplane-mode E2E suite covering quickstart V1â€“V10 in `apps/mobile/test/integration/offline_e2e_test.dart`
- [ ] T056 Run full quickstart validation on demo device; record SC-001 two-number results and corpus pass rates in `specs/001-offline-emergency-copilot/validation-results.md`
- [X] T057 [P] Fill `docs/techstack.md` (currently empty) and add `apps/mobile/README.md` build/run/model-asset instructions per quickstart Â§1â€“2
- [X] T058 Run `flutter analyze` + full `flutter test` in `apps/mobile/`; fix all findings

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies â€” starts immediately
- **Foundational (Phase 2)**: Depends on Setup â€” **BLOCKS all user stories**
- **US1 (Phase 3)**: Depends on Foundational only â†’ MVP
- **US2 (Phase 4)**: Depends on Foundational; merge task T027 touches US1's `enrichment_pipeline` output â€” build after US1 core (T019) exists
- **US3 (Phase 5)**: Depends on Foundational + US1 (warnings render on brief; T032 extends US1 use-case)
- **US4 (Phase 6)**: Depends on Foundational (intake T011) + US1 (feeds analyze use-case)
- **US5 (Phase 7)**: Depends on Foundational (alarms table) + US1 (brief must exist to schedule from)
- **US6 (Phase 8)**: Depends on Foundational (Settings.language) + US1 content triplets; T046 touches US1 screen
- **US7 (Phase 9)**: Depends on Foundational (repositories/seeding) + US1 (records to list)
- **Polish (Phase 10)**: Depends on desired stories; T055/T056 need all stories

### User Story Dependencies

- **US1 (P1)**: After Foundational â€” no other-story dependencies â†’ **MVP**
- **US2 (P1)**: After Foundational + US1 merge point (T019/T027)
- **US3 (P2)**: After Foundational + US1 (brief screen hosts warnings)
- **US4 (P2)**: After Foundational + US1 (intake â†’ analyze)
- **US5 (P2)**: After Foundational + US1 (brief hosts alarm control)
- **US6 (P3)**: After Foundational + US1 (content triplets exist)
- **US7 (P3)**: After Foundational + US1 (records exist)

### Within Each Story

- Tests before/alongside their implementation tasks
- Models/entities â†’ services â†’ UI â†’ integration
- Contract/corpus tests marked [P] run first in parallel

### Parallel Opportunities

- Phase 1: T003, T004, T005 parallel
- Phase 2: T007, T008, T010 parallel
- US1: T013+T014 (tests) parallel; T015+T016+T018 parallel
- US3: T028+T029 parallel; T030 parallel with T031
- US5: T037 (test) parallel with T038
- US6: T043+T044 parallel
- US7: T048, T050, T051 parallel
- **Cross-story**: once Foundational lands, US7 (history/guides/settings) and US5 (alarm scheduler) can proceed in parallel with US1 by separate developers â€” they only need Foundational repositories, integrating at the Brief screen last

---

## Parallel Example: User Story 1

```bash
# Launch US1 tests together:
Task: "Contract test for analysis validator in apps/mobile/test/contract/analysis_schema_test.dart"
Task: "Corpus fast-path classification test in apps/mobile/test/corpus/fastpath_corpus_test.dart"

# Launch independent US1 components together:
Task: "Fast-path classifier in apps/mobile/lib/inference/fastpath_classifier.dart"
Task: "Template checklists in apps/mobile/lib/inference/template_checklists.dart"
Task: "System prompt + GBNF grammar in apps/mobile/lib/inference/bantay_prompt.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001â€“T005)
2. Complete Phase 2: Foundational (T006â€“T012) â€” **CRITICAL, blocks all stories**
3. Complete Phase 3: User Story 1 (T013â€“T023)
4. **STOP and VALIDATE**: airplane-mode paste â†’ brief â‰¤2s skeleton + enrichment + 0 egress (quickstart V1, V7)
5. Demo-ready MVP

### Incremental Delivery

1. Setup + Foundational â†’ foundation ready
2. + US1 â†’ validate â†’ **MVP demo** (paste â†’ Bantay brief)
3. + US2 â†’ checklists tick/persist â†’ demo adds interaction (spec demo step 3)
4. + US3 â†’ red flags â†’ safety-shield differentiator live
5. + US4 â†’ screenshots â†’ real-world GC image input
6. + US5 â†’ alarms â†’ "re-check in 1 hour" demo beat
7. + US6 â†’ language switch â†’ trilingual stage moment
8. + US7 â†’ history/guides/low-power â†’ full product polish
9. Polish â†’ full quickstart V1â€“V10 sign-off

### Parallel Team Strategy

1. Team completes Setup + Foundational together
2. After Foundational: Dev A = US1 (critical path to MVP); Dev B = US5 + US7 (Foundational-only integration, land at Brief screen after US1); Dev C = assets/guides/corpus (T005, T010, T053, T057)
3. Stories integrate independently at `home_screen.dart` â€” coordinate merges there only

---

## Notes

- Tasks marked **[P]** = different files, no dependencies; safe to dispatch concurrently
- Every task references an exact file path for direct execution
- Commit after each task or logical group; stop at any checkpoint to validate that story independently
- Watch item (research R4): SC-001 is measured as skeleton â‰¤2s AND enrichment completion separately â€” never conflate in validation-results.md
- Avoid: vague tasks, concurrent edits to `home_screen.dart`/`analyze_advisory.dart` (the two shared integration points)
