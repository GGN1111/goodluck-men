# Feature Specification: SignalReady Pocket — Offline Emergency Co-Pilot

**Feature Branch**: `001-offline-emergency-copilot`

**Created**: 2026-10-09

**Status**: Draft

**Input**: User description: "SignalReady Pocket: a 100% offline, grid-proof emergency co-pilot for hyper-local Filipino crises (flash floods, fires, security lockdowns, blackouts). It parses raw SMS, barangay group-chat forwards, and screenshots of notices into plain Tagalog/Bisaya/English action plans, flags missing survival details (e.g., evacuation order with no evacuation center), generates situation-specific offline checklists, schedules local re-check alarms, and is anchored by 'Bantay', a reactive mascot whose state reflects threat level. Designed for the AppBuildersPH Hackathon."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Instant Offline Alert Decoding (Priority: P1)

A resident receives a confusing, jargon-heavy barangay flood advisory as an SMS forward during a blackout with no cell signal. They paste the raw text into the app and immediately receive a plain-language brief in their chosen language: what is happening, where, when, and how severe it is — with the app's guardian mascot ("Bantay") visibly shifting into the matching threat state.

**Why this priority**: This is the core value proposition. Without it the product is a generic note app. It must work with zero connectivity because that is precisely when other tools fail.

**Independent Test**: Fully testable by enabling airplane mode, pasting a sample flood advisory, and confirming a structured, plain-language brief appears within the target time with correct severity indication.

**Acceptance Scenarios**:

1. **Given** the device has no cellular or internet connection, **When** the user pastes a raw flood advisory, **Then** a structured brief (plain-language summary, crisis category, location, time/status, severity state) is displayed within 2 seconds.
2. **Given** an advisory written in dense utility/LGU jargon (e.g., "Feeder 4 trip, Marikina 16.5m"), **When** it is analyzed, **Then** the summary is expressed in plain language a non-technical resident can act on, without unexplained codes.
3. **Given** any pasted advisory, **When** it is analyzed, **Then** no data is transmitted off the device (verifiable with a device network monitor showing zero traffic).
4. **Given** an active life-threatening advisory (flash flood, active fire), **When** analysis completes, **Then** Bantay and the interface display the ALERT (red) state; for utility updates the INFO state; for rumors or missing critical details the CAUTION (amber) state.

---

### User Story 2 - Situation-Specific Action Checklist (Priority: P1)

From the same pasted advisory, the user gets a short, prioritized checklist of immediate steps tailored to the crisis type (for a flood: kill the main breaker, grab the 72-hour go-bag, move to high ground) and can tick items off as they complete them.

**Why this priority**: Turning analysis into action is the difference between an alert and a co-pilot. It is the second half of the core value loop and is needed for the live demo.

**Independent Test**: Testable by pasting advisories of different crisis types and confirming the steps change to match, then checking items off and confirming progress persists.

**Acceptance Scenarios**:

1. **Given** a pasted flood advisory, **When** the brief is displayed, **Then** a prioritized checklist of situation-appropriate steps (target: three steps) is shown, each with a toggleable done/not-done state.
2. **Given** the same advisory analyzed as a blackout instead of a flood, **When** the crisis category changes, **Then** the checklist steps change to match that crisis type rather than showing generic advice.
3. **Given** the user ticks checklist items, **When** they leave and reopen the app, **Then** the ticked state is preserved.

---

### User Story 3 - Missing Information Red Flags (Priority: P2)

The advisory the user pasted is an evacuation order that never says *where* to evacuate. Instead of letting the user guess, the app displays an explicit warning list of the critical details the announcement failed to include (evacuation center address, barangay hotline, specific zone).

**Why this priority**: This is the safety shield and primary differentiator over a generic summarizer — it prevents false confidence in incomplete information.

**Independent Test**: Testable by pasting deliberately incomplete advisories and confirming the corresponding omissions are surfaced as prominent warnings.

**Acceptance Scenarios**:

