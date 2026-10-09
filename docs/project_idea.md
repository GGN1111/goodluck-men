# SIGNALREADY POCKET: Comprehensive Project & Technical Specification

**Document Type:** Master Review Document / Hackathon Blueprint
**Target Event:** AppBuildersPH Hackathon (SM Makati)
**Status:** Ready for Development Sprint

---

## 1. Executive Summary & Core Philosophy

**SignalReady Pocket** is an air-gapped, grid-proof emergency co-pilot designed for hyper-local Filipino crises (sudden barangay flash floods, neighborhood fires, campus security lockdowns, and unscheduled blackouts). When local cell towers are jammed, lose power, or cloud AI services fail, SignalReady Pocket remains 100% operational.

It translates confusing, incomplete SMS broadcasts and forwarded Facebook group chat (GC) notices into plain Tagalog, Bisaya, or English action plans, flags missing survival details, and generates offline emergency checklists—all running **100% on-device**.

### The "Tarsi" Design Formula (Disaster Response Edition)

| Engineering Constraint      | Rebranded Consumer Feature                          |
| --------------------------- | --------------------------------------------------- |
| **No Cloud Server / DB**    | 100% Grid-Proof (Works when cell towers die/jam)    |
| **No User Auth / Accounts** | Zero-Friction Access (Open and parse in <2 seconds) |
| **No Subscription Backend** | Free Forever Emergency Utility                      |
| **Local Storage Only**      | Zero Tracking & Absolute Privacy                    |

---

## 2. Core Feature Set

1. **Hyper-Local Text & Screenshot Parsing:** Instantly ingest raw SMS advisories, barangay GC announcements, or screenshots of official Facebook notices.
2. **Bantay Reactive Guardian (Mascot Engine):** "Bantay" (a Philippine Eagle wearing a responder vest) acts as the emotional and visual anchor. The UI adapts its theme based on Bantay's threat assessment.
3. **Missing Info & Red Flag Detector:** The safety shield. If an alert omits critical details (e.g., an evacuation order with no evacuation center listed), the app explicitly highlights the omission so users don't guess.
4. **Offline Action Checklists:** Generates immediate, situation-specific action steps based on the crisis type (e.g., "Switch off main breaker," "Prepare 72-hour go-bag").
5. **Smart Local Battery & Crisis Alarms:** Sets local OS notifications for timed crisis updates (e.g., "Re-check river water levels in 1 hour") and toggles a dark/high-contrast mode during blackouts to save battery.
6. **Instant Multi-Language Switch:** Toggles between English, Tagalog, and Cebuano instantly without re-processing the input.

---

## 3. The Role of the Local LLM

The local LLM serves as the **reasoning, translation, and structuring engine**. It performs five critical offline tasks:

1. **De-Jargoning & Plain-Language Summarization:** Strips away dense LGU codes and translates them into a single, plain-language executive summary. (e.g., _“Feeder 4 trip, Marikina 16.5m”_ _"Marikina River is flooding. Leave low-lying areas."_)
2. **Missing Info Detection (The Safety Shield):** Scans for missing context and populates a warning list (e.g., _"⚠️ WARNING: No official Barangay response hotline was provided in this message."_)
3. **Threat Classification & Mascot State Machine:** Evaluates severity to control Bantay's expression and UI theme:

- **ALERT (Red):** Active fires, flash floods, armed threats.
- **CAUTION (Amber):** Unverified rumors, missing locations.
- **INFO (Blue/Dark):** Utility updates, blackouts.

4. **Dynamic Action Checklist Generation:** Generates a prioritized 3-step action checklist tailored specifically to the incident type, replacing generic advice with contextual steps.
5. **JSON Schema Generation:** Turns chaotic, unformatted chat forwards into a strict JSON structure for the mobile frontend to render UI cards and schedule OS alarms.

---

## 4. Technical Architecture & Tech Stack

**Recommended Tech Stack:**

