# Babel PRD — Phase 2: International Communicator

## Overview
- Persona: International Communicator — users messaging across languages (friends, family, colleagues).
- Goal: Remove language friction by translating in real time, surfacing cultural context, and helping users adjust tone across languages.
- Scope: Deliver all 5 required AI features for this persona plus 1 advanced capability.
- Simplifications: Any source language → device language (QA focus EN↔JA), OpenAI provider, enabled by default, no feature flags, client-side caching only, no telemetry.

## Objectives
- Enable seamless cross-language conversations with minimal user effort.
- Provide trustworthy translations while preserving tone and intent.
- Offer lightweight, on-demand explanations for slang/idioms and cultural nuance.
- Keep privacy and latency in check for a fluid chat experience.

## Success Metrics
- Adoption: Users in EN↔JA chats see translations by default; qualitative feedback from testers is positive.
- Latency: P95 translation round-trip ≤ 900 ms for ≤ 1500 char messages on Wi‑Fi/LTE.
- Quality: Translations judged “useful” in informal QA across 20 test cases per direction.
- Stickiness: Auto-translate remains enabled in channels by default with option to disable.

## Out of Scope (Phase 2)
- Voice translation/transcription.
- Offline translation.
- Server-side rewriting of message bodies (no destructive edits to originals).
- Per-sender auto-translation rules beyond channel-level defaults.
- Telemetry/analytics dashboards.

## Assumptions
- Mobile: iOS 16+ (SwiftUI), existing Stream Chat integration remains.
- Backend: Vercel serverless for AI endpoints; OpenAI as provider (gpt-4o-mini or similar) with keys stored in Vercel env.
- Preferences: Stored per-device (UserDefaults) to keep implementation simple; no cross-device sync in Phase 2.

## Features (Required)
1) Real-time translation (inline) — Any source → device language (QA focus EN↔JA)
- Show translated text inline beneath original with a quick toggle (Show Original/Show Translation).
- Composer action: “Translate and send to {detected other language}” appears when last incoming ≠ device language; preview before sending.

2) Language detection & auto-translate (default ON)
- Detect language for incoming/outgoing text on-device, and auto-translate to the viewer’s preferred language when the channel is set to auto-translate.

3) Cultural context hints
- Message action: “Explain” (combined) returns concise definitions and cultural/politeness notes for the detected language; results shown in device language.

4) Formality level adjustment
- Composer action to rewrite the draft into more formal/neutral/casual variants before sending.

5) Slang/idiom explanations
- Included in the combined “Explain” action above (no separate menu item).

## Advanced Capability
Context-Aware Smart Replies (chosen)
- Offer 2–3 reply suggestions in the user’s device language, consistent with tone preference and last few messages (short window). If last incoming language ≠ device language, show a “Translate and send to {detected}” pill after insertion.

## User Experience
- Incoming messages auto-translate to device language by default; per-message “Show Original” toggle.
- Long-press on message shows: Translate/Show Original, Explain, Copy, Report.
- Composer has a “Tone” pill (Formal/Neutral/Casual) and shows a “Translate and send to {detected}” pill when last incoming ≠ device language.
- Smart Replies: On-demand via a Suggestions button near the composer; chips insert editable text.

## Data & Privacy
- Client defaults to on-device language detection (NaturalLanguage.NLLanguageRecognizer). Only the necessary text snippet is sent to AI endpoints.
- No long-term storage of message bodies or translations on our servers; ephemeral processing only. Client-side cache with short TTL (≈2 hours) for repeat requests.
- No RAG: the model receives a short sliding window (last ~6 messages) for context only when needed (e.g., smart replies).
- PII guidelines: redact emails/phones by pattern before sending to AI unless user explicitly includes them in composer actions.

## Performance & Reliability Targets
- P95 latency ≤ 900 ms for translation/explanation/rewrites.
- Timeouts at 3–5 s with clear fallback UI; retries limited with exponential backoff.
- Degrade gracefully: if AI fails, show original content and a retry affordance.

## Acceptance Criteria
- Inline translation works reliably for any source → device language (validated EN↔JA) with stable toggling.
- Auto-translate is enabled by default per channel and persists on-device across sessions.
- Cultural context and slang explanations return relevant, concise guidance in < 1.5 s P95.
- Formality rewrite offers formal/neutral/casual and respects emoji/punctuation.
- Context-aware smart replies produce 2–3 suggestions for EN or JA and are editable before sending.

## Risks & Mitigations
- Translation accuracy variance → Provide “Show Original” and easy retry.
- Latency spikes → On-device detection; keep payloads short; client-side caching.
- Cost overrun → On-demand smart replies (user-triggered), text length caps.
- Privacy concerns → Redact patterns; document data handling; user can disable auto-translate per channel.
