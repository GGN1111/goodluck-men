# Contract: UI Actions & Screen States

**Branch**: `001-offline-emergency-copilot` | **Date**: 2026-10-09
**Consumers**: `lib/ui/` (screens) ← users; `lib/domain/` (use-cases) implements responses
**Related**: [spec.md §6 screen layout](../spec.md) · [bantay-analysis.schema.json](./bantay-analysis.schema.json) · [data-model.md](../data-model.md)

UI contract: every user action, the observable response, and the state it mutates. All actions must succeed with networking disabled.

---

## Screens

| Screen | Purpose |
|---|---|
| **Home / Brief** | Intake (paste or image), Bantay mascot card, action checklist, missing-info red flags, re-check alarm, language switcher (matches spec §6 layout) |
| **History** | Past IncidentRecords with brief, severity, warnings, checklist state; delete |
| **Guides** | Cached EmergencyProtocolGuides browsable by crisis type (offline reference) |
| **Settings** | Language default, low-power/high-contrast mode, notification status, model status |

Global chrome: header shows "100% GRID-PROOF CRISIS ENGINE" + airplane/offline indicator (informational badge, not a network probe).

---

## Action → response contract

### Intake

| # | Action | Response | Mutates |
|---|---|---|---|
| A1 | Paste text + tap analyze | ≤2s: skeleton brief renders — theme to `bantay_state`, Bantay art swaps, category/location/status line, template checklist, warnings from fast-path; status "Bantay is analyzing…" while enrichment streams | new IncidentRecord (`status=skeleton`) |
| A2 | Pick/photograph screenshot | OCR ≤1s → same as A1 with `source.type=ocr` | new IncidentRecord |
| A3 | OCR fails (blur/no text) | Message: couldn't read image + "type/paste instead" — **never** a fabricated brief; source attempt preserved | no record, or record `status=failed` if partial |
| A4 | Paste empty / non-emergency text | "No emergency content detected" + retry — no crisis invented (edge case) | no record (or `GENERAL/INFO` only if genuinely advisory-like) |
| A5 | Enrichment completes | Skeleton fields replaced in place: trilingual summary + speech, refined steps, red flags; status `enriched`; checklist tick state and ids preserved | IncidentRecord → `enriched` |
| A6 | Enrichment fails after 1 repair | Degraded brief stays visible + "analysis limited" notice + Retry (FR-014) | status `failed` |

### Brief interactions

| # | Action | Response | Mutates |
|---|---|---|---|
| B1 | Toggle checklist step | Immediate `pending⇄done`, visually distinct; persists across restart (SC-008) | ActionStep.state |
| B2 | Set re-check alarm (15m / 1h / custom) | Confirmation chip with fire time; works in airplane mode; fires within 1 min (SC-006) | ReCheckAlarm `scheduled` |
| B3 | Cancel alarm | Chip clears; platform notification cancelled | status `cancelled` |
| B4 | Language switch `TAGALOG \| EN \| CEBUANO` | ≤1s all brief text (summary/speech/steps/warnings) swaps; **no** re-analysis, severity/checklist state unchanged (FR-009) | Settings.language (display) |
| B5 | Analyze new advisory while one open | Previous record auto-saved to History; new skeleton renders | new record |

### History & settings

| # | Action | Response | Mutates |
|---|---|---|---|
| C1 | Open History record | Full brief + checklist state offline (SC-008) | — |
| C2 | Delete record | Permanent, cascades steps/warnings/alarms; gone on restart (FR-015) | rows removed |
| C3 | Toggle low-power mode | All screens render high-contrast dark theme (`#1A202C` base) per FR-011 | Settings.low_power_mode |
| C4 | Notifications denied | Banner explains reminders won't appear + in-app re-check prompt fallback (FR-008 edge case) | Settings.notifications_granted |
| C5 | Reboot / relaunch | Alarms reconciled from DB: pending re-armed, fired/cancelled untouched (research R8); nothing silently lost | ReCheckAlarm re-arm |
| C6 | Edit HouseholdProfile | Saved locally; may append context to *future* checklists only — never alters source-derived fields (FR-005) | HouseholdProfile |

---

## Severity → visual state map (FR-003, golden-testable)

| `bantay_state` | Theme tokens | Bantay art |
|---|---|---|
| `ALERT` | Alert Crimson `#C53030` accents, red banner | spread wings / vest alert pose |
| `CAUTION` | Warning Amber `#D69E2E` accents, amber banner | cautious pose |
| `INFO` | Primary Slate `#1A202C` + blue accent, blue banner | calm/info pose |

Missing-info red flags always render in Warning Amber regardless of severity (they are FR-004 safety shields).

---

## Invariants (cross-cutting)

1. **Offline**: every action above succeeds in airplane mode; zero socket opens (SC-007).
2. **Provenance**: UI never displays a field the pipeline did not source from `source_text`/template/profile — no UI-level enrichment of facts (FR-005).
3. **No auth wall**: app opens directly to Home; no login, onboarding gate, or account prompt (FR-012).
4. **Progressive trust**: skeleton content is visually distinguishable from enriched content (subtle "analyzing" shimmer) so users know what is final.
5. **Language completeness**: any visible brief text comes in `en`/`tl`/`ceb` triplets; partial translation triggers the R5 warning badge, not partial display.