- **Frontend UI:** Flutter (Dart) or React Native (Single codebase, rapid UI card assembly).
- **Fast Text Ingestion:** Native Apple VisionKit (iOS) / Google MLKit Text Recognition (Android) for screenshots.
- **Local AI Engine:** Ollama or llama.cpp serving a 4-bit quantized `Llama-3.2-1B-Instruct` or `Qwen-2.5-1.5B-Instruct` locally at `localhost:11434`.
- **Local Storage:** SQLite or Hive (Encrypted cache for pre-saved household profiles and history).
- **Local Alarms:** `flutter_local_notifications` or Android AlarmManager.

**System Data Flow:**

```text
[ 📝 Pasted SMS / GC Text ] or [ 📷 Screenshot OCR Pass ]
        │
        ▼
[ Fast Text Ingestion ]  ──► Extracts unformatted raw string (<50ms)
        │
        ▼
[ Local LLM Server ]     ──► Ollama/llama.cpp processing at localhost:11434
        │                    (Model: Llama-3.2-1B-Instruct)
        ▼
[ Structured JSON ]      ──► Parsed schema with severity, actions & red flags
        │
        ├───────────────────────────────┐
        ▼                               ▼
[ Bantay Reactive UI ]        [ Local Database (SQLite) ]
• Threat State (Red/Yellow)   • Save Crisis Incident Record
• Action Checklist            • Cache Emergency Protocol Guides
• Missing Info Red Flags      • Schedule Local OS Re-Check Alarms
                                        │
                                        ▼
                              [ Local Push Alarms ]
                              • "Bantay Alert: Re-check Marikina River level"

```

---

## 5. Local AI System Prompt & Expected JSON

**System Prompt (Send to local `api/generate`):**

```text
You are Bantay, an offline disaster and crisis assistant running 100% on-device.
Analyze the raw emergency SMS, barangay announcement, or school notice and output a strictly valid JSON object.

RULES:
1. Do NOT invent missing details or facts.
2. If critical information (evacuation location, official contact number, specific zone) is omitted from the raw text, explicitly list it in "missing_warnings".
3. Categorize crisis_type as: "FLOOD", "FIRE", "SECURITY", "BLACKOUT", or "GENERAL".
4. Set "bantay_state" to:
   - "ALERT": Active life-threatening emergency (evacuation, active fire, flash flood).
   - "CAUTION": Moderate threat, missing crucial location details, or unverified rumor.
   - "INFO": Non-life-threatening utility update (scheduled blackout, advisory).
5. Return ONLY raw valid JSON. No markdown wrappers or extra text.

REQUIRED JSON SCHEMA:
{
  "crisis_type": "FLOOD | FIRE | SECURITY | BLACKOUT | GENERAL",
  "summary_tagalog": "string",
  "summary_english": "string",
  "location": "string",
  "time_or_status": "string",
  "bantay_state": "ALERT | CAUTION | INFO",
  "bantay_speech_tagalog": "string",
  "bantay_speech_english": "string",
  "action_checklist": [
    {
      "step_tagalog": "string",
      "step_english": "string"
    }
  ],
  "missing_warnings": ["string"]
}

```

**Example JSON Output (For a Flood Notice):**

```json
{
  "crisis_type": "FLOOD",
  "summary_tagalog": "Umapaw ang Marikina River sa Alarm 2 (16.5m). Kailangan nang lumikas ng mga nasa mabababang lugar.",
  "summary_english": "Marikina River reached Alarm 2 (16.5m). Residents in low-lying areas must evacuate.",
  "location": "Zone 4, Barangay Tumana",
  "time_or_status": "As of 4:30 PM",
  "bantay_state": "ALERT",
  "bantay_speech_tagalog": "Mag-ingat! Mabilis na tumataas ang tubig. Lumikas agad ngunit mag-ingat dahil walang nakalagay na tiyak na evacuation center sa advisory na ito!",
  "bantay_speech_english": "Alert! Water levels are rising fast. Evacuate now, but take note: this announcement did NOT specify which evacuation center is open!",
  "action_checklist": [
    {
      "step_tagalog": "Patayin ang pangunahing switch ng kuryente (main breaker).",
      "step_english": "Turn off the main electrical breaker."
    },
    {
      "step_tagalog": "Kunin ang 72-hour emergency go-bag at mahahalagang dokumento.",
      "step_english": "Grab your 72-hour emergency go-bag and vital documents."
    }
  ],
  "missing_warnings": [
    "BABALA: Walang nakalagay na eksaktong Evacuation Center address sa advisory.",
    "BABALA: Walang ibinigay na opisyal na contact number ng Barangay Emergency Response Team."
  ]
}
```

