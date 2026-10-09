# Tech Stack — SignalReady Pocket

| Layer | Choice | Why |
|---|---|---|
| App framework | **Flutter 3.44 / Dart ≥3.4** | Single Android target for v1, widget testability, FFI access for llama.cpp |
| Storage | **sqflite (SQLite)** + `sqflite_common_ffi` on host | Plain single-file DB, no ORM; FK cascade for FR-015; host tests run the same schema via ffi |
| On-device LLM | **llama.cpp via Dart FFI** (`ffi` package) | In-process inference, zero network; GBNF-constrained JSON output; fast-path classifier + template checklists are the no-model fallback (research R1/R11) |
| Model assets | **Qwen2.5-1.5B-Instruct Q4_K_M** primary, **Llama-3.2-1B** fallback (GGUF) | Chosen in research R2 for Tagalog/Cebuano quality at ~1 GB on a ≥6 GB device |
| Notifications | **flutter_local_notifications** + `timezone` zonedSchedule | Exact in-app-scheduled alarms (FR-008); DB rows are source of truth, launch reconciliation re-arms after reboot (research R8) |
| OCR | **google_mlkit_text_recognition** + `image_picker` | Offline screenshot ingestion (FR-007); injectable engine seam for host tests |
| State / DI | Hand-rolled **composition root** (`AppGraph`) | No provider/riverpod — one graph threaded through the router; every repo takes the shared `Database` |
| Theming | `appThemeFor(severity, lowPower)` tokens | Severity accents (crimson/amber/blue) + blackout pure-black variant (FR-011) |
| Testing | `flutter_test`, `sqflite_common_ffi`, `IOOverrides` egress guard, goldens | Contract/corpus tests, real-DB integration on host, zero-egress proof (SC-007), golden pins for the three Bantay states |
