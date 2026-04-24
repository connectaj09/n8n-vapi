# Project Building: After-Hours Legal Intake Voice Agent

## Overview

A voice-first AI receptionist for law firms that captures, qualifies, and routes after-hours leads that would otherwise go to voicemail. The system is built on **Vapi** (voice) and **n8n** (orchestration), with outputs flowing into the firm's case-management software, on-call attorneys, and compliance storage.

## How to Read the Flow

The flow has three layers — **the firm only sees the bottom row**. Everything above that row is invisible infrastructure that produces a single morning artifact: a qualified, prefilled lead.  

---

## Architecture: Three Layers

### 1. Gray Layer — The Caller

Anyone calling outside business hours:

- A person sitting in their car after a crash
- A family member of someone in the ER
- A worker who just got hurt on a construction site

**Today:** These calls go to voicemail and the firm loses them by morning.

### 2. Purple Layer — The AI Brain (Vapi)

This is the product. Vapi handles voice end-to-end:

- **Speech recognition** (ASR)
- **LLM conversation**
- **Text-to-speech** (TTS)
- **Pickup time:** under 2 seconds — faster than any human receptionist

#### Qualification Interview

A structured interview mapped to intake criteria:

| Question | What It Qualifies |
|---|---|
| "When did the accident happen?" | Statute of limitations |
| "Were you the one at fault?" | Liability |
| "Did you go to the hospital?" | Injury severity |
| "Does the other driver have insurance?" | Collectability |

#### Intake Capture

Basic fields collected during the call:

- Name
- Phone number
- Date of incident
- Location

### 3. Teal Layer — System + Outputs (n8n)

**n8n is the decision-maker.** It receives structured JSON from Vapi, evaluates the case against the firm's intake criteria (e.g., *"must be within statute, not at fault, treated by a doctor"*), and only then triggers the three outputs.

#### Output 1 — Case Management System

A new lead is created with all fields prefilled in the firm's CMS.

- **HubSpot Free CRM** — the v1 target for all deployments. Each firm runs its own HubSpot Free tenant; we integrate via a HubSpot Private App token stored as an n8n credential. See *HubSpot Field Mapping* under Phase 0.
- Filevine, Litify, MyCase, Lawmatics — future legal-specific integrations for firms that outgrow HubSpot or prefer a legal-native tool.

#### Output 2 — On-Call Attorney SMS

A text within 60 seconds. Example:

> *"New qualified MVA lead — Maria Lopez, rear-ended yesterday, treated at Mercy ER, has insurance, callback ready."*

#### Output 3 — Compliance Storage

Full audio recording + transcript stored for:

- Compliance review
- Quality assurance
- Future training data

---

## The Unqualified Path (Not in the Diagram)

If a caller doesn't qualify — e.g., a 4-year-old accident past the statute, or a minor fender-bender with no injuries — the agent **does not hang up**. Instead:

1. Politely captures the info
2. Tells the caller the firm will be in touch if they can help
3. Logs the call as `non-qualified`

**Result:** Nothing is wasted, but no human time is spent on it.

---

## Component Responsibilities

| Layer | Tool | Responsibility |
|---|---|---|
| Voice | Vapi | ASR, LLM dialog, TTS, call control |
| Orchestration | n8n | Qualification logic, routing, integrations |
| CRM | HubSpot Free (v1); Filevine / Litify / MyCase / Lawmatics as future targets | Lead record of truth |
| Notification | SMS provider (e.g., Twilio) | On-call attorney alert |
| Storage | Audio + transcript store | Compliance and QA |

---

## Phases

Delivery is sequenced so the domain (Personal Injury / MVA) is locked first, then the Vapi ↔ n8n contract is frozen, then the two engines are built in parallel against that contract.

### Phase 0 — Domain Lock (PI / MVA)

- Expand the 4-part qualification gate with edge cases: out-of-state incidents, minors, wrongful death, uninsured motorist, multi-party.
- Finalize the full intake field list Vapi must capture.
- Draft the interview script *beats* (question order + branches) — not the full prompt yet.
- **CRM chosen: HubSpot Free CRM.** Each firm runs its own HubSpot Free tenant; we integrate via a HubSpot Private App token stored as an n8n credential. See *HubSpot Field Mapping* below.
- Legal: recording-disclosure line, retention policy, state-specific statute thresholds.

#### Qualification Decision Table (MVA — expanded)

The four-part gate still applies. These rules extend it for edge cases. Any row marked `human_review` short-circuits auto-qualification.

