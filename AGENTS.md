# AGENTS.md

Division of responsibilities between the two runtime agents in this system: the **Vapi Voice Agent** and the **n8n Orchestration Agent**. Each one has a single job. When a task spans both, the contract between them is the webhook payload defined at the bottom of this file.

---

## 1. Vapi Voice Agent

**Runtime:** Vapi
**Role:** Talk to the caller, run the structured interview, hand structured data to n8n.
**Status:** Not yet built — Phase 3.

### Responsibilities

- Answer the inbound call in under 2 seconds.
- Greet with firm-branded opening line.
- Run the qualification interview (see `project-building.md` → *Interview Beats*).
- Capture all `intake` fields including `injury_description`, `age`, `death_involved`.
- Collect answers for `qualification.at_fault`, `received_treatment`, `other_party_insured`, `caller_has_um_coverage` (bools/nulls).
- Emit `qualification.flags[]` for ambiguous or edge-case answers (`at_fault_unsure`, `minor_involved`, `wrongful_death`, `out_of_state`, `multi_party`, `hit_and_run`).
- Handle unqualified callers gracefully — **never hang up abruptly**.
- End the call with a clear next-step message.
- POST the final structured JSON (matching the frozen contract below) to the n8n webhook.

### Must Not

- Make the qualification *decision*. It collects answers; n8n decides.
- Write directly to the CRM or send SMS.
- Emit free-form prose in qualification fields — those are deterministic bools/enums. Free prose belongs in `notes` or `injury_description`.

### Prompt Contract

The system prompt must produce deterministic slots. Every answer maps to a named field in the final end-of-call-report tool call. `notes` is the only field that carries free-form summary text.

---

## 2. n8n Orchestration Agent

**Runtime:** n8n (local, `http://localhost:5678`)
**Role:** Receive the Vapi payload, qualify, route to CRM + SMS.
**Status:** Live. Workflow `MVA-Intake-v0.1-Phase1` (ID `Z9MKDm6ULzQtmRqA`), 20 nodes, active.

### Responsibilities

- Expose `POST /webhook/mva-intake` for Vapi to call at end-of-call.
- Validate the payload shape; reject malformed requests with `400` + error detail.
- Apply the firm's qualification rules (statute + 4-part gate + `flags[]` edge cases).
- Route to one of three buckets:
  - **`qualified`:** create HubSpot Contact + Deal (stage `qualified`), SMS the on-call attorney with the deal URL, respond `200`.
  - **`non_qualified`:** create HubSpot Contact + Deal (stage `non_qualified`), no SMS, respond `200`.
  - **`human_review`:** create HubSpot Contact + Deal (stage `human_review`), SMS the attorney with `REVIEW —` prefix, respond `200`.
- All three routes return a JSON response including `call_id`, `contact_id`, `deal_id`, `deal_url`, `sms_sid` (when sent), `reason`, `phase`.

### Must Not

- Talk to the caller. Voice is Vapi's job.
- Re-ask qualification questions. If data is ambiguous, Vapi must emit a `flags[]` entry; n8n routes to `human_review` — it never calls back.
- Hardcode firm-specific rules inside expressions. Stage IDs, statute threshold, attorney phone, Twilio sender all live in the top-of-workflow **Config** Set node so they are discoverable and tunable per-firm.
- Store tokens inline. HubSpot + Twilio auth lives in n8n credentials, referenced by name on each node.

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

### Dedup (Phase 3)

Between Qualifier and Switch Route, the flow searches HubSpot for an existing deal with the same `vapi_call_id`. If one is found, Switch Route is skipped and a short-circuit response is returned — no duplicate contact, no duplicate deal, no duplicate SMS. This guards against Vapi webhook retries after timeouts.

Response when deduplicated:

```json
{"duplicate": true, "call_id": "...", "deal_id": "...", "deal_url": "...", "note": "Already processed - duplicate call_id", "phase": "phase-3"}
```

Caveat: HubSpot search indexing is eventually-consistent (~5-10s lag). A retry inside that window may still create a duplicate. Production retries are typically >30s apart.

### Downstream Routing (n8n, implemented in Phase 2, preserved in Phase 3)

Each non-duplicate payload resolves to exactly one of three routes. The Qualifier Code node emits `route` + `hubspot_stage_id`; the Switch Route node hands off to the right branch. Each branch creates HubSpot Contact → Deal (associated), then optionally sends SMS, then converges on `Respond 200`.

1. **`qualified`** — all four gates pass AND `flags` is empty → HubSpot contact + deal (stage `qualified`) + Twilio SMS.
2. **`non_qualified`** — any gate fails AND `flags` is empty → HubSpot contact + deal (stage `non_qualified`), no SMS.
3. **`human_review`** — any `flags` entry, regardless of gate outcome → HubSpot contact + deal (stage `human_review`) + Twilio SMS with `REVIEW —` prefix.

Archive to separate compliance storage is deferred; HubSpot's deal `description` carries the `audio_url` for now.

### Response Shape (Phase 2)

```json
{
  "route": "qualified" | "non_qualified" | "human_review",
  "call_id": "vapi_...",
  "contact_id": "<HubSpot contact ID>",
  "deal_id": "<HubSpot deal ID>",
  "deal_url": "https://app-na2.hubspot.com/contacts/<portal>/record/0-3/<deal_id>",
  "sms_sid": "SM..."  // present on qualified + human_review only
  "reason": "<why this route was chosen>",
  "phase": "phase-2"
}
```

On validation failure: `400` with `{"error": "validation_failed", "detail": "<which field>"}`.

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
