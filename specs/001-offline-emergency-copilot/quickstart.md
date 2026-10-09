# Quickstart & Validation Guide: SignalReady Pocket

**Branch**: `001-offline-emergency-copilot` | **Date**: 2026-10-09
**Purpose**: runnable, end-to-end validation of the plan's design artifacts. Implementation bodies, migrations, and full test suites belong in `tasks.md` (Phase 2) — this guide only says *what to run and what to expect*.

**Contracts referenced**: [bantay-analysis.schema.json](./contracts/bantay-analysis.schema.json) · [local-inference.md](./contracts/local-inference.md) · [ui-actions.md](./contracts/ui-actions.md) · [data-model.md](./data-model.md)

---

## 1. Prerequisites

- Flutter SDK (stable ≥3.24), Android SDK; demo device or emulator with **≥6 GB RAM**, Android 8.0+
- Xcode 15+ only if building the secondary iOS target
- Model assets placed in `apps/mobile/assets/models/`:
  - `qwen2.5-1.5b-instruct-q4_k_m.gguf` (primary, ~1.0 GB)
  - `llama-3.2-1b-instruct-q4_k_m.gguf` (fallback, ~0.7 GB)
  - CI smoke model: `qwen2.5-0.5b-instruct-q4_k_m.gguf`
- Golden corpus: 20+ advisories (floods, fires, blackouts, security, rumor, non-emergency, empty) with reviewer-expected `crisis_type`/`bantay_state`/required warnings — seeded under `apps/mobile/test/corpus/`

## 2. Setup

```bash
cd apps/mobile
flutter pub get
flutter build apk --debug        # debug build includes the bundled model asset
flutter install                   # or flutter run
```

First launch runs `preflight()` (research R2): reports model variant + RAM class; missing model ⇒ Guides/History-only state (research R11).

## 3. Validation scenarios

Run **all scenarios with the device in airplane mode** (the default acceptance posture).

### V1 — Core offline parse (→ SC-001, FR-001/013, G5)
1. Airplane mode ON. Open app, paste the spec's Marikina flood advisory (or corpus #1).
2. **Expect**: structured brief within **2 s** — ALERT theme (crimson), Bantay alert art, `FLOOD`, location/time line, template checklist, warnings. Status shows "analyzing…" then flips to enriched with trilingual summary + refined steps within ~15 s p95.
3. **Measure & record separately**: (a) skeleton latency (must be ≤2000 ms), (b) enrichment completion latency (target ≤15 s). *Note: the ≤2s claim is the skeleton — see research R4; if stakeholders demand fully-enriched ≤2s, re-run with the 0.5B fallback + capped `maxTokens: 120` and record the quality trade-off.*

### V2 — Missing-info red flags (→ SC-002, FR-004/005)
1. Paste an evacuation order with **no** evacuation center and **no** hotline (corpus fixture).
2. **Expect**: warnings `EVAC_CENTER` and `HOTLINE` both present in EN/TL/CEB.
3. Paste a complete advisory → **expect zero** warnings (no fabrication).
4. Run the whole corpus through `flutter test --plain-name "corpus"` → schema validation + expected category/severity + required warnings must pass 100%; manually review enriched outputs for any field content absent from source (zero-fabrication clause).

### V3 — Screenshot ingestion (→ FR-007)
1. Load a clear FB-notice screenshot → **expect** brief equivalent to pasting its text.
2. Load a blurry/text-free image → **expect** "couldn't read image" + paste fallback, never a brief.

### V4 — Checklist & persistence (→ FR-006, SC-008)
1. Tick steps 1 and 2, force-kill the app, relaunch offline.
2. **Expect**: ticks preserved; History shows the record with state intact.

### V5 — Re-check alarm offline (→ SC-006, FR-008)
1. Schedule a re-check 1 minute out while in airplane mode; wait.
2. **Expect**: notification fires within **±1 min**.
3. Schedule another, reboot the device (edge case), wait past fire time.
4. **Expect**: alarm still fires (boot reconciliation) **or** an explicit reschedule notice — never silent loss (research R8).

### V6 — Instant language switch (→ SC-005, FR-009)
1. On an enriched brief, toggle `TAGALOG → EN → CEBUANO`.
2. **Expect**: all brief text swaps in **<1 s**, no "analyzing…" reappears, severity + tick state unchanged. If Cebuano carries the translation-warning badge, confirm `model_notice` behavior (research R5).

### V7 — Zero-egress proof (→ SC-007, G1)
1. With airplane mode ON, run V1–V6; simultaneously monitor traffic (device data-usage screen or host-side proxy for emulator).
2. **Expect**: **0 bytes** transferred across the entire workflow. `flutter test integration` includes an automated socket-egress assertion that must pass.

### V8 — Degradation paths (→ FR-014, R3)
1. Simulate model failure (rename asset, restart) → **expect** "model not installed" with Guides/History still working.
2. Force a repair-retry failure (test hook injecting malformed raw output) → **expect** degraded brief retained + "analysis limited" + Retry — never a blank screen or fabricated content.

### V9 — Blackout mode & delete (→ FR-011/015, SC-008)
1. Toggle low-power mode → all screens render high-contrast dark theme.
2. Delete a record → gone immediately and after restart (cascades per data model).

### V10 — Non-emergency & odd inputs (→ edge cases)
Empty paste, grocery list, foreign-language text, 20k-char forward → each yields "no emergency content" or a clearly-limited analysis; no invented crisis, no crash.

## 4. Performance budget checklist

| Metric | Target | Scenario |
|---|---|---|
| Skeleton brief display | ≤2 s offline | V1(a) |
| Enrichment completion | p95 ≤15 s (mid-range) | V1(b) |
| OCR extraction | ≤1 s | V3 |
| Language switch | <1 s | V6 |
| Alarm firing | ±1 min | V5 |
| Egress | 0 bytes | V7 |
| UI | 60 fps theme transitions | golden/frame tests |

## 5. Definition of done (design phase exit)

- All V1–V10 pass on the demo device in airplane mode.
- Corpus contract tests green (schema + classification + warnings).
- SC-001 recorded with the two-number methodology from research R4.
- No gate regressions against the Constitution Check table in [plan.md](./plan.md).
