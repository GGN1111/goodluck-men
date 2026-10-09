# Phase 1 Data Model: SignalReady Pocket — Offline Emergency Co-Pilot

**Branch**: `001-offline-emergency-copilot` | **Date**: 2026-10-09
**Spec references**: [spec.md](./spec.md) (Key Entities, FRs) · [contracts/bantay-analysis.schema.json](./contracts/bantay-analysis.schema.json)

All entities live in local SQLite (research R7). No entity carries identity, account, or network fields (FR-012).

---

## Enums

### CrisisType (FR-002)
`FLOOD | FIRE | SECURITY | BLACKOUT | GENERAL` — exhaustive, exactly one per incident. Fast-path and LLM must agree; on disagreement the fast-path value is kept for the skeleton and the disagreement is logged for corpus review (never blocks display).

### SeverityState (FR-003)
| State | Meaning | Theme |
|---|---|---|
| `ALERT` | Active life-threatening emergency | Alert Crimson `#C53030`, Bantay alert art |
| `CAUTION` | Moderate threat, missing crucial details, unverified rumor | Warning Amber `#D69E2E`, Bantay caution art |
| `INFO` | Non-life-threatening utility update | Primary Slate `#1A202C` + blue accent, Bantay info art |

Assigned once at skeleton creation; LLM may only **raise or confirm** severity, never silently downgrade an ALERT (safety rule — a downgrade requires the source text to clearly be non-emergency and is validated in corpus tests).

### Language
`en | tl | ceb` — display-only. All brief content exists for all three languages before display (FR-009, research R5).

### AnalysisStatus
`skeleton → enriched | failed`
- `skeleton` — fast-path brief rendered (≤2s, FR-013).
- `enriched` — validated LLM output merged in.
- `failed` — LLM failed after one repair retry; degraded brief retained, user offered retry (FR-014).

### AlarmStatus
`scheduled → fired | cancelled` — `fired` set when the notification is delivered; `cancelled` on user cancel. Reconciliation re-arms `scheduled` rows only (research R8).

### ChecklistStepState
`pending ⇄ done` — freely toggleable (FR-006).

---

## Entities

### IncidentRecord
One analyzed advisory (spec: Key Entities).

| Field | Type | Rules |
|---|---|---|
| `id` | integer PK | auto-increment |
| `created_at` | datetime | set at paste/OCR intake |
| `source_type` | `text \| ocr` | how the advisory arrived |
| `source_text` | text | raw input preserved verbatim, always (FR-014 retry; FR-005 provenance) — OCR failures store the extraction attempt + error |
| `crisis_type` | CrisisType | required, one of five (FR-002) |
| `severity` | SeverityState | required (FR-003) |
| `location` | text nullable | only if present/extractable from source; never invented (FR-005) |
| `time_or_status` | text nullable | same provenance rule |
| `summary_en/tl/ceb` | text ×3 | skeleton: template text derived from source; enriched: LLM (FR-001, FR-009) |
| `speech_en/tl/ceb` | text ×3 | Bantay speech, same staging |
| `status` | AnalysisStatus | see transitions below |
| `model_notice` | text nullable | set when `failed`/degraded (FR-014) |

**Validation**: any of `location`/`time_or_status`/summaries may be empty-string only if absent in source — corpus test asserts no field contains information not derivable from `source_text` (FR-005, SC-002).

**Relationships**: 1→N `ActionStep`, 1→N `MissingWarning`, 1→N `ReCheckAlarm`.

### ActionStep
| Field | Type | Rules |
|---|---|---|
| `id` | integer PK | |
| `incident_id` | FK → IncidentRecord, cascade delete | |
| `priority` | integer ≥1 | ordered; skeleton uses template order, enrichment may reorder/rewrite text |
| `text_en/tl/ceb` | text ×3 | all required (FR-009) |
| `state` | ChecklistStepState | default `pending` (FR-006) |
| `origin` | `template \| llm` | provenance for quality review |