| Input | Value | Routing |
|---|---|---|
| Statute | Within threshold (default 2 yrs) | proceed |
| Statute | Outside threshold | `non_qualified` |
| At-fault | No | proceed |
| At-fault | Yes | `non_qualified` |
| At-fault | Unsure | `human_review` |
| Treatment | Received or scheduled | proceed |
| Treatment | None | `non_qualified` |
| Other-party insured | Yes | proceed |
| Other-party insured | No + caller has UM coverage | `human_review` |
| Other-party insured | No + no UM | `non_qualified` |
| Minor (under 18) involved | Yes | `human_review` (statute often tolled) |
| Wrongful death | Yes | `human_review` (different statute) |
| Incident out-of-state | Yes | `human_review` |
| Multi-party / commercial vehicle | Yes | `human_review` |
| Hit-and-run | Yes | `human_review` (UM claim path) |

Thresholds (statute of limitations, minimum treatment cutoff, etc.) are stored in a top-of-workflow **Set** node so they are tunable per firm / per state without code changes.

#### Intake Fields

Fields Vapi must capture by end of call and post to n8n:

| Field | Type | Notes |
|---|---|---|
| Caller full name | string | |
| Callback phone | E.164 string | |
| Incident date | YYYY-MM-DD | |
| Incident location | string | city + state minimum |
| At-fault answer | `yes` \| `no` \| `unsure` | |
| Treatment answer | `yes` \| `no` \| `scheduled` | |
| Other-party insured | `yes` \| `no` \| `unknown` | |
| Caller UM coverage | `yes` \| `no` \| `unknown` | only relevant if other-party uninsured |
| Injury description | free text | short |
| Caller age | integer | flags minors |
| Death involved | bool | routes to wrongful-death path |

#### Interview Beats

Question order and branches for the voice interview. The full Vapi prompt is locked in Phase 2.

1. Greeting + recording-disclosure line (state-aware wording).
2. Emergency check: *"Is anyone seriously injured right now or needing emergency help?"* — if yes, 911 redirect, then continue.
3. Incident date.
4. Incident location (city + state).
5. Fault question.
6. Injury + treatment question.
7. Other-party insurance question (+ UM coverage fallback if they say no).
8. Age / minors check + death-involved check.
9. Callback name + phone.
10. Closing line — qualified path vs non-qualified polite close. The agent **never hangs up**.

#### Legal / Compliance

- **Recording disclosure** — two variants: one for one-party-consent states, one for two-party-consent states. Vapi selects based on caller area code or firm-configured state.
- **Retention** — audio + transcript retained 7 years by default; per-firm configurable.
- **Bar-rule safe language** — the agent never promises representation; closing line says *"someone from the firm will follow up."*
- **PHI care** — medical details are captured in HubSpot and compliance storage, but **never** placed in the attorney SMS body. SMS contains identifiers + a link to the HubSpot deal.

#### HubSpot Field Mapping

HubSpot Free caps custom properties at 10. The design uses **8 custom deal properties** for fields we need to filter / report on, and packs everything else into HubSpot's **built-in fields** (which don't count against the cap). Transcripts are kept in compliance storage — HubSpot only stores the URL.

**HubSpot Contact** (one per caller) — built-in properties only:

| HubSpot property | Built-in? | Source |
|---|---|---|
| `firstname` / `lastname` | built-in | `intake.name` (split on first space) |
| `phone` | built-in | `caller_phone` |
| `lifecyclestage` | built-in | `lead` (qualified) or `subscriber` (non-qualified / human-review) |

**HubSpot Deal** (one per call):

*Built-in properties* (no setup needed — HubSpot creates these by default):

| Property | Source |
|---|---|
| `dealname` | `"MVA Intake — {lastname} — {incident_date}"` |
| `dealstage` | `qualified` \| `non_qualified` \| `human_review` (map to pipeline stage IDs) |
| `description` | rendered narrative block — see below |

*Custom deal properties* (8; created once per firm at setup):

| Property | Type | Source |
|---|---|---|
| `incident_date` | Date | `intake.incident_date` |
| `incident_location` | Single-line text | `intake.location` |
| `within_statute` | Single checkbox | computed at call time (frozen) |
| `at_fault` | Single checkbox | `qualification.at_fault` |
| `received_treatment` | Single checkbox | `qualification.received_treatment` |
| `other_party_insured` | Single checkbox | `qualification.other_party_insured` |
| `review_flags` | Single-line text | comma-joined `qualification.flags[]` |
| `vapi_call_id` | Single-line text | `call_id` (idempotency key) |

*Rendered into the built-in `description` field* (attorney-readable; not filterable):

- `intake.injury_description`
- `intake.age` + `intake.death_involved`
- `qualification.caller_has_um_coverage`
- `started_at`, `ended_at` (+ computed duration)
- `audio_url` (link to compliance storage)
- `transcript_url` (link to compliance storage — transcript itself is stored there, not in HubSpot)
- `notes`

Example `description` block:

