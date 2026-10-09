# Contract: Local Inference Interface (llama.cpp FFI)

**Branch**: `001-offline-emergency-copilot` | **Date**: 2026-10-09
**Consumers**: `lib/inference/` (implementer) ← `lib/domain/` analysis use-case (caller)
**Related**: [bantay-analysis.schema.json](./bantay-analysis.schema.json) · research R1, R3, R4

In-process Dart FFI interface — **no HTTP surface, no port, no network** (FR-012). This documents the contract shape, not the implementation.

---

## Lifecycle

```text
loadModel(variant) → ModelHandle        // primary Qwen2.5-1.5B-Q4; fallback Llama-3.2-1B-Q4; throws ModelMissing (research R11)
unload()                                // frees native memory (low-memory warning on Android)
preflight(): { variant, ramClass, ready }   // first-launch capability probe (research R2)
```

- `loadModel` is idempotent; concurrent `generate` calls queue (single-context inference — models of this size share one context).
- Cold `loadModel` is invoked at app start and must complete before user can paste (progress shown); it is **not** part of the ≤2s brief budget (that is the fast-path's job — research R4).

---

## Generation

```text
generateStream(request) → Stream<InferenceEvent>
```

### Request

| Field | Type | Notes |
|---|---|---|
| `promptId` | string | correlates events; maps to `analysis_id` |
| `systemPrompt` | string | Bantay system prompt (spec §5) **extended**: requires all three languages (EN/TL/CEB) in every text field, forbids fabrication, lists the 5 crisis types / 3 states |
| `userText` | string | raw advisory, ≤20,000 chars (longer inputs pre-truncated with explicit notice — edge case) |
| `grammar` | GBNF grammar id (`bantay-json-v1`) | constrains decoding to the schema in `bantay-analysis.schema.json` — emitted tokens are structurally valid JSON (research R3) |
| `sampling` | `{ temperature: 0.2–0.4, top_p: 0.9, seed: int?, maxTokens: int }` | low temperature for factual fidelity; `maxTokens` sized for trilingual payload (~700) or capped fast mode (~120, R4 fallback) |
| `stage` | `enrich \| repair` | `repair` = the single targeted retry after validation failure |

### Events

| Event | Payload | Meaning |
|---|---|---|
| `tokens(text)` | incremental raw text | UI streams progress ("Bantay is analyzing…"); **not** rendered as brief until validated |
| `completed(raw)` | full raw string | handed to schema validator |
| `failed(code, message)` | `oom \| model_missing \| timeout \| grammar_violation \| cancelled` | triggers repair (once) or degraded path (FR-014) |
| `progress(tokensGenerated, elapsedMs)` | telemetry for quickstart measurements (SC-001/latency risk in research R4) |

### Post-processing contract (caller side)

1. Parse `completed(raw)` → validate against `bantay-analysis.schema.json`.
2. Copy-detect Cebuano vs EN/TL (byte-identical ⇒ warn via `model_notice`, do not fail — research R5).
3. Merge into skeleton **preserving** `analysis_id`, step ids, and user `state` toggles (FR-006 persistence).
4. On validation failure → re-invoke `generateStream(stage: repair)` once; second failure ⇒ `status=failed`, degraded brief retained (FR-014).

---

## Guarantees & non-guarantees

**Guaranteed**
- Works with networking fully disabled; interface opens zero sockets (SC-007 egress assertion).
- Under grammar constraints, `completed(raw)` is always parseable JSON matching the schema's *structure*.
- Semantic content (enums present, trilingual fields non-empty) enforced by caller validation.
- Token stream cancellation is immediate on user navigation.

**Non-guaranteed**
- Truthfulness of paraphrase — mitigated by prompt grounding + corpus fabrication review (FR-005, SC-002), not by this interface.
- Exact latency — measured, not asserted; targets in research R4 (skeleton ≤2s via fast path; enrichment p95 ≤15s).
- Translation quality of `ceb` — copy-detection warns but cannot judge quality (SC-009 covers user perception).

---

## Error codes → user-facing behavior

| Code | Behavior |
|---|---|
| `model_missing` | App runs guides/history only; paste shows "AI model not installed" + retry after reinstall (research R11) |
| `oom` | Unload, retry with fallback model once; else degraded brief |
| `timeout` / `grammar_violation` | One repair attempt → else `status=failed` + "analysis limited" notice |
| `cancelled` | Skeleton remains; user may restart analysis from History |