1. **Given** an evacuation advisory with no evacuation center stated, **When** analysis completes, **Then** a visible warning explicitly states that no evacuation center address was provided.
2. **Given** an advisory with no official contact number, **When** analysis completes, **Then** a warning states that no barangay/emergency hotline was included.
3. **Given** an advisory containing all critical details, **When** analysis completes, **Then** no spurious warnings are shown (no invented omissions).
4. **Given** any advisory, **When** the brief is produced, **Then** no detail appears in the brief that was not present in (or directly derivable from) the source text — the system never fills gaps with guesses.

---

### User Story 4 - Screenshot Ingestion (Priority: P2)

The user does not have the text — they have a screenshot of an official Facebook notice or a photo of a printed bulletin. They load the image into the app and receive the same brief, checklist, and red flags as if they had pasted the text.

**Why this priority**: A large share of real Filipino emergency communication arrives as images in group chats; without this the app misses those cases. Still secondary to the paste flow because manual retyping remains a workaround.

**Independent Test**: Testable by loading sample notice screenshots and confirming output parity with the equivalent pasted text.

**Acceptance Scenarios**:

1. **Given** a clear screenshot of a text-based emergency notice, **When** the user loads it, **Then** the extracted text produces a brief equivalent to pasting that text directly.
2. **Given** an unreadable, blurry, or text-free image, **When** extraction fails, **Then** the user receives a clear message and an offer to paste/retype the text instead — never a fabricated brief.

---

### User Story 5 - Local Re-Check Alarms (Priority: P2)

After reading the advisory, the user schedules a re-check reminder ("Re-check river level in 1 hour"). At the scheduled time the device shows the reminder even though the phone still has no signal.

**Why this priority**: Emergencies evolve; keeping the user updated without connectivity is a meaningful safety feature, but it depends on Stories 1–2 producing a brief worth re-checking.

**Independent Test**: Testable by scheduling a reminder a minute out while in airplane mode and confirming it fires on time.

**Acceptance Scenarios**:

1. **Given** a displayed brief, **When** the user schedules a re-check for a chosen interval, **Then** a local reminder is queued for that time.
2. **Given** the device is in airplane mode at the scheduled time, **When** the time arrives, **Then** the reminder notification still appears.
3. **Given** a scheduled reminder, **When** the scheduled time passes, **Then** the reminder fires within one minute of the scheduled time.

---

### User Story 6 - Instant Three-Language Switching (Priority: P3)

A Bisaya-speaking parent and their Tagalog-speaking teen look at the same screen. They switch the display language between Cebuano, Tagalog, and English instantly, without waiting for the advisory to be re-analyzed.

**Why this priority**: Accessibility across Philippine languages broadens impact and is a demo highlight, but the app delivers core value in its default language first.

**Independent Test**: Testable by analyzing one advisory, then toggling languages and confirming all displayed content changes immediately with no re-processing delay.

**Acceptance Scenarios**:

1. **Given** an analyzed advisory, **When** the user switches from English to Tagalog, **Then** the summary, Bantay's speech, checklist steps, and warnings all appear in Tagalog within 1 second.
2. **Given** a language switch, **When** it is performed, **Then** the analysis is not re-run and the severity state, checklist progress, and warnings remain unchanged.
3. **Given** the Cebuano option, **When** selected, **Then** user-facing content renders in Cebuano.

---

### User Story 7 - Incident History & Blackout-Friendly Display (Priority: P3)

The user reviews previously parsed advisories and their completed checklists later, and the interface stays legible and battery-frugal during a prolonged blackout.

**Why this priority**: Valuable for record-keeping and long incidents, but the app is already useful without history on first launch.

**Independent Test**: Testable by parsing multiple advisories, reopening history, and confirming records and checklist states; toggling the low-power display mode and confirming high-contrast dark rendering.

**Acceptance Scenarios**:

