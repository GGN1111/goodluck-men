# Emergency protocol guides (T004 placement contract)

Bundled, read-only reference content seeded into SQLite on first run
(`lib/data/guide_seed.dart`, task T010). Never fetched from a network
(FR-012). Tracked in git.

## Format

One JSON file per guide slug, e.g. `flood-go-bag.json`:

```json
{
  "slug": "flood-go-bag",
  "crisis_type": "FLOOD",
  "title": { "en": "...", "tl": "...", "ceb": "..." },
  "body": { "en": "...", "tl": "...", "ceb": "..." }
}
```

## Required coverage (minimum set)

| slug | crisis_type |
|------|-------------|
| `flood-basics` | FLOOD |
| `flood-go-bag` | FLOOD |
| `fire-response` | FIRE |
| `security-lockdown` | SECURITY |
| `blackout-basics` | BLACKOUT |
| `general-first-aid` | GENERAL |

All three language fields (`en`, `tl`, `ceb`) are mandatory per FR-009.
