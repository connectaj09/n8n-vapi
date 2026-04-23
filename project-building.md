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

A new lead is created with all fields prefilled in the firm's CMS:

- Filevine
- Litify
- MyCase
- Lawmatics

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
| CRM | Filevine / Litify / MyCase / Lawmatics | Lead record of truth |
| Notification | SMS provider (e.g., Twilio) | On-call attorney alert |
| Storage | Audio + transcript store | Compliance and QA |
