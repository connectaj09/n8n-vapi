# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project

**After-Hours Legal Intake Voice Agent** — a voice-first AI receptionist for law firms that captures, qualifies, and routes after-hours leads. Built on **Vapi** (voice) and **n8n** (orchestration).

Read `project-building.md` for the full architecture. Read `AGENTS.md` for the division of responsibilities between Vapi and n8n.

## Stack

- **Vapi** — voice layer (ASR, LLM dialog, TTS). Owns the qualification interview.
- **n8n** — orchestration layer. Receives structured JSON from Vapi, applies intake criteria, routes outputs.
- **CRM targets** — Filevine, Litify, MyCase, Lawmatics (one per deployment).
- **SMS** — attorney notification channel (Twilio or equivalent).
- **Storage** — audio + transcript retention for compliance.

## Qualification Criteria (MVA default)

A lead is `qualified` only if **all** of the following hold:

1. Incident date within statute of limitations
2. Caller was not at fault
3. Caller received medical treatment
4. Other party has insurance (collectability)

Unqualified calls are **not hung up on** — they are logged politely and marked `non-qualified`. See `project-building.md` → *The Unqualified Path*.

## SLAs

- **Pickup:** < 2 seconds
- **Attorney SMS:** < 60 seconds after call ends
- **CRM lead creation:** same cycle as SMS

## Working Conventions

- Prefer the `n8n-mcp` tools when creating, validating, or updating workflows — do not hand-write workflow JSON when a tool exists.
- When adding a node, call `search_nodes` / `get_node` before guessing the node type or parameter shape.
- Always run `validate_workflow` before `n8n_create_workflow` or `n8n_update_full_workflow`.
- Treat the Vapi → n8n webhook payload as a versioned contract. Document any schema change in `project-building.md`.
- Do not commit secrets. Use n8n credential references, not inline API keys.

## Out of Scope (for now)

- Multi-language support
- Warm transfers to a live attorney mid-call
- Calendar booking inside the call
- Languages other than English

These may be added later — do not pre-build for them.
