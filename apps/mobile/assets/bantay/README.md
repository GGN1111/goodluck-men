# Bantay mascot assets (T004 placement contract)

One visual per threat state (spec §3 / research R12). Tracked in git.

| File | State | Theme accent |
|------|-------|--------------|
| `bantay_alert.svg` (or `.json` Lottie) | ALERT — spread wings / responder vest, urgent pose | Alert Crimson `#C53030` |
| `bantay_caution.svg` | CAUTION — wary pose | Warning Amber `#D69E2E` |
| `bantay_info.svg` | INFO — calm pose | Info Blue `#3182CE` |

Subject: "Bantay", a Philippine Eagle wearing a responder vest.

Wired into `lib/ui/bantay_mascot.dart` (task T021): widget selects the asset
from the severity token (`app_theme.dart` → `BantayStateToken`). A missing or
placeholder asset must not crash the UI — fall back to a generic icon.
