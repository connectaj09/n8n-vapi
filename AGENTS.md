# AGENTS.md

Division of responsibilities between the two runtime agents in this system: the **Vapi Voice Agent** and the **n8n Orchestration Agent**. Each one has a single job. When a task spans both, the contract between them is the webhook payload defined at the bottom of this file.

---

## 1. Vapi Voice Agent

**Runtime:** Vapi
**Role:** Talk to the caller, run the structured interview, hand structured data to n8n.

### Responsibilities

- Answer the inbound call in under 2 seconds.
- Greet with firm-branded opening line.
- Run the qualification interview (see `project-building.md`).
- Capture intake fields: name, phone, date of incident, location.
- Handle unqualified callers gracefully — never hang up abruptly.
- End the call with a clear next-step message.
- POST the final structured JSON to the n8n webhook.

### Must Not

- Make the qualification *decision*. It collects answers; n8n decides.
- Write directly to the CRM.
- Send the attorney SMS.
- Store audio or transcript on its own beyond the Vapi call record.

### Prompt Contract

The system prompt must produce deterministic slots. Every answer maps to a named field in the final tool call / end-of-call report. No free-form summaries in the payload — those go in a separate `notes` field.

---

## 2. n8n Orchestration Agent

**Runtime:** n8n
**Role:** Receive the Vapi payload, qualify, route, and notify.

### Responsibilities

- Expose a **Webhook** trigger node that Vapi calls at end-of-call.
- Validate the payload shape and reject malformed requests.
- Apply the firm's qualification rules (statute, fault, treatment, insurance).
- Branch on `qualified` vs `non-qualified`.
- **Qualified path:**
  1. Create lead in the firm's CRM (Filevine / Litify / MyCase / Lawmatics).
  2. Send SMS to the on-call attorney within 60 seconds.
  3. Archive audio URL + transcript to compliance storage.
- **Non-qualified path:**
  1. Log the call to a `non-qualified` table / sheet.
  2. No attorney notification.
  3. Still archive audio + transcript.
- Return a 200 response to Vapi with a correlation ID.

### Must Not

- Talk to the caller. Voice is Vapi's job.
- Re-ask qualification questions. If a field is missing, flag it and route to a human-review queue — do not call back.
- Hardcode firm-specific rules inside expressions. Put rule thresholds in a Set node or `n8n_manage_datatable` record at the top of the workflow so they are discoverable and tunable per-firm.

---

## Contract: Vapi → n8n Webhook Payload

> **Status:** FROZEN as of Phase 1 (workflow `MVA-Intake-v0.1-Phase1`, n8n ID `Z9MKDm6ULzQtmRqA`). Any future change requires bumping the workflow version and updating all three of: Vapi assistant tool def, n8n validator, and this document.

```json
{
  "call_id": "vapi_...",
  "caller_phone": "+1...",
  "started_at": "ISO-8601",
  "ended_at": "ISO-8601",
  "intake": {
    "name": "string",
    "phone": "string",
    "incident_date": "YYYY-MM-DD",
    "location": "string",
    "injury_description": "string",
    "age": 0,
    "death_involved": false
  },
  "qualification": {
    "within_statute": true,
    "at_fault": false,
    "received_treatment": true,
    "other_party_insured": true,
    "caller_has_um_coverage": null,
    "flags": []
  },
  "audio_url": "https://...",
  "transcript": "string",
  "notes": "string"
}
```

### Field Notes

- `intake.age` — used by n8n to flag minors (`< 18`) into the `human_review` path, since statute of limitations is typically tolled for minors.
- `intake.death_involved` — routes to the wrongful-death path, which has a different statute and always requires human review.
- `qualification.caller_has_um_coverage` — only relevant when `other_party_insured` is false. Enables the uninsured-motorist claim path.
- `qualification.flags` — array of string flags that force `human_review` routing regardless of the four-part gate. Known values:
  - `"minor_involved"`
  - `"wrongful_death"`
  - `"out_of_state"`
  - `"multi_party"`
  - `"hit_and_run"`
  - `"at_fault_unsure"`

### Downstream Routing (n8n)

Each payload resolves to exactly one of three routes:

1. `qualified` — all four gates pass AND `flags` is empty → create HubSpot contact + deal (stage `qualified`), SMS attorney, archive.
2. `non_qualified` — any gate fails AND `flags` is empty → log to HubSpot with stage `non_qualified`, no SMS, archive.
3. `human_review` — any `flags` entry, regardless of gate outcome → create HubSpot deal with stage `human_review`, SMS attorney with `REVIEW` prefix, archive.

### Schema Change Discipline

Any change to this schema must be reflected in:

1. The Vapi assistant's tool / end-of-call-report definition.
2. The n8n webhook validator.
3. `project-building.md` architecture doc.
4. The HubSpot custom-property list (see *HubSpot Field Mapping* in `project-building.md`).

---

## Handoff Rules

- **Vapi owns the conversation.** n8n never speaks to the caller.
- **n8n owns the decision.** Vapi never decides if a lead is qualified.
- **Both own observability.** Vapi keeps the call record; n8n keeps the routing record; the two are joined by `call_id`.
