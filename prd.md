# Babel PRD (MVP)

## Product Vision
- Build a native iOS chat app that delivers reliable, fast, real-time messaging with offline support and minimal backend.
- Establish a clean foundation to add AI features post‑MVP.

## Goals (MVP)
- One‑to‑one chat and basic group chat (3+ users).
- Real‑time delivery with optimistic UI updates and timestamps.
- Message states: sending, sent, delivered, read.
- Presence (online/offline) and typing indicators.
- Local persistence and offline send/receive with sync on reconnect.
- Temporary device‑bound authentication (Keychain UUID).
- Foreground in‑app notifications; APNs can be deferred to post‑MVP.

## Non‑Goals (MVP)
- End‑to‑end encryption.
- Voice/video calling.
- Advanced moderation, roles/permissions.
- Advanced AI features and persona‑specific flows.
- Heavy custom theming or complex settings.
- Crash reporting (explicitly excluded).

## Assumptions
- Platform: iOS 16+ (SwiftUI).
- Messaging: Stream Chat SwiftUI SDK.
- Backend: Minimal Vercel serverless function for Stream user token issuance.
- Auth: Device‑bound UUID stored in Keychain; upgradeable later.
- Security: Transport‑level security only for MVP.
- Region: US.
- APNs: Optional; can be added after core chat is solid.

## Platform
- App name: Babel
- Bundle ID: com.smheard.chat-app-ios-native
- iOS: Swift 5.9+, SwiftUI, Swift Concurrency.

## User Experience
- First‑run: App generates a device UUID (stored in Keychain) and asks for display name (optional for MVP).
- Channel List: Shows existing 1:1 and group chats, unread counts, last message preview.
- Chat View: Messages with timestamps, delivery/read states; typing indicator; input composer.
- Group Creation: Start group with 3+ participants via a simple member picker.
- Presence: Online/offline indicators in list and chat header.
- Notifications: In‑app banner/toast for new messages while app is foregrounded.

## Functional Requirements
- Authentication
  - Generate and persist a device‑bound UUID in Keychain as `user_id`.
  - Exchange `user_id` (and optional name/avatar) for a Stream user token via Vercel endpoint.
- Channels
  - List user’s channels with pagination.
  - Create 1:1 channels and group channels (3+ members).
  - Show participants and presence indicators.
- Messaging
  - Send/receive text messages in real time.
  - Show states: sending, sent, delivered, read.
  - Show timestamps.
  - Typing indicators in active chats.
  - Optional: image attachments if time allows.
- Offline & Persistence
  - Cache messages locally; survive app restarts.
  - Queue outgoing messages offline and sync on reconnect.
- Notifications
  - Foreground in‑app notification for new messages.
  - APNs background push via Stream (deferred if needed).

## Non‑Functional Requirements
- Reliability: Messages never silently drop; retriable failures.
- Performance: Smooth scrolling, sub‑100ms optimistic send rendering.
- Error Handling: Graceful UI for network errors; retry affordances.
- Security: API secret never ships in app; only in Vercel function.

## Acceptance Criteria
- 1:1 chat works across two devices in real time.
- Group chat with 3+ users functions with correct attribution.
- Presence, typing indicators, and read receipts are visible and accurate.
- Messages persist across restarts; offline send queues and syncs on reconnect.
- In‑app foreground notifications surface new messages while active.
- Device‑bound auth persists via Keychain.
- App connects using server‑issued Stream token (no secrets in client).

## Test Scenarios
- Two simulators/devices exchanging messages.
- Airplane mode while sending; messages sync on reconnect.
- Rapid‑fire messages (20+) without UI jank or loss.
- Force‑quit and reopen; history intact.
- Background/foreground transitions without message loss.

## Dependencies & Services
- Stream Chat (iOS SwiftUI SDK; US region).
- Vercel serverless function for token issuance using Stream Server SDK.

## Risks & Mitigations
- Token service availability: Keep function simple and add basic health checks.
- APNs setup time: Defer until core chat is stable.
- Vendor lock‑in: Keep a thin abstraction over chat service if future migration is a concern.

## Future (Post‑MVP)
- APNs background notifications.
- Persona‑driven AI features for the International Communicator.
- Sign in with Apple; profiles/media; moderation; theming.

