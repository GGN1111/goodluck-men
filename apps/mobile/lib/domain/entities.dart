/// Domain entities and enums per data-model.md.
///
/// Pure Dart (no Flutter imports) so repositories, validators, and the
/// inference pipeline can share them. All `toMap`/`fromMap` use SQLite
/// column names (snake_case) — schema lives in `lib/data/migrations/`.
library;

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// FR-002: exactly one of five categories per incident.
enum CrisisType {
  flood,
  fire,
  security,
  blackout,
  general;

  String get contractName {
    switch (this) {
      case CrisisType.flood:
        return 'FLOOD';
      case CrisisType.fire:
        return 'FIRE';
      case CrisisType.security:
        return 'SECURITY';
      case CrisisType.blackout:
        return 'BLACKOUT';
      case CrisisType.general:
        return 'GENERAL';
    }
  }

  static CrisisType fromContract(String value) {
    switch (value) {
      case 'FLOOD':
        return CrisisType.flood;
      case 'FIRE':
        return CrisisType.fire;
      case 'SECURITY':
        return CrisisType.security;
      case 'BLACKOUT':
        return CrisisType.blackout;
      case 'GENERAL':
        return CrisisType.general;
      default:
        throw FormatException('Unknown crisis_type: $value');
    }
  }
}

/// FR-003: severity states + theme mapping (see `core/theme/app_theme.dart`).
enum SeverityState {
  alert,
  caution,
  info;

  String get contractName {
    switch (this) {
      case SeverityState.alert:
        return 'ALERT';
      case SeverityState.caution:
        return 'CAUTION';
      case SeverityState.info:
        return 'INFO';
    }
  }

  static SeverityState fromContract(String value) {
    switch (value) {
      case 'ALERT':
        return SeverityState.alert;
      case 'CAUTION':
        return SeverityState.caution;
      case 'INFO':
        return SeverityState.info;
      default:
        throw FormatException('Unknown bantay_state: $value');
    }
  }
}

/// FR-009: three display languages, switchable instantly.
enum AppLanguage {
  en,
  tl,
  ceb;

  static AppLanguage fromName(String value) {
    switch (value) {
      case 'en':
        return AppLanguage.en;
      case 'tl':
        return AppLanguage.tl;
      case 'ceb':
        return AppLanguage.ceb;
      default:
        throw FormatException('Unknown language: $value');
    }
  }
}

/// Incident lifecycle: skeleton → enriched | failed (data-model.md).
enum AnalysisStatus {
  skeleton,
  enriched,
  failed;

  static AnalysisStatus fromName(String value) => AnalysisStatus.values
      .firstWhere((e) => e.name == value,
          orElse: () => AnalysisStatus.skeleton);
}

/// Alarm lifecycle: scheduled → fired | cancelled (data-model.md).
enum AlarmStatus {
  scheduled,
  fired,
  cancelled;

  static AlarmStatus fromName(String value) => AlarmStatus.values
      .firstWhere((e) => e.name == value, orElse: () => AlarmStatus.scheduled);
}

enum ChecklistStepState {
  pending,
  done;

  static ChecklistStepState fromName(String value) =>
      ChecklistStepState.values.firstWhere((e) => e.name == value,
          orElse: () => ChecklistStepState.pending);
}

/// FR-004 warning codes (contract `missing_warnings[].code`).
enum WarningCode {
  evacCenter,
  hotline,
  zone,
  other;

  String get contractName {
    switch (this) {
      case WarningCode.evacCenter:
        return 'EVAC_CENTER';
      case WarningCode.hotline:
        return 'HOTLINE';
      case WarningCode.zone:
        return 'ZONE';
      case WarningCode.other:
        return 'OTHER';
    }
  }

  static WarningCode fromContract(String value) {
    switch (value) {
      case 'EVAC_CENTER':
        return WarningCode.evacCenter;
      case 'HOTLINE':
        return WarningCode.hotline;
      case 'ZONE':
        return WarningCode.zone;
      case 'OTHER':
        return WarningCode.other;
      default:
        throw FormatException('Unknown warning code: $value');
    }
  }
}

enum SourceType {
  text,
  ocr;

  static SourceType fromName(String value) => SourceType.values
      .firstWhere((e) => e.name == value, orElse: () => SourceType.text);
}