---

## 6. UI/UX Design System & Layout Architecture

**Color Palette & Design Tokens:**

- **Primary Slate (`#1A202C`):** High-contrast base optimized for low-power dark mode (saves battery during blackouts).
- **Alert Crimson (`#C53030`):** High-visibility red reserved for active life safety threats.
- **Warning Amber (`#D69E2E`):** Distinct highlight for missing advisory info and unverified rumors.

**Screen Structure:**

```text
+------------------------------------------------------------------+
| 🛡️ 100% GRID-PROOF CRISIS ENGINE             [ AIRPLANE MODE ✈️ ]|
+------------------------------------------------------------------+
|                                                                  |
|  +------------------------------------------------------------+  |
|  |                   [ BANTAY MASCOT CARD ]                   |  |
|  |                                                            |  |
|  |            🚨 ALERT BANTAY (Spread Wings / Vest)           |  |
|  |                                                            |  |
|  |  "Marikina River Alarm 2 parsed! Evacuate Zone 4 immediately.|  |
|  |   Notice: The advisory forgot to state the evac center!"   |  |
|  +------------------------------------------------------------+  |
|                                                                  |
|  [ 📋 IMMEDIATE ACTION CHECKLIST ]                               |  |
|  +------------------------------------------------------------+  |
|  | [x] 1. Turn off main electrical breaker            [DONE]  |  |
|  | [ ] 2. Grab 72-hour emergency go-bag                [CHECK] |  |
|  | [ ] 3. Move family to high ground / Barangay Hall    [CHECK] |  |
|  +------------------------------------------------------------+  |
|                                                                  |
|  [ ⚠️ MISSING INFORMATION RED FLAGS ]                            |  |
|  +------------------------------------------------------------+  |
|  | • Missing: No specific Evacuation Center address provided.   |  |
|  | • Missing: No direct Barangay hotline included in text.     |  |
|  +------------------------------------------------------------+  |
|                                                                  |
|  [ ⏰ SET RE-CHECK ALARM: 1 HOUR ]                               |  |
|                                                                  |
|  [ 📝 PASTE NEW ANNOUNCEMENT ]         [ TAGALOG | EN | CEBUANO ]|
+------------------------------------------------------------------+

```

---

## 7. The Winning 5-Minute Live Demo Script (SM Makati)

**[0:00 - 0:30] THE HOOK & PROBLEM**
"When a flash flood hits a barangay or a transformer blows, local cell towers get instantly jammed or lose power entirely. Cloud AI apps like ChatGPT crumble when you need them most, leaving families with confusing, incomplete SMS forwards."

**[0:30 - 1:00] THE AIRPLANE MODE STUNT**
_(Enable Airplane Mode live on stage. Display local network monitor showing 0 KB/s traffic.)_
"This is SignalReady Pocket. Powered by local AI, it runs 100% on-device with zero internet, zero cloud servers, and zero setup."

**[1:00 - 2:30] LIVE PARSING & BANTAY REACTION**
_(Paste a messy, confusing barangay flood announcement into the app.)_
"In under 1 second, our local AI processes the text natively. Bantay shifts to Alert State, summarizes the threat into plain Tagalog, generates a contextual evacuation checklist, and flags a critical red flag: the barangay announcement forgot to state which evacuation center is open."

**[2:30 - 3:30] THE ACTION CHECKLIST & ALARM DEMO**
_(Tap through the checklist items live.)_
"Users check off safety steps offline, and Bantay sets a local OS alarm to re-verify river levels in 1 hour—working completely while cell service is dead."

**[3:30 - 4:30] THE TARSI BUSINESS MODEL**
"Because we carry zero server upkeep costs, SignalReady Pocket uses the Tarsi formula: 100% free for citizens, with customized offline deployment packages for municipalities and university campuses."

**[4:30 - 5:00] THE WRAP**
"Grid-proof, mascot-led, built for every local crisis. Thank you!"
