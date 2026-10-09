# Model assets (T004 placement contract)

`.gguf` files are **git-ignored** (multi-hundred-MB binaries). Place them here
before building — see `quickstart.md` §1. The app bundles them as Flutter
assets (`pubspec.yaml` → `assets/models/`).

## Required files

| File | Role | Size (approx.) | Source |
|------|------|----------------|--------|
| `qwen2.5-1.5b-instruct-q4_k_m.gguf` | **Primary** model (research R2) | ~1.0 GB | Qwen2.5-1.5B-Instruct, GGUF Q4_K_M (Hugging Face `Qwen/Qwen2.5-1.5B-Instruct-GGUF` or llama.cpp-compatible mirror) |
| `llama-3.2-1b-instruct-q4_k_m.gguf` | **Fallback** for ≤3 GB RAM devices | ~0.7 GB | Llama-3.2-1B-Instruct GGUF Q4_K_M (Meta Llama community license — accept before download) |
| `qwen2.5-0.5b-instruct-q4_k_m.gguf` | **CI smoke model** (research R10) | ~0.4 GB | Qwen2.5-0.5B-Instruct GGUF Q4_K_M |

## Grammar (tracked in git)

- `bantay-json-v1.gbnf` — GBNF grammar for constrained JSON decoding (created by task T018). This file **is** committed.

## Behavior when missing

`preflight()` (research R2/R11) reports `model_variant: missing` → the app
still runs History/Guides/Settings; paste/OCR intake shows
"AI model not installed" (contract: `local-inference.md`, error code
`model_missing`).

## Licensing notes

- Qwen2.5 series: Apache-2.0.
- Llama 3.2: Meta Llama 3.2 Community License — separate acceptance required.
- Models are for on-device inference only; never uploaded, never sent over a
  network (FR-012).