enum StepOrigin {
  template,
  llm;

  static StepOrigin fromName(String value) => StepOrigin.values
      .firstWhere((e) => e.name == value, orElse: () => StepOrigin.template);
}

enum WarningOrigin {
  fastpath,
  llm;

  static WarningOrigin fromName(String value) => WarningOrigin.values
      .firstWhere((e) => e.name == value, orElse: () => WarningOrigin.fastpath);
}

// ---------------------------------------------------------------------------
// Shared value types
// ---------------------------------------------------------------------------

/// Trilingual content triplet (FR-009) — summary, speech, steps, warnings.
class LocalizedText {
  const LocalizedText({required this.en, required this.tl, required this.ceb});

  final String en;
  final String tl;
  final String ceb;

  String forLang(AppLanguage language) {
    switch (language) {
      case AppLanguage.en:
        return en;
      case AppLanguage.tl:
        return tl;
      case AppLanguage.ceb:
        return ceb;
    }
  }

  bool get isComplete =>
      en.trim().isNotEmpty && tl.trim().isNotEmpty && ceb.trim().isNotEmpty;

  Map<String, String> toMap() => {'en': en, 'tl': tl, 'ceb': ceb};

  factory LocalizedText.fromMap(Map<String, Object?> map) => LocalizedText(
        en: (map['en'] ?? '') as String,
        tl: (map['tl'] ?? '') as String,
        ceb: (map['ceb'] ?? '') as String,
      );

  LocalizedText copyWith({String? en, String? tl, String? ceb}) =>
      LocalizedText(en: en ?? this.en, tl: tl ?? this.tl, ceb: ceb ?? this.ceb);
}

// ---------------------------------------------------------------------------
// Entities
// ---------------------------------------------------------------------------

/// One analyzed advisory (data-model.md IncidentRecord).
class IncidentRecord {
  const IncidentRecord({
    this.id,
    required this.createdAt,
    required this.sourceType,
    required this.sourceText,
    required this.crisisType,
    required this.severity,
    this.location,
    this.timeOrStatus,
    required this.summary,
    required this.speech,
    required this.status,
    this.modelNotice,
    this.analysisId,
  });

  final int? id;
  final DateTime createdAt;
  final SourceType sourceType;
  final String sourceText; // verbatim (or truncated with notice) — FR-005 provenance
  final CrisisType crisisType;
  final SeverityState severity;
  final String? location;
  final String? timeOrStatus;
  final LocalizedText summary;
  final LocalizedText speech;
  final AnalysisStatus status;
  final String? modelNotice;
  final String? analysisId; // UUID linking to inference request

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'created_at': createdAt.toIso8601String(),
        'source_type': sourceType.name,
        'source_text': sourceText,
        'crisis_type': crisisType.contractName,
        'severity': severity.contractName,
        'location': location,
        'time_or_status': timeOrStatus,
        'summary_en': summary.en,
        'summary_tl': summary.tl,
        'summary_ceb': summary.ceb,
        'speech_en': speech.en,
        'speech_tl': speech.tl,
        'speech_ceb': speech.ceb,
        'status': status.name,
        'model_notice': modelNotice,
        'analysis_id': analysisId,
      };

  factory IncidentRecord.fromMap(Map<String, Object?> map) => IncidentRecord(
        id: map['id'] as int?,
        createdAt: DateTime.parse(map['created_at'] as String),
        sourceType: SourceType.fromName(map['source_type'] as String),
        sourceText: map['source_text'] as String,
        crisisType: CrisisType.fromContract(map['crisis_type'] as String),
        severity: SeverityState.fromContract(map['severity'] as String),
        location: map['location'] as String?,
        timeOrStatus: map['time_or_status'] as String?,
        summary: LocalizedText.fromMap({
          'en': map['summary_en'],
          'tl': map['summary_tl'],
          'ceb': map['summary_ceb'],
        }),
        speech: LocalizedText.fromMap({
          'en': map['speech_en'],
          'tl': map['speech_tl'],
          'ceb': map['speech_ceb'],
        }),
        status: AnalysisStatus.fromName(map['status'] as String),
        modelNotice: map['model_notice'] as String?,
        analysisId: map['analysis_id'] as String?,
      );

  IncidentRecord copyWith({
    int? id,
    CrisisType? crisisType,
    SeverityState? severity,
    String? location,
    String? timeOrStatus,
    LocalizedText? summary,
    LocalizedText? speech,
    AnalysisStatus? status,
    String? modelNotice,
    String? analysisId,
  }) {
    return IncidentRecord(
      id: id ?? this.id,
      createdAt: createdAt,
      sourceType: sourceType,
      sourceText: sourceText,
      crisisType: crisisType ?? this.crisisType,
      severity: severity ?? this.severity,
      location: location ?? this.location,
      timeOrStatus: timeOrStatus ?? this.timeOrStatus,
      summary: summary ?? this.summary,
      speech: speech ?? this.speech,
      status: status ?? this.status,
      modelNotice: modelNotice ?? this.modelNotice,
      analysisId: analysisId ?? this.analysisId,
    );
  }
}

