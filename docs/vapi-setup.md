# Vapi Assistant Setup (Phase 3)

Copy-paste reference for configuring the Vapi assistant that fronts our MVA intake. All of this lives in the Vapi dashboard; nothing here is checked out from the repo at runtime.

## Prerequisites

1. **Vapi account** — sign up at [vapi.ai](https://vapi.ai) (free to start).
2. **US phone number** — Vapi dashboard → **Phone Numbers → Buy Number** (~$2/mo + usage).
3. **ngrok tunnel running** — `bash scripts/ngrok-start.sh` (prints the https URL).
4. **Attorney test phone verified in Twilio** — trial accounts only send SMS to verified Caller IDs.

## Assistant configuration

In **Vapi Dashboard → Assistants → Create Assistant**:

| Field | Value |
|---|---|
| **Name** | `MVA-Intake v0.1` |
| **First Message** | *"Thanks for calling. This call may be recorded for quality purposes. Is anyone injured right now or needing emergency help?"* |
| **Model** | OpenAI → **gpt-4o** (fast + strong structured output) |
| **Voice** | Deepgram → **aura-asteria-en** |
| **Transcriber** | Deepgram → **nova-2** |
| **Max Call Duration** | `600` seconds |
| **Silence Timeout** | `30` seconds |
| **End Call Phrases** | `"goodbye"`, `"thanks, bye"`, `"have a good night"` |

Server URL (under **Server URL** or **Advanced → Messaging**): **`https://<your-ngrok>.ngrok-free.app/webhook/mva-intake`**. Update every ngrok restart.

## System prompt (paste verbatim into Vapi's `System Prompt` field)

```
You are the after-hours receptionist for a personal-injury law firm handling
motor vehicle accident (MVA) cases. A caller has just reached the firm outside
business hours. Your job:

1. Warm, concise, professional. Never robotic, never rushed.
2. Read the recording-disclosure first message (already set).
3. If the caller says anyone is seriously injured or needs emergency help,
   tell them to hang up and dial 911 before continuing. Then gently continue.
4. Gather the intake information listed below.
5. Never give legal advice ("you should sue...", "you have a strong case").
   Never give medical advice. Never promise representation.
6. Close with: "Thanks for calling. Someone from the firm will follow up with
   you soon." Never hang up abruptly, even for unqualified callers.
7. At the end of the call, invoke the submit_intake function exactly once
   with the collected data.

Fields to collect (in roughly this order):
- Caller's full name
- Callback phone number
- Date of the incident (YYYY-MM-DD if possible)
- City and state where it happened
- Were they at fault? (yes / no / unsure)
- Was anyone injured? Short description of the injury.
- Did they or the injured person get medical treatment? (yes / no / scheduled)
- Does the other driver have insurance? (yes / no / unknown)
- If other driver is uninsured, does the caller's policy have uninsured-motorist
  (UM) coverage? (yes / no / unknown)
- Caller's age (needed to detect minors)
- Did anyone die in the incident?

Populate the `flags` array with any of these strings that apply:
- "at_fault_unsure"       — caller isn't sure who was at fault
- "minor_involved"        — anyone under 18 was injured
- "wrongful_death"        — someone died in the incident
- "out_of_state"          — the incident was outside Texas
- "multi_party"           — more than one other vehicle, or a commercial vehicle
- "hit_and_run"           — the other driver left the scene

Rules for deterministic fields:
- Booleans must be actual booleans (true / false), not strings.
- `incident_date` must be ISO date (YYYY-MM-DD).
- `caller_has_um_coverage` can be null if irrelevant or unknown.
- Do not invent information. If the caller declines to answer, leave the
  field empty / false and add a note in `notes`.
```

## Tool definition — `submit_intake`

In **Vapi Dashboard → Assistants → MVA-Intake → Functions → Add Function**:

- **Function Name:** `submit_intake`
- **Description:** `Submit the collected intake information at the end of the call. Call this exactly once when all fields have been gathered.`
- **Async:** off (we want the call to wait for our server's 200 before hanging up cleanly).

Parameters schema (paste as JSON):

```json
{
  "type": "object",
  "properties": {
    "intake": {
      "type": "object",
      "properties": {
        "name": {"type": "string"},
        "phone": {"type": "string"},
        "incident_date": {"type": "string"},
        "location": {"type": "string"},
        "injury_description": {"type": "string"},
        "age": {"type": "number"},
        "death_involved": {"type": "boolean"}
      },
      "required": ["name", "phone", "incident_date", "location", "injury_description", "age", "death_involved"]
    },
    "qualification": {
      "type": "object",
      "properties": {
        "within_statute": {"type": "boolean"},
        "at_fault": {"type": "boolean"},
        "received_treatment": {"type": "boolean"},
        "other_party_insured": {"type": "boolean"},
        "caller_has_um_coverage": {"type": ["boolean", "null"]},
        "flags": {"type": "array", "items": {"type": "string"}}
      },
      "required": ["within_statute", "at_fault", "received_treatment", "other_party_insured", "flags"]
    },
    "notes": {"type": "string"}
  },
  "required": ["intake", "qualification", "notes"]
}
```

Vapi auto-fills these from its own call metadata, so the tool schema does **not** include them:

- `call_id` — Vapi's own call ID
- `caller_phone` — ANI / caller number
- `started_at`, `ended_at` — call timestamps
- `audio_url` — Vapi's hosted recording
- `transcript` — Vapi's transcription

The server URL receives the tool call plus Vapi's standard metadata, merged.

## Attach phone number

**Phone Numbers → your number → Attach to Assistant → MVA-Intake v0.1**.

## First live test

1. Start ngrok (`bash scripts/ngrok-start.sh`) — copy the https URL.
2. Paste it into the assistant's Server URL (append `/webhook/mva-intake`).
3. From any phone, dial the Vapi number.
4. Run through the interview.
5. Check:
   - **Vapi Dashboard → Calls** — transcript captured, `submit_intake` fired at end.
   - **n8n → Executions** — one success entry.
   - **HubSpot** — new deal in the right pipeline column with all 8 custom properties populated.
   - **Your phone** — SMS arrives within 60s.

## Payload envelope check

Vapi sometimes wraps tool output inside an end-of-call-report envelope instead of posting the raw schema. After the first live test, open the n8n execution → Webhook node → check the received body shape:

- **If** the body has top-level `call_id`, `intake`, `qualification` — we're good. Nothing to change.
- **If** the body is `{ message: { type: "end-of-call-report", ..., artifact: { structuredData: {...} } } }` — add a one-line unwrapper Code node between Webhook and Config:

```javascript
const raw = $input.first().json.body || $input.first().json;
const payload = raw?.message?.artifact?.structuredData
             || raw?.message?.artifact?.submitIntake
             || raw?.body
             || raw;
return [{ json: { body: payload } }];
```

## Known limitations (Phase 3)

- **ngrok free URL changes each session** — update Vapi's Server URL each time.
- **HubSpot search indexing lag** — dedup works for Vapi retries >10s apart. Fast retries may still create duplicates.
- **Twilio trial prefix** — every SMS begins with *"Sent from your Twilio trial account -"* until you upgrade.
- **No contact dedup** — a repeat caller creates a new HubSpot contact each call. Deal dedup by `vapi_call_id` still works. Phase 3.5 adds contact-upsert-by-phone.
