/// Schema v1 — mirrors data-model.md entities exactly.
///
/// Conventions:
/// - Datetimes stored as ISO-8601 TEXT.
/// - Bools stored as INTEGER 0/1.
/// - `ON DELETE CASCADE` from incidents (FR-015 permanent delete).
/// - Enum CHECK constraints enforce contract values (FR-002/003/004).
const String migrationV1Sql = '''
CREATE TABLE incidents (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at     TEXT    NOT NULL,
  source_type    TEXT    NOT NULL CHECK (source_type IN ('text','ocr')),
  source_text    TEXT    NOT NULL,
  crisis_type    TEXT    NOT NULL CHECK (crisis_type IN
                   ('FLOOD','FIRE','SECURITY','BLACKOUT','GENERAL')),
  severity       TEXT    NOT NULL CHECK (severity IN
                   ('ALERT','CAUTION','INFO')),
  location       TEXT,
  time_or_status TEXT,
  summary_en     TEXT    NOT NULL,
  summary_tl     TEXT    NOT NULL,
  summary_ceb    TEXT    NOT NULL,
  speech_en      TEXT    NOT NULL,
  speech_tl      TEXT    NOT NULL,
  speech_ceb     TEXT    NOT NULL,
  status         TEXT    NOT NULL CHECK (status IN
                   ('skeleton','enriched','failed')),
  model_notice   TEXT,
  analysis_id    TEXT
);

CREATE TABLE action_steps (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  incident_id INTEGER NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
  priority    INTEGER NOT NULL CHECK (priority >= 1),
  text_en     TEXT    NOT NULL,
  text_tl     TEXT    NOT NULL,
  text_ceb    TEXT    NOT NULL,
  state       TEXT    NOT NULL CHECK (state IN ('pending','done')),
  origin      TEXT    NOT NULL CHECK (origin IN ('template','llm'))
);
CREATE INDEX idx_steps_incident ON action_steps(incident_id, priority);

CREATE TABLE missing_warnings (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  incident_id INTEGER NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
  code        TEXT    NOT NULL CHECK (code IN
                ('EVAC_CENTER','HOTLINE','ZONE','OTHER')),
  text_en     TEXT    NOT NULL,
  text_tl     TEXT    NOT NULL,
  text_ceb    TEXT    NOT NULL,
  origin      TEXT    NOT NULL CHECK (origin IN ('fastpath','llm'))
);
CREATE INDEX idx_warnings_incident ON missing_warnings(incident_id);

CREATE TABLE recheck_alarms (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  incident_id     INTEGER NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
  fire_at         TEXT    NOT NULL,
  message         TEXT    NOT NULL,
  status          TEXT    NOT NULL CHECK (status IN
                    ('scheduled','fired','cancelled')),
  platform_handle TEXT
);
CREATE INDEX idx_alarms_status ON recheck_alarms(status, fire_at);

CREATE TABLE guides (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  slug        TEXT    NOT NULL UNIQUE,
  crisis_type TEXT    NOT NULL CHECK (crisis_type IN
                ('FLOOD','FIRE','SECURITY','BLACKOUT','GENERAL')),
  title_en    TEXT    NOT NULL,
  title_tl    TEXT    NOT NULL,
  title_ceb   TEXT    NOT NULL,
  body_en     TEXT    NOT NULL,
  body_tl     TEXT    NOT NULL,
  body_ceb    TEXT    NOT NULL
);

CREATE TABLE household_profile (
  id               INTEGER PRIMARY KEY CHECK (id = 1),
  meeting_point    TEXT,
  evac_destination TEXT,
  notes            TEXT,
  updated_at       TEXT
);

CREATE TABLE settings (
  id                   INTEGER PRIMARY KEY CHECK (id = 1),
  language             TEXT NOT NULL DEFAULT 'tl'
                         CHECK (language IN ('en','tl','ceb')),
  low_power_mode       INTEGER NOT NULL DEFAULT 0,
  notifications_granted INTEGER NOT NULL DEFAULT 0,
  model_variant        TEXT NOT NULL DEFAULT 'primary'
                         CHECK (model_variant IN ('primary','fallback','missing'))
);

INSERT INTO settings (id, language) VALUES (1, 'tl');
''';

/// Idempotent settings-row seed. The default row is inserted only if absent,
/// so it is safe on both the `onCreate` and the self-heal path.
const String settingsSeedSql = '''
INSERT INTO settings (id, language)
  SELECT 1, 'tl' WHERE NOT EXISTS (SELECT 1 FROM settings WHERE id = 1);
''';