/// Prioritized checklist item (FR-006) — max 5 per incident.
class ActionStep {
  const ActionStep({
    this.id,
    required this.incidentId,
    required this.priority,
    required this.text,
    required this.state,
    required this.origin,
  });

  final int? id;
  final int incidentId;
  final int priority; // >= 1
  final LocalizedText text;
  final ChecklistStepState state;
  final StepOrigin origin;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'incident_id': incidentId,
        'priority': priority,
        'text_en': text.en,
        'text_tl': text.tl,
        'text_ceb': text.ceb,
        'state': state.name,
        'origin': origin.name,
      };

  factory ActionStep.fromMap(Map<String, Object?> map) => ActionStep(
        id: map['id'] as int?,
        incidentId: map['incident_id'] as int,
        priority: map['priority'] as int,
        text: LocalizedText.fromMap({
          'en': map['text_en'],
          'tl': map['text_tl'],
          'ceb': map['text_ceb'],
        }),
        state: ChecklistStepState.fromName(map['state'] as String),
        origin: StepOrigin.fromName(map['origin'] as String),
      );

  ActionStep copyWith({
    int? id,
    int? priority,
    LocalizedText? text,
    ChecklistStepState? state,
    StepOrigin? origin,
  }) =>
      ActionStep(
        id: id ?? this.id,
        incidentId: incidentId,
        priority: priority ?? this.priority,
        text: text ?? this.text,
        state: state ?? this.state,
        origin: origin ?? this.origin,
      );
}

/// Red-flag warning for an omitted critical detail (FR-004).
class MissingWarning {
  const MissingWarning({
    this.id,
    required this.incidentId,
    required this.code,
    required this.text,
    required this.origin,
  });

  final int? id;
  final int incidentId;
  final WarningCode code;
  final LocalizedText text;
  final WarningOrigin origin;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'incident_id': incidentId,
        'code': code.contractName,
        'text_en': text.en,
        'text_tl': text.tl,
        'text_ceb': text.ceb,
        'origin': origin.name,
      };

  factory MissingWarning.fromMap(Map<String, Object?> map) => MissingWarning(
        id: map['id'] as int?,
        incidentId: map['incident_id'] as int,
        code: WarningCode.fromContract(map['code'] as String),
        text: LocalizedText.fromMap({
          'en': map['text_en'],
          'tl': map['text_tl'],
          'ceb': map['text_ceb'],
        }),
        origin: WarningOrigin.fromName(map['origin'] as String),
      );
}

/// Local re-check reminder (FR-008) — DB-backed for boot/launch reconciliation.
class ReCheckAlarm {
  const ReCheckAlarm({
    this.id,
    required this.incidentId,
    required this.fireAt,
    required this.message,
    required this.status,
    this.platformHandle,
  });

