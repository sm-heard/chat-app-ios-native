# Phase 2 Status — International Communicator

## Context
- Phase 1 (core chat + push) is feature-complete and stable across two test devices.
- Phase 2 focuses on the MessageAI persona “International Communicator,” with OpenAI (gpt-4o-mini) powering all AI affordances.
- All Phase 2 features ship without feature flags and target a straightforward, default-on experience.

## Core Deliverables Implemented
- **Language preference flow:** First-launch modal requires each user to pick a preferred language (defaulted to device locale). Preference is stored locally and synced to Stream via `/api/language`, and can be changed from Profile.
- **Inline translation:** Incoming messages auto-translate to the user’s preferred language with a translation toggle and detected-language chip. Translations cache per message for ~2 hours.
- **Explain action:** Message footer “Explain” button calls the AI endpoint for combined slang/culture guidance, presenting results in the preferred language.
- **Tone adjustment:** Composer offers Formal/Neutral/Casual rewrite support with optimistic UI and recovery on failure.
- **Smart replies:** Suggestions button fetches up to three context-aware replies (last six messages) in the preferred language.
- **Translate & send:** Composer surfaces a one-tap “Translate to {other participant language}” shortcut when a channel member uses a different language.

## Backend / Infrastructure
- Single `/api/ai` endpoint handles translate, explain, tone, and smart reply tasks using the OpenAI Responses API (no `response_format` dependency).
- `/api/language` updates the Stream user’s `language` field, sanitizing IDs and language codes.
- Token endpoint persists preferred language, auto-adds users to `messaging:babel-general`, and refreshes Sign in with Apple credentials when available.

## Outstanding Work
- Verify `/api/language` is deployed and accessible from Vercel; confirm auth/edge routing in production.
- Manual QA sweep for:
  - First-launch language prompt (new and existing accounts).
  - Profile language changes syncing back to Stream and reflecting in other members’ UI.
  - AI endpoints under poor network conditions and for longer (>500 char) messages.
- Define manual TestFlight checklist that covers translation toggles, explain action, tone rewrites, and smart replies across EN↔JA.
- Ensure Stream dashboard retains push provider “chat-app-ios-native” and that preferred language shows under user extra data.

## Testing Notes
- No automated tests yet for language persistence, translation cache eviction, or AI failure states; rely on manual regression for now.
- Push notifications verified previously on physical hardware; confirm they continue to work after AI additions.
