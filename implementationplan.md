# Babel Implementation Plan (MVP)

Easiest path: Stream Chat SwiftUI SDK + minimal Vercel token service + device‑bound auth. APNs can be deferred until after core chat is stable. No crash reporting.

## At‑a‑Glance
- Client: SwiftUI (iOS 16+), Stream Chat SwiftUI SDK, Keychain UUID auth.
- Backend: Vercel serverless function to mint Stream user tokens (US region).
- Notifications: In‑app foreground notifications at MVP; APNs via Stream optional post‑MVP.
- App: Babel (bundle id: com.smheard.chat-app-ios-native).

## Prerequisites
- Apple Developer account (already available).
- Stream Chat account (create an app in US region).
- Vercel account and project.

## Milestones
1) Day 0: Stream setup, Vercel token API, iOS project skeleton
2) Day 1: Channel list + messaging; presence, typing, read receipts; offline cache
3) Day 2: In‑app notifications; reliability polish; test scenarios; (optional) APNs

## 1) Stream Setup
- Create a Stream app in the dashboard; select Region: US.
- Copy credentials:
  - STREAM_API_KEY (public; used by client and server)
  - STREAM_API_SECRET (private; server‑only)
- Optional: Lock server token endpoint by domain/IP/cors as needed.

## 2) Vercel Token API
Purpose: Issue Stream user tokens for your device‑bound UUID and upsert basic user profile.

- Stack: Node.js/TypeScript on Vercel serverless (Node runtime, not Edge).
- Endpoint: `POST /api/stream/token`
  - Request JSON: `{ "user_id": "<uuid>", "name": "<optional>", "image": "<optional>" }`
  - Response JSON: `{ "token": "<jwt>", "user": { ... }, "apiKey": "<STREAM_API_KEY>" }`
- Env vars (Vercel Project Settings → Environment Variables):
  - `STREAM_API_KEY` = your Stream API key (from dashboard)
  - `STREAM_API_SECRET` = your Stream API secret (from dashboard)
  - Optional `STREAM_REGION` = `us` (or leave unset; default US)

Example handler (TypeScript):

```ts
// api/stream/token.ts
import type { VercelRequest, VercelResponse } from "@vercel/node";
import { StreamChat } from "stream-chat";

const apiKey = process.env.STREAM_API_KEY!;
const apiSecret = process.env.STREAM_API_SECRET!;

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") return res.status(405).json({ error: "Method Not Allowed" });
  try {
    const { user_id, name, image } = req.body || {};
    if (!user_id) return res.status(400).json({ error: "Missing user_id" });

    const serverClient = StreamChat.getInstance(apiKey, apiSecret);
    await serverClient.upsertUser({ id: user_id, name, image });

    const token = serverClient.createToken(user_id);
    return res.status(200).json({ token, user: { id: user_id, name, image }, apiKey });
  } catch (e: any) {
    return res.status(500).json({ error: "Token issuance failed", detail: e?.message });
  }
}
```

Quick test (after deploy):

```bash
curl -X POST https://<your-vercel-app>.vercel.app/api/stream/token \
  -H 'Content-Type: application/json' \
  -d '{"user_id":"test-uuid","name":"Test User"}'
```

Expected: JSON with `token` and `apiKey`.

## 3) iOS App (SwiftUI + Stream)
- Create Xcode project: Name "Babel", bundle id `com.smheard.chat-app-ios-native`, iOS 16+, SwiftUI.
- Add SPM packages:
  - Stream Chat SwiftUI SDK: https://github.com/GetStream/stream-chat-swift
- App configuration:
  - Store `STREAM_API_KEY` in a small config (safe to ship in client).
  - Store `TOKEN_ENDPOINT` (your Vercel URL) in config.

Auth & Connect flow:
1) On first launch, generate/store a UUID in Keychain as `user_id`.
2) Call Vercel `POST /api/stream/token` with `{ user_id, name? }`.
3) Initialize `ChatClient` with API key, then connect user with the returned token.

Swift (illustrative):

```swift
import SwiftUI
import StreamChat
import StreamChatSwiftUI

final class AppChatController: ObservableObject {
    static let shared = AppChatController()
    private(set) var client: ChatClient!

    func configureAndConnect(userId: String, name: String?) {
        let config = ChatClientConfig(apiKeyString: "<STREAM_API_KEY>")
        client = ChatClient(config: config)
        fetchToken(userId: userId, name: name) { token in
            self.client.connectUser(
                userInfo: .init(id: userId, name: name),
                token: .init(token)
            ) { error in
                if let error { print("Connect error: \(error)") }
            }
        }
    }

    private func fetchToken(userId: String, name: String?, completion: @escaping (String) -> Void) {
        // Make POST to TOKEN_ENDPOINT and parse `token`
        // Call completion(token)
    }
}
```

UI wiring (SwiftUI):

```swift
@main
struct BabelApp: App {
    var body: some Scene {
        WindowGroup {
            ChannelList()
                .onAppear { bootstrap() }
        }
    }

    private func bootstrap() {
        let userId = KeychainService.shared.userId() // generate/store UUID
        AppChatController.shared.configureAndConnect(userId: userId, name: nil)
    }
}
```

- Use Stream SwiftUI components for speed: Channel list and message views.
- Offline cache is enabled by default (SQLite). Messages persist and sync on reconnect.
- Presence, typing, read receipts are provided by the SDK components.

Group creation:
- Use Stream channel creation APIs (e.g., create a `messaging` channel with member IDs).

In‑app foreground notifications:
- Subscribe to new message events and surface a lightweight in‑app banner/toast while active.

## 4) Optional: APNs via Stream (Post‑MVP OK)
- Upload your APNs Auth Key (.p8), Key ID, and Team ID to Stream dashboard.
- In app:
  - Request notification permission and register for remote notifications.
  - On `didRegisterForRemoteNotificationsWithDeviceToken`, add device to current user via Stream iOS SDK.
- Validate background pushes with a second device sending messages while the app is backgrounded.

## 5) Testing Checklist
- Two devices real‑time chat (1:1 and group 3+).
- Offline send with airplane mode; sync on reconnect.
- Rapid‑fire 20+ messages; no message loss; UI stays responsive.
- Force‑quit and reopen; history intact.
- Background/foreground lifecycle transitions.

## Secrets & Configuration Guide
Where to get and add secrets/keys:

- Stream (Dashboard):
  - Obtain `STREAM_API_KEY` and `STREAM_API_SECRET` from your Stream app (Region: US).
- Vercel (Project → Settings → Environment Variables):
  - Add `STREAM_API_KEY` and `STREAM_API_SECRET` (Production and Preview).
  - Redeploy to apply.
- iOS App:
  - Embed `STREAM_API_KEY` in app config (public).
  - Set `TOKEN_ENDPOINT` to your deployed Vercel URL.
  - Do NOT embed `STREAM_API_SECRET` in the app.

When you’re ready, I can scaffold the Vercel function and the iOS boilerplate with placeholders for `STREAM_API_KEY`, `TOKEN_ENDPOINT`, and the Keychain utility.

