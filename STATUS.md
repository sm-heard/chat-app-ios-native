# Babel Project Status

## Context
- Babel is a native iOS chat MVP built with SwiftUI and the Stream Chat SDK, backed by a Vercel token service and device-bound Sign in with Apple auth.
- The PRD targets reliable 1:1 and group messaging with presence, typing, read receipts, offline sync, and foreground notifications.
- We are in the “stable core chat” phase of the implementation plan; APNs integrated.

## Recent Progress
- Upgraded authentication to Sign in with Apple: credentials persist in Keychain, refresh when possible, and the Vercel `api/stream/token.ts` endpoint verifies Apple tokens, exchanges codes/refresh tokens, and sanitizes Stream user IDs before issuing chat tokens.
- Token endpoint now auto-creates the `messaging:babel-general` channel and ensures each user is added, so everyone lands in a shared space while preserving 1:1 flows.
- iOS UI shows a tabbed experience with a branded “Chats” list and a Profile tab that surfaces stored IDs and token state for debugging.
- Channel composer supports direct messages and group creation (optional naming), lists other known users with presence badges, and handles Stream errors gracefully.
- Push plumbing is in place end-to-end: Info.plist and entitlements include push configuration, the app requests authorization and forwards APNs tokens via `PushNotificationManager`, and the `/api/stream/push/register` endpoint attaches devices to Stream under the `chat-app-ios-native` provider.
- Client configuration relies on Info.plist/environment keys (`STREAM_API_KEY`, `TOKEN_ENDPOINT`, `PUSH_PROVIDER_NAME`), keeping server secrets confined to Vercel env vars.

## Current Status & Next Steps
- Core chat flows (Sign in with Apple, auto-joined General channel, 1:1 and group chats) have been exercised on real devices and are behaving correctly.
- Push registration succeeds
- No secrets are committed in source; it remains safe to check in app entitlements and config files as long as Info.plist placeholders stay generic.
- Continue monitoring Stream channel defaults so `babel-general` persists as the communal space and adjust naming in config if dashboard changes.

## Open Risks & Follow-Ups
- Push notifications must be validated on physical hardware; simulators will not register APNs tokens.
- Apple token refresh on the backend depends on `APPLE_PRIVATE_KEY`, team ID, and key ID staying present in Vercel—losing them will break silent re-auth.
- For production rollout, remember to switch `aps-environment` and Stream push provider credentials to their production counterparts.
