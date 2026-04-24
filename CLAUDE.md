# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Glossary

Domain terms used across the docs, code, and SMS bodies. Keep these definitions in mind when reading fixtures, prompts, and qualification logic.

**Legal / intake**

- **Attorney** — a lawyer licensed to represent clients; here, the on-call person who gets the SMS and decides whether to call the lead back.
- **Retained** — the moment a client formally hires the attorney (signs a fee agreement); in our HubSpot pipeline, the "closed won" stage.
- **Lead** — a potential client, i.e. any caller before qualification. Becomes a "case" if retained.
- **Intake** — the process of gathering enough information from a caller to decide whether the firm will represent them.
- **Qualification** — the decision "is this lead worth an attorney's time?"; driven by our 4-part gate + flags.
- **Personal Injury (PI)** — the legal domain covering bodily-harm claims (car crashes, slip-and-fall, medical malpractice, etc.). Our v1 vertical.
- **MVA** — Motor Vehicle Accident; the specific PI sub-type we handle in v1 (car/truck/motorcycle collisions).
- **Statute of limitations** — the legal deadline after which a lawsuit can no longer be filed. Varies by state and claim type (Texas MVA is 2 years). If the incident is older, the case is dead on arrival.
- **Tolled (statute)** — the deadline is paused or extended. Most common for minors: the clock doesn't start until they turn 18. Why `minor_involved` always routes to human review.
- **Liability / at-fault** — who caused the accident. If our caller was at fault, there's no one else to sue, so the case is unqualified.
- **Collectability** — whether the at-fault party (or their insurer) actually has assets to pay a judgment. An uninsured defendant with no assets = no recovery, even with a winning case.
- **Uninsured Motorist (UM) coverage** — the caller's own auto policy add-on that pays out when the other driver is uninsured. Turns an otherwise uncollectable case into a qualified one.
- **Hit-and-run** — at-fault driver flees the scene; the claim typically goes through the caller's UM coverage. Routes to human review because it's a UM/insurance-process case, not a standard third-party claim.
- **Wrongful death** — a claim brought on behalf of someone killed by another's negligence. Different statute, different damages, different procedure — always human review.
- **Non-qualified** — a lead that fails our criteria. Still captured politely; no attorney SMS; lands in HubSpot's `Non-Qualified` stage for record-keeping.
- **Human review** — the "we can't auto-decide this" bucket. Attorney opens HubSpot, reads transcript + notes, decides manually.
- **Bar rules** — the ethics rules each state's bar association imposes on lawyers. Relevant to us because the voice agent cannot make promises of representation (would violate rules on unauthorized practice / advertising).
- **PHI** — Protected Health Information. Medical details captured in the call are sensitive; we keep them inside HubSpot + compliance storage, never in SMS bodies.
- **Recording disclosure** — the spoken notice at the start of the call ("this call may be recorded"). Required in two-party-consent states; optional in one-party-consent states. Vapi picks the variant based on caller/firm state.

**Tech / infrastructure**

- **Webhook** — an HTTP endpoint we expose so Vapi can POST the end-of-call payload to us. Our webhook is `POST /webhook/mva-intake`.
- **E.164** — the international phone number format (`+<country-code><number>`, no spaces/dashes). All phone fields use it.
- **Idempotency** — the property that running the same operation twice has no extra effect. We're *not* idempotent yet — duplicate calls create duplicate deals. `vapi_call_id` is the key we'll use for dedup in Phase 3.
- **Pipeline / Stage (HubSpot)** — pipeline = the overall sales process; stage = a single column in it. Our six stages map 1:1 to the routing buckets plus follow-on outcomes.
- **Private App Token (HubSpot)** — the single-account auth token we use for API calls; begins with `pat-na2-...`. Stored as an n8n credential, never inline.

## Project

**After-Hours Legal Intake Voice Agent** — a voice-first AI receptionist for law firms that captures, qualifies, and routes after-hours leads. Built on **Vapi** (voice) and **n8n** (orchestration).

Read `project-building.md` for the full architecture. Read `AGENTS.md` for the division of responsibilities between Vapi and n8n.

## Stack