**Rules**: target three immediate steps (FR-006); max 5 enforced (a longer list dilutes prioritization); steps are situation-specific — corpus test asserts a FLOOD incident's template steps differ from BLACKOUT's (FR-006 acceptance scenario 2).

### MissingWarning
| Field | Type | Rules |
|---|---|---|
| `id` | integer PK | |
| `incident_id` | FK, cascade delete | |
| `code` | enum: `EVAC_CENTER \| HOTLINE \| ZONE \| OTHER` | drives icon/label (FR-004) |
| `text_en/tl/ceb` | text ×3 | rendered as prominent red-flag list |
| `origin` | `fastpath \| llm` | |

**Rules**: emitted only for details genuinely absent from source (FR-004/FR-005); zero spurious warnings is a corpus acceptance assertion (SC-002).

### ReCheckAlarm
| Field | Type | Rules |
|---|---|---|
| `id` | integer PK | |
| `incident_id` | FK, cascade delete | |
| `fire_at` | datetime | must be > create time; user-selectable interval (15m/1h/custom) |
| `message` | text | e.g. "Bantay Alert: re-check Marikina River level" — localized at scheduling time for the chosen language |
| `status` | AlarmStatus | transitions below |
| `platform_handle` | text nullable | OS notification id for cancel/rewrite |

**State transitions**: `scheduled → fired` (delivery) · `scheduled → cancelled` (user) · `scheduled → scheduled` (boot/launch reconciliation re-arms it — research R8, SC-006, reboot edge case).

### EmergencyProtocolGuide
| Field | Type | Rules |
|---|---|---|
| `id` | integer PK | |
| `slug` | text unique | e.g. `flood-go-bag`, `fire-response` |
| `title_en/tl/ceb` | text ×3 | |
| `body_en/tl/ceb` | text ×3 | |
| `crisis_type` | CrisisType | browsable by category |

**Rules**: read-only, bundled at install (asset → seeded into SQLite on first run); never network-fetched (FR-012).

### HouseholdProfile *(optional, user-editable — spec Key Entities)*
| Field | Type | Rules |
|---|---|---|
| `id` | PK, single row | v1 supports one profile |
| `meeting_point` | text nullable | |
| `evac_destination` | text nullable | user-provided — distinguished from advisory-derived location in UI |
| `notes` | text nullable | |
| `updated_at` | datetime | |

**Rules**: purely local; personalization only appends user-supplied context to checklists — never merges profile data into `source_text`-derived fields (keeps FR-005 provenance clean).

### Settings (single-row, implicit)
`language: Language` (default `tl`), `low_power_mode: bool` (FR-011), `notifications_granted: bool` (runtime), `model_variant: primary | fallback | missing` (research R2/R11).

---

## State diagrams

**Incident lifecycle**
```text
[paste/OCR] → skeleton(≤2s) ──LLM valid──→ enriched
                  │                └─LLM fail after 1 retry─→ failed (degraded brief + retry offer)
                  └─ user deletes → (rows cascaded away, FR-015)
```

**Severity & theme**: immutable per incident except safety-rule raise/confirm (never silent downgrade of ALERT).

**Alarm**: `scheduled → fired | cancelled`, with idempotent re-arm at launch/BOOT_COMPLETED.

---

## Validation rules traceability

| Rule | FR/SC |
|---|---|
| Exactly one crisis category; one severity | FR-002, FR-003 |
| Trilingual completeness for brief/steps/warnings | FR-009 |
| No field content absent from `source_text` | FR-005, SC-002 |
| Warnings only for genuinely omitted critical details | FR-004, SC-002 |
| Checklist ≤5 steps, situation-specific, persistent done-state | FR-006, SC-008 |
| Alarms fire offline within 1 minute | FR-008, SC-006 |
| History survives restart, fully offline | FR-010, SC-008 |
| Permanent single-record delete | FR-015 |
| No account/egress fields anywhere | FR-012, SC-007 |
