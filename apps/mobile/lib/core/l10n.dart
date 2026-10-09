import '../domain/entities.dart';

/// T043 — Language lookup layer (FR-009): the single place that maps an
/// [AppLanguage] onto the `en`/`tl`/`ceb` field of a content triplet.
///
/// Switching language is a pure field selection over data already on the
/// screen — it never touches the pipeline, the DB, or checklist state
/// (research R5 / US6). Every brief widget resolves text through here.
String lookup(LocalizedText text, AppLanguage language) =>
    text.forLang(language);

/// Short UI labels for the switcher (EN / TG / BS — the vernacular names
/// Filipino users recognise for English/Tagalog/Cebuano).
String languageLabel(AppLanguage language) => switch (language) {
      AppLanguage.en => 'EN',
      AppLanguage.tl => 'TG',
      AppLanguage.ceb => 'BS',
    };

/// Full name — used in Settings and accessibility labels.
String languageName(AppLanguage language) => switch (language) {
      AppLanguage.en => 'English',
      AppLanguage.tl => 'Tagalog',
      AppLanguage.ceb => 'Cebuano',
    };

/// Cycles EN → TG → BS → EN, for the one-tap header toggle.
AppLanguage nextLanguage(AppLanguage current) => switch (current) {
      AppLanguage.en => AppLanguage.tl,
      AppLanguage.tl => AppLanguage.ceb,
      AppLanguage.ceb => AppLanguage.en,
    };