/// Idempotent v1 DDL (CREATE TABLE IF NOT EXISTS / CREATE INDEX IF NOT
/// EXISTS) + default settings row. Used by [healSchema] to bring a stale or
/// partially-created dev DB up to the full v1 shape without dropping data.
///
/// This is the safety net for DBs created by builds whose schema predates a
/// table that v1 now includes (e.g. the `guides` table): such files skip
/// `onCreate`, so without healing, first open crashes with
/// "no such table". Every statement here is safe to run repeatedly.
const String migrationV1IdempotentSql = '''
CREATE TABLE IF NOT EXISTS incidents (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at     TEXT    NOT NULL,
  source_type    TEXT    NOT NULL CHECK (source_type IN ('text','ocr')),
  source_text    TEXT    NOT NULL,
  crisis_type    TEXT    NOT NULL CHECK (crisis_type IN
                   ('FLOOD','FIRE','SECURITY','BLACKOUT','GENERAL')),
  severity       TEXT    NOT NULL CHECK (severity IN
                   ('ALERT','CAUTION','INFO')),
  location       TEXT,
  time_or_status TEXT,
  summary_en     TEXT    NOT NULL,
  summary_tl     TEXT    NOT NULL,
  summary_ceb    TEXT    NOT NULL,
  speech_en      TEXT    NOT NULL,
  speech_tl      TEXT    NOT NULL,
  speech_ceb     TEXT    NOT NULL,
  status         TEXT    NOT NULL CHECK (status IN
                   ('skeleton','enriched','failed')),
  model_notice   TEXT,
  analysis_id    TEXT
);

CREATE TABLE IF NOT EXISTS action_steps (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  incident_id INTEGER NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
  priority    INTEGER NOT NULL CHECK (priority >= 1),
  text_en     TEXT    NOT NULL,
  text_tl     TEXT    NOT NULL,
  text_ceb    TEXT    NOT NULL,
  state       TEXT    NOT NULL CHECK (state IN ('pending','done')),
  origin      TEXT    NOT NULL CHECK (origin IN ('template','llm'))
);
CREATE INDEX IF NOT EXISTS idx_steps_incident
  ON action_steps(incident_id, priority);

CREATE TABLE IF NOT EXISTS missing_warnings (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  incident_id INTEGER NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
  code        TEXT    NOT NULL CHECK (code IN
                ('EVAC_CENTER','HOTLINE','ZONE','OTHER')),
  text_en     TEXT    NOT NULL,
  text_tl     TEXT    NOT NULL,
  text_ceb    TEXT    NOT NULL,
  origin      TEXT    NOT NULL CHECK (origin IN ('fastpath','llm'))
);
CREATE INDEX IF NOT EXISTS idx_warnings_incident
  ON missing_warnings(incident_id);

CREATE TABLE IF NOT EXISTS recheck_alarms (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  incident_id     INTEGER NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
  fire_at         TEXT    NOT NULL,
  message         TEXT    NOT NULL,
  status          TEXT    NOT NULL CHECK (status IN
                    ('scheduled','fired','cancelled')),
  platform_handle TEXT
);
CREATE INDEX IF NOT EXISTS idx_alarms_status
  ON recheck_alarms(status, fire_at);

CREATE TABLE IF NOT EXISTS guides (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  slug        TEXT    NOT NULL UNIQUE,
  crisis_type TEXT    NOT NULL CHECK (crisis_type IN
                ('FLOOD','FIRE','SECURITY','BLACKOUT','GENERAL')),
  title_en    TEXT    NOT NULL,
  title_tl    TEXT    NOT NULL,
  title_ceb   TEXT    NOT NULL,
  body_en     TEXT    NOT NULL,
  body_tl     TEXT    NOT NULL,
  body_ceb    TEXT    NOT NULL
);

CREATE TABLE IF NOT EXISTS household_profile (
  id               INTEGER PRIMARY KEY CHECK (id = 1),
  meeting_point    TEXT,
  evac_destination TEXT,
  notes            TEXT,
  updated_at       TEXT
);

CREATE TABLE IF NOT EXISTS settings (
  id                   INTEGER PRIMARY KEY CHECK (id = 1),
  language             TEXT NOT NULL DEFAULT 'tl'
                         CHECK (language IN ('en','tl','ceb')),
  low_power_mode       INTEGER NOT NULL DEFAULT 0,
  notifications_granted INTEGER NOT NULL DEFAULT 0,
  model_variant        TEXT NOT NULL DEFAULT 'primary'
                         CHECK (model_variant IN ('primary','fallback','missing'))
);
''';