  final int? id;
  final int incidentId;
  final DateTime fireAt;
  final String message;
  final AlarmStatus status;
  final String? platformHandle;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'incident_id': incidentId,
        'fire_at': fireAt.toIso8601String(),
        'message': message,
        'status': status.name,
        'platform_handle': platformHandle,
      };

  factory ReCheckAlarm.fromMap(Map<String, Object?> map) => ReCheckAlarm(
        id: map['id'] as int?,
        incidentId: map['incident_id'] as int,
        fireAt: DateTime.parse(map['fire_at'] as String),
        message: map['message'] as String,
        status: AlarmStatus.fromName(map['status'] as String),
        platformHandle: map['platform_handle'] as String?,
      );

  ReCheckAlarm copyWith({
    int? id,
    AlarmStatus? status,
    String? platformHandle,
  }) =>
      ReCheckAlarm(
        id: id ?? this.id,
        incidentId: incidentId,
        fireAt: fireAt,
        message: message,
        status: status ?? this.status,
        platformHandle: platformHandle ?? this.platformHandle,
      );
}

/// Bundled, read-only offline reference guide (never network-fetched).
class EmergencyProtocolGuide {
  const EmergencyProtocolGuide({
    required this.slug,
    required this.crisisType,
    required this.title,
    required this.body,
  });

  final String slug;
  final CrisisType crisisType;
  final LocalizedText title;
  final LocalizedText body;

  Map<String, Object?> toMap() => {
        'slug': slug,
        'crisis_type': crisisType.contractName,
        'title_en': title.en,
        'title_tl': title.tl,
        'title_ceb': title.ceb,
        'body_en': body.en,
        'body_tl': body.tl,
        'body_ceb': body.ceb,
      };

  factory EmergencyProtocolGuide.fromMap(Map<String, Object?> map) =>
      EmergencyProtocolGuide(
        slug: map['slug'] as String,
        crisisType: CrisisType.fromContract(map['crisis_type'] as String),
        title: LocalizedText.fromMap({
          'en': map['title_en'],
          'tl': map['title_tl'],
          'ceb': map['title_ceb'],
        }),
        body: LocalizedText.fromMap({
          'en': map['body_en'],
          'tl': map['body_tl'],
          'ceb': map['body_ceb'],
        }),
      );
}

/// Optional single-row household preparedness profile.
class HouseholdProfile {
  const HouseholdProfile({
    this.id = 1,
    this.meetingPoint,
    this.evacDestination,
    this.notes,
    this.updatedAt,
  });

  final int id;
  final String? meetingPoint;
  final String? evacDestination;
  final String? notes;
  final DateTime? updatedAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'meeting_point': meetingPoint,
        'evac_destination': evacDestination,
        'notes': notes,
        'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
      };

  factory HouseholdProfile.fromMap(Map<String, Object?> map) =>
      HouseholdProfile(
        id: (map['id'] as int?) ?? 1,
        meetingPoint: map['meeting_point'] as String?,
        evacDestination: map['evac_destination'] as String?,
        notes: map['notes'] as String?,
        updatedAt: map['updated_at'] != null
            ? DateTime.parse(map['updated_at'] as String)
            : null,
      );
}

/// Single-row user settings (language default, low-power mode, permissions).
class AppSettings {
  const AppSettings({
    this.language = AppLanguage.tl,
    this.lowPowerMode = false,
    this.notificationsGranted = false,
    this.modelVariant = 'primary',
  });

  final AppLanguage language;
  final bool lowPowerMode;
  final bool notificationsGranted;

  /// 'primary' | 'fallback' | 'missing' (research R2/R11).
  final String modelVariant;

  Map<String, Object?> toMap() => {
        'id': 1,
        'language': language.name,
        'low_power_mode': lowPowerMode ? 1 : 0,
        'notifications_granted': notificationsGranted ? 1 : 0,
        'model_variant': modelVariant,
      };

  factory AppSettings.fromMap(Map<String, Object?> map) => AppSettings(
        language: AppLanguage.fromName(map['language'] as String? ?? 'tl'),
        lowPowerMode: ((map['low_power_mode'] as int?) ?? 0) == 1,
        notificationsGranted: ((map['notifications_granted'] as int?) ?? 0) == 1,
        modelVariant: map['model_variant'] as String? ?? 'primary',
      );

  AppSettings copyWith({
    AppLanguage? language,
    bool? lowPowerMode,
    bool? notificationsGranted,
    String? modelVariant,
  }) =>
      AppSettings(
        language: language ?? this.language,
        lowPowerMode: lowPowerMode ?? this.lowPowerMode,
        notificationsGranted: notificationsGranted ?? this.notificationsGranted,
        modelVariant: modelVariant ?? this.modelVariant,
      );
}