1. **Given** previously parsed advisories, **When** the user opens history, **Then** each record shows its brief, severity, warnings, and checklist state, fully offline.
2. **Given** the low-power/high-contrast mode is enabled, **When** any screen is displayed, **Then** a dark, high-contrast theme is used for legibility and battery savings.
3. **Given** history exists, **When** the user deletes a record, **Then** it is removed and cannot be recovered from the app.

---

### Edge Cases

- **Empty or non-emergency input**: Pasting a grocery list or blank text yields a clear "no emergency content detected" response — never an invented crisis.
- **Input in a language outside the three supported languages**: The app still produces a brief or explains it cannot analyze the text; it never fabricates content.
- **Conflicting or rumor-like content** (e.g., word-of-mouth hearsay, unverified forwards): Classified at most as CAUTION, with an explicit "unverified" indication.
- **Very long group-chat forwards**: Long inputs are handled without crashing; if only part can be analyzed, the user is told what was and was not analyzed.
- **Analysis failure or malformed output**: The user sees a friendly retry option with the raw text preserved; a partial/failed analysis is never presented as complete.
- **Screenshot with mixed text and images/memes**: Only meaningful notice text is used; surrounding noise does not become part of the brief.
- **Device reboot**: Previously scheduled reminders either re-arm or the user is informed they need rescheduling — no silent loss without notice.
- **Notification permission denied**: The app explains that reminders will not appear and offers in-app re-check prompts instead.
- **Multiple advisories in quick succession**: Each analysis is kept as a separate record; the newest brief is shown first.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST accept raw pasted text (SMS, group-chat forward, or typed notice) and produce a structured emergency brief containing: plain-language summary, crisis category, location, time/status, severity state, guardian speech, action checklist, and missing-information warnings.
- **FR-002**: The system MUST classify every brief into exactly one crisis category: FLOOD, FIRE, SECURITY, BLACKOUT, or GENERAL.
- **FR-003**: The system MUST assign exactly one severity state per brief — ALERT (active life-threatening emergency), CAUTION (moderate threat, missing crucial details, or unverified rumor), or INFO (non-life-threatening utility update) — and visually reflect it through distinct interface theming (crimson for ALERT, amber for CAUTION, dark/blue for INFO) and the corresponding Bantay mascot state.
- **FR-004**: The system MUST detect and explicitly display warnings when critical details are absent from the source text, including at minimum: evacuation center location, official contact/hotline, and affected zone/area — whenever those apply to the crisis type.
- **FR-005**: The system MUST NOT invent, infer-as-fact, or embellish any detail absent from the source text; uncertainty must be surfaced, not filled.
- **FR-006**: The system MUST generate a prioritized, situation-specific action checklist (target of three immediate steps) that varies by crisis type, with per-step done/not-done toggles.
- **FR-007**: The system MUST accept an image (screenshot/photo of a notice) as input and produce the same structured brief as equivalent pasted text; on failed text extraction it MUST offer a clear fallback instead of producing a brief.
- **FR-008**: The system MUST allow the user to schedule local re-check reminders from a displayed brief, and those reminders MUST fire at the scheduled time (within one minute) with no network connectivity.
- **FR-009**: The system MUST present all user-facing brief content (summary, guardian speech, checklist steps, warnings) in Tagalog, English, and Cebuano, switchable instantly (within 1 second) without re-running the analysis or altering state.
- **FR-010**: The system MUST persist each analyzed incident (source text, brief, severity, warnings, checklist progress) locally so history and progress survive app restarts and remain available offline.
- **FR-011**: The system MUST offer a high-contrast dark display mode suitable for blackouts and battery conservation, applicable across all screens.
- **FR-012**: The system MUST require no user account, registration, or login, and MUST transmit no user content off the device at any point.
- **FR-013**: The system MUST complete analysis and display the brief within 2 seconds for a typical advisory (up to 1,000 characters) on a supported device with no connectivity.
- **FR-014**: The system MUST clearly signal when input cannot be analyzed (empty, unreadable image, unsupported content) and MUST preserve the user's original input for retry.
- **FR-015**: The system MUST let users delete individual incident records permanently.

