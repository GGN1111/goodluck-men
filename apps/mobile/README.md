# SignalReady Pocket (apps/mobile)

100% offline, grid-proof emergency co-pilot. Flutter app: paste/OCR an
advisory → fast-path structured brief (≤2 s) → optional on-device LLM
enrichment (trilingual EN/TL/CEB), checklist, red-flag warnings, re-check
alarms, offline guides.

## Prerequisites

- Flutter stable (this repo builds with 3.44.x) + Android SDK
- Demo device/emulator: **≥6 GB RAM**, Android 8.0+
- Model assets (optional but recommended) in `assets/models/`:
  - `qwen2.5-1.5b-instruct-q4_k_m.gguf` (primary, ~1.0 GB)
  - `llama-3.2-1b-instruct-q4_k_m.gguf` (fallback, ~0.7 GB)
  - `qwen2.5-0.5b-instruct-q4_k_m.gguf` (CI smoke, ~0.5 GB)

Without a GGUF the app runs **fast-path-only**: skeleton briefs, templates,
warnings, guides, history all work; enrichment shows the "analysis limited"
degraded path (FR-014 / research R11).

## Build & run

```bash
cd apps/mobile
flutter pub get
flutter build apk --debug      # debug build bundles assets/models/
flutter install                # or: flutter run -d <device-id>
```

First launch opens the local SQLite DB (bundled guides seeded), reconciles
any pending re-check alarms, and reports the model variant in
Settings → Status.

## Tests

```bash
flutter analyze
flutter test                                   # full suite (unit + widget + integration + goldens)
flutter test --update-goldens test/golden/     # regenerate golden baselines
```

Integration suites (`test/integration/`) run on the host against real
SQLite via `sqflite_common_ffi`, with an `IOOverrides` guard asserting zero
socket opens (SC-007).

## Model asset install

Copy the GGUF files into `assets/models/` (already declared in
`pubspec.yaml`), then rebuild. `AppGraph` copies the primary model into the
app documents dir on first launch and reports `model_variant=primary` in
Settings; a missing file leaves the variant as `missing`.

## Layout

- `lib/core/` — composition root (`AppGraph`), theme tokens, l10n helpers
- `lib/domain/` — entities, analysis use-case, delete use-case, validator
- `lib/data/` — SQLite schema/migrations + repositories
- `lib/inference/` — fast-path classifier, templates, warning rules, llama.cpp engine, prompt/GBNF
- `lib/ingest/` — paste normalization + OCR service
- `lib/notifications/` — exact-alarm scheduler + reboot reconciler
- `lib/ui/` — Brief/History/Guides/Settings screens + Bantay mascot
