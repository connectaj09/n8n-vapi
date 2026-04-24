# CLAUDE.md

Guidance for Claude Code when working in this repository.

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

- Phase 0 (domain) ✅ | Phase 1 (webhook scaffold) ✅ | Phase 2 (HubSpot + Twilio integrations) ✅ | Phase 3 (live Vapi) ⏳
- Active workflow: `MVA-Intake-v0.1-Phase1`, n8n ID `Z9MKDm6ULzQtmRqA`
- Webhook URL: `http://localhost:5678/webhook/mva-intake`
- 4/4 fixtures pass end-to-end (`bash scripts/test-intake.sh`)

## Repo Layout

- `project-building.md` — full architecture, phases, HubSpot field map, interview beats, legal/compliance
- `AGENTS.md` — Vapi ↔ n8n division of labor + frozen webhook payload contract
- `fixtures/` — 4 mock Vapi payloads (qualified, non_qualified, human_review, invalid)
- `workflows/mva-intake-v0.2.json` — importable snapshot of the live workflow
- `scripts/test-intake.sh` — one-shot smoke runner against the local webhook
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