- **Vapi** — voice layer (ASR, LLM dialog, TTS). Owns the qualification interview. *Not wired yet — Phase 3.*
- **n8n** — orchestration layer. Receives structured JSON from Vapi, applies intake criteria, routes outputs. *Running locally at `http://localhost:5678`.*
- **CRM (v1)** — **HubSpot Free CRM**, one tenant per firm, integrated via a HubSpot Private App token stored as an n8n credential. Filevine, Litify, MyCase, Lawmatics are future targets.
- **SMS** — **Twilio**, credential stored in n8n. Trial tier currently (adds a "Sent from your Twilio trial account -" prefix).
- **Storage** — audio + transcript held on Vapi's side; URL referenced in HubSpot deal `description`. Separate compliance archive deferred.

## Current State

- Phase 0 (domain) ✅ | Phase 1 (webhook scaffold) ✅ | Phase 2 (HubSpot + Twilio) ✅ | Phase 3 (dedup + Vapi-ready) ✅ — pending first live call
- Active workflow: `MVA-Intake-v0.1-Phase1`, n8n ID `Z9MKDm6ULzQtmRqA`, 23 nodes
- Webhook URL: `http://localhost:5678/webhook/mva-intake` (local) — Vapi hits this via ngrok
- **5/5 fixtures pass** end-to-end via `bash scripts/test-intake.sh` (qualified, non_qualified, human_review, invalid, dedup)
- Vapi assistant config: `docs/vapi-setup.md` (copy-paste reference; assistant lives in Vapi dashboard)
- ngrok launcher: `bash scripts/ngrok-start.sh` (free tier; URL rotates per session)

## Repo Layout

- `project-building.md` — full architecture, phases, HubSpot field map, interview beats, legal/compliance
- `AGENTS.md` — Vapi ↔ n8n division of labor + frozen webhook payload contract
- `fixtures/` — 4 mock Vapi payloads (qualified, non_qualified, human_review, invalid)
- `workflows/mva-intake-v0.2.json` — importable snapshot of the live workflow
- `scripts/test-intake.sh` — one-shot smoke runner (5 cases: 3 routes + invalid + dedup)
- `scripts/ngrok-start.sh` — opens an ngrok tunnel so Vapi can reach our local n8n
- `docs/vapi-setup.md` — Vapi assistant config reference (system prompt, `submit_intake` tool schema)
- `Pipeline-ids.txt` — **gitignored** scratch file; contains live secrets, do not commit

## Qualification Criteria (MVA default)

A lead is `qualified` only if **all four** hold AND `qualification.flags[]` is empty:

1. Incident date within statute of limitations (default 2 years; per-firm tunable via Config Set node)
2. Caller was not at fault
3. Caller received medical treatment (received OR scheduled)
4. Other party has insurance — OR caller has uninsured-motorist coverage

If any `flags[]` entry is present (`minor_involved`, `wrongful_death`, `out_of_state`, `multi_party`, `hit_and_run`, `at_fault_unsure`), the lead routes to `human_review` regardless of the four-part gate.

Unqualified calls are **not hung up on** — they are captured, land in HubSpot under `Non-Qualified` stage, and generate **no SMS**. See `project-building.md` → *The Unqualified Path*.

## SLAs

- **Pickup:** < 2 seconds
- **Attorney SMS:** < 60 seconds after call ends
- **CRM lead creation:** same cycle as SMS

## Working Conventions

- Prefer the `n8n-mcp` tools when creating, validating, or updating workflows — do not hand-write workflow JSON when a tool exists.
- When adding a node, call `search_nodes` / `get_node` before guessing the node type or parameter shape.
- Always run `validate_workflow` before `n8n_create_workflow`; after mutations, run `n8n_validate_workflow` against the workflow ID to confirm server-side validity.
- For multi-step mutations, prefer `n8n_update_partial_workflow` with one atomic batch. Use `validateOnly: true` to preview.
- Treat the Vapi → n8n webhook payload as a versioned contract. It is **frozen** as of Phase 1 — any change requires bumping the workflow version and updating Vapi tool def + n8n validator + `project-building.md`.
- **Never commit secrets.** Use n8n credential references, not inline API keys. `Pipeline-ids.txt` is gitignored; leave it that way.
- Credentials on HubSpot/Twilio nodes can be referenced by **name only** (`{name: "HubSpot App Token account"}`) when only one credential of that type exists in the instance — n8n-mcp resolves the ID automatically.
- n8n's public API does not allow listing credentials. If a credential ID is genuinely needed, grab it from the n8n UI URL when editing the credential.

## Out of Scope (for now)

- Multi-language support
- Warm transfers to a live attorney mid-call
- Calendar booking inside the call
- Languages other than English

These may be added later — do not pre-build for them.
