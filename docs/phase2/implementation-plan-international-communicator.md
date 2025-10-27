# Implementation Plan — Phase 2: International Communicator

## Architecture Summary
- Client (iOS):
  - On-device language detection via `NaturalLanguage.NLLanguageRecognizer` (any source → device language target).
  - New message actions: Translate/Show Original, Explain (combined), Tone Rewrite; composer Suggestions button.
  - Auto-translate default ON; first-launch language picker stores preferred language per user; per-message Show Original toggle.
  - Client-side translation cache (messageId+targetLang) with ~2h TTL.
- Server (Vercel):
  - Single endpoint: `/api/ai` with `task` param: `translate | explain | tone | smart_replies`.
  - Provider: OpenAI (`gpt-4o-mini`) via server-side SDK; env: `OPENAI_API_KEY`.
  - Guardrails: input length caps; minimal logging; no telemetry; no RAG (short sliding window only when needed).

## Milestones
1) Foundations (Day 1)
- Add iOS language detection utility; derive default target from device language; build language settings manager and first-launch picker; persist tone preference.
- Scaffold single Vercel endpoint `/api/ai` with mock responses.
- Derive API base from existing `TOKEN_ENDPOINT` (drop `/api/stream/token`). No new Info.plist keys.

2) Translation & Detection (Days 2–3)
- Implement `task=translate` tuned for general fidelity and tone preservation; validate EN↔JA.
- Client: Translate/Show Original; auto-translate default ON; inline rendering with language chip.
- Add client cache (messageId+targetLang) and optimistic UI.

3) Explain (combined) (Day 4)
- Implement `task=explain` to return concise definition + cultural/politeness hints (<= 120 words) in device language.
- Long-press action wired; collapsible inline card with copy.

4) Tone Adjustment (Day 5)
- Implement `task=tone` returning formal/neutral/casual candidates.
- Composer UI: tone pills; preview and replace draft.

5) Advanced Capability (Days 6–7)
- Smart Replies: `task=smart_replies` returns 2–3 suggestions in device language using last ~6 messages (roles + langs).
- UX: “Suggestions” button near composer to fetch on-demand; chips insert editable text. If last incoming ≠ device language, show “Translate and send to {detected}”.

6) Polish & QA (Day 8)
- Latency polish (parallel detection), error states, loading skeletons.
- Manual test matrix focused on EN↔JA.

## API Contract (Single Endpoint)
- `POST /api/ai`
  - Request: `{ task: "translate"|"explain"|"tone"|"smart_replies", payload: object }`
  - Translate payload: `{ text: string, target: string, source?: string, message_id?: string }`
  - Explain payload: `{ text: string, target: string }`
  - Tone payload: `{ text: string, target: string, style: "formal"|"neutral"|"casual" }`
  - Smart replies payload: `{ messages: Array<{ role: "user"|"other", text: string, lang?: string }>, target: string }`
  - Response: per task, minimal JSON (`translation`, `explanation`, `rewritten`, `suggestions`)

Notes:
- All requests authenticated (reuse existing auth/session as applicable). Max text length capped (e.g., 1500 chars) with 400 errors if exceeded.

## iOS Changes
- UI
  - Incoming messages: auto-translate with per-message “Show Original”.
  - Message long-press: Translate/Show Original, Explain.
  - Composer: Tone pills (Formal/Neutral/Casual), Suggestions button; show “Translate and send to {detected}” when last incoming ≠ device language.
- Data
  - Preferences model: `{ preferredLanguage: String, tonePreference: String }` in `UserDefaults`.
  - Translation cache keyed by `(messageId, targetLang)` with short TTL (~2h).
- Networking
  - `AIService` client for `/api/ai` with timeouts, retries, and redaction helpers.

## Security & Privacy
- Server-side key custody only; client never holds LLM keys.
- Minimal logs (no message content). Pattern-based redaction for PII before AI calls.

## Telemetry
- None for Phase 2 (keep it simple). Use ad-hoc console logs for QA only.

## Testing
- Unit: language detection wrapper, AIService request builder, UI state reducers.
- Integration: mock server responses, timeout paths, retry logic.
- Manual matrix: Any→device with QA focus on EN↔JA; include a few smoke tests for ES/FR/DE; long/short texts; emojis; code-mixed inputs.

## Rollout
- Ship to all users (no feature flags). Validate via TestFlight builds.

## Risks & Mitigations
- Latency/Cost spikes → caching, length caps, batch requests, progressive disclosure of AI UI.
- Accuracy disputes → “Show Original” and quick retry with alternative prompt.
- UX clutter → keep actions in long-press, minimal header affordances, collapsible cards.

## Required Config
- Vercel env: `OPENAI_API_KEY`.
- iOS: no new keys; derive AI base URL from existing `TOKEN_ENDPOINT`.