### Key Entities *(include if feature involves data)*

- **Incident Record**: One analyzed advisory — raw source text/image reference, generated brief (summary, category, location, time/status, severity, guardian speech), created timestamp, and the user's selected display language at save time.
- **Action Step**: An individual checklist item belonging to an Incident Record — text in each supported language, priority order, done/not-done state.
- **Missing-Information Warning**: A safety flag belonging to an Incident Record — the omitted detail it refers to and its text in each supported language.
- **Re-Check Alarm**: A scheduled reminder tied to an Incident Record — target time, reminder message, fired/not-fired state.
- **Emergency Protocol Guide**: Cached reference content (e.g., go-bag lists, flood/fire/security/blackout protocols) available offline and browsable without any analysis.
- **Household Profile** *(optional, user-editable)*: Locally stored preparedness details (meeting point, evacuation destination, household notes) used to personalize checklists.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With the device in airplane mode, 100% of paste-to-brief attempts for advisories up to 1,000 characters display a structured brief within 2 seconds.
- **SC-002**: Across a 20-advisory test set containing deliberately omitted details, 100% of omissions are surfaced as warnings, and 0 details absent from the source text appear in any brief.
- **SC-003**: A first-time user, with no instructions, completes the paste → brief → first checked-off action step flow in under 30 seconds.
- **SC-004**: Independent reviewers agree with the system's severity state (ALERT/CAUTION/INFO) on at least 18 of 20 sample advisories, and with the crisis category on at least 18 of 20.
- **SC-005**: Language switches complete in under 1 second with no visible re-analysis, and 100% of displayed brief content changes to the selected language.
- **SC-006**: Reminders scheduled while in airplane mode fire within one minute of their scheduled time in 100% of test runs.
- **SC-007**: The full workflow (paste, analyze, checklist, reminder, language switch, history review) completes with zero bytes transmitted off the device, verified by network monitoring.
- **SC-008**: History, checklist progress, and cached guides remain fully accessible after an app restart and with no connectivity in 100% of test runs.
- **SC-009**: In a moderated session, at least 8 of 10 target users (Filipino households/students) rate the plain-language summaries as "easy to understand" and say they would trust the red-flag warnings.

## Assumptions

- **Platform**: A mobile application for Android and iOS phones; no web, desktop, or SMS-gateway component in this version.
- **Single user, single device**: No accounts, syncing, or multi-device collaboration; all data lives only on the device until the user deletes it.
- **Analysis capability**: Target devices are assumed to have sufficient on-board processing to analyze a typical advisory within the 2-second target (FR-013) with no connectivity; this is validated during technical planning.
- **Language handling**: To satisfy instant switching (FR-009), summary, guardian speech, checklist steps, and warnings are produced in all three supported languages in a single analysis pass. "Bisaya" and "Cebuano" are treated as the same language.
- **Fixed taxonomies**: Five crisis categories and three severity states are exhaustive for this version; new categories (e.g., medical, volcanic activity) map to GENERAL until extended.
- **Input trust model**: The app treats pasted/photographed content as unverified user input; it does not verify authenticity of advisories, so rumor-prone content is capped at CAUTION severity.
- **No live data feeds**: The app does not pull river levels, outage maps, or official feeds; it only interprets content the user provides, plus cached reference guides.
- **Data retention**: Incident records are kept until the user deletes them; no automatic archival or cloud backup exists.
- **Permissions**: Users are assumed to grant notification permission for reminders; the app degrades gracefully if denied (FR-008, edge cases).
- **Scope boundary**: Sending/forwarding advisories to others, integration with official LGU broadcast systems, and any monetization/municipality packaging are out of scope for this specification.
- **Demo context**: The hackathon 5-minute demo script is a presentation asset, not a product requirement; the product must work independently of the demo flow.