```
Injury: neck + back pain, ER-treated
Caller age: 34  |  Death involved: No  |  UM coverage: N/A
Call: 2026-04-22 23:14 → 23:19 (5m 12s)
Audio: https://storage.../audio.mp3
Transcript: https://storage.../transcript.txt

[Notes]
Rear-ended on I-35 southbound, Dallas...
```

**Tradeoff:** fields inside `description` are not filterable or reportable in HubSpot Free — they are readable prose only. If a firm later needs to filter on one (e.g., "all deals with UM coverage claims"), promote it to one of the 2 remaining custom-property slots.

**Per-firm onboarding:**

1. Firm signs up for HubSpot Free at hubspot.com.
2. Firm creates a HubSpot **Private App** with `crm.objects.contacts.*` and `crm.objects.deals.*` scopes (plus `crm.schemas.deals.*` for the one-time property creation).
3. Firm shares the Private App token; we store it as an n8n credential reference (never inline).
4. We run a one-time n8n workflow to create the 8 custom deal properties in that firm's tenant.

### Phase 1 — Contract Lock

- Freeze the Vapi → n8n webhook JSON schema (drafted in `AGENTS.md`). ✅ done — marked FROZEN in `AGENTS.md`.
- Write the n8n webhook validator — the first real code. ✅ done — `MVA-Intake-v0.1-Phase1` workflow (n8n ID `Z9MKDm6ULzQtmRqA`).
- Add a mock payload fixture so n8n can be built without live Vapi calls. ✅ done — 4 fixtures under `fixtures/`.

#### Workflow (Phase 1)

**Local webhook URL:** `http://localhost:5678/webhook/mva-intake`

**Workflow structure** (12 nodes): Webhook → Config → Validator → If Valid → { Qualifier → Switch → [Stub Qualified | Stub Non-Qualified | Stub Human Review] → Respond 200 } or { Build Error Body → Respond 400 }.

Routing buckets (see `AGENTS.md` → Downstream Routing):

- `qualified` → stub emits the HubSpot contact+deal + SMS payload shape (Phase 2 replaces the stub with real HTTP Request nodes).
- `non_qualified` → stub emits a non-qualified deal record, no SMS.
- `human_review` → stub emits a review deal + SMS prefixed `REVIEW —`. Triggered whenever `qualification.flags[]` is non-empty, regardless of the 4-part gate.

**Fixtures** (`fixtures/`): `mock-vapi-qualified.json`, `mock-vapi-non-qualified.json`, `mock-vapi-human-review.json`, `mock-vapi-invalid.json`.

**Smoke test:** `bash scripts/test-intake.sh` — POSTs each fixture and asserts HTTP status + response substring. Exits with number of failures.

**Workflow JSON snapshot:** `workflows/mva-intake-v0.1.json` — importable into any n8n instance. Source of truth is the n8n DB; repo file is a versioned snapshot.

### Phase 2 — Real Integrations (HubSpot + Twilio)

- Replace 3 stub Set nodes with real HTTP + Twilio nodes. ✅ done.
- HubSpot Create Contact + Create Deal (with all 8 custom properties + description + contact association) per branch. ✅ done.
- Twilio SMS on qualified + human-review branches. ✅ done.
- Config node extended with `attorney_phone` + `twilio_from`. ✅ done.
- Compliance archive to separate storage: **deferred** (HubSpot stores the Vapi `audio_url` only).

#### Credentials (n8n)

- `HubSpot App Token account` — credential type `hubspotAppToken`; used by all 6 HubSpot HTTP Request nodes via **Predefined Credential Type**.
- `Twilio account` — credential type `twilioApi`; used by both Twilio SMS nodes.

#### Response shape (Phase 2)

```json
{
  "route": "qualified" | "non_qualified" | "human_review",
  "call_id": "vapi_...",
  "contact_id": "<HubSpot contact ID>",
  "deal_id": "<HubSpot deal ID>",
  "sms_sid": "SM..." (qualified + human_review only),
  "deal_url": "https://app-na2.hubspot.com/contacts/.../record/0-3/<deal_id>",
  "reason": "<reason>",
  "phase": "phase-2"
}
```

#### Workflow snapshot

`workflows/mva-intake-v0.2.json` — importable; replace the `attorney_phone` / `twilio_from` placeholders before activating on a new instance.

### Phase 3 — Integration

- End-to-end: real call → Vapi → n8n → CRM + SMS + archive.
- Golden path + 3 unqualified scenarios + 1 partial-info scenario.
- Verify SLAs: <2s pickup, <60s attorney SMS.

### Phase 4 — Pilot

- Shadow mode at one firm (n8n routes, but a human is also on call), then cutover.
- Weekly transcript review to tune the prompt and adjust per-firm thresholds.
