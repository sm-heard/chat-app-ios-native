import type { VercelRequest, VercelResponse } from "@vercel/node";
import { StreamChat } from "stream-chat";

const apiKey = process.env.STREAM_API_KEY;
const apiSecret = process.env.STREAM_API_SECRET;
const defaultProviderName = process.env.STREAM_PUSH_PROVIDER_NAME ?? "chat-app-ios-native";

if (!apiKey || !apiSecret) {
  // eslint-disable-next-line no-console
  console.warn("STREAM_API_KEY or STREAM_API_SECRET is not configured.");
}

type PushRegistrationPayload = {
  user_id?: unknown;
  device_token?: unknown;
  push_provider?: unknown;
  push_provider_name?: unknown;
};

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method Not Allowed" });
  }

  if (!apiKey || !apiSecret) {
    return res.status(500).json({ error: "Stream credentials missing on server" });
  }

  const {
    user_id: userId,
    device_token: deviceToken,
    push_provider: pushProvider,
    push_provider_name: pushProviderName,
  }: PushRegistrationPayload =
    req.body ?? {};

  if (typeof userId !== "string" || userId.trim().length === 0) {
    return res.status(400).json({ error: "Missing user_id" });
  }

  if (typeof deviceToken !== "string" || deviceToken.trim().length === 0) {
    return res.status(400).json({ error: "Missing device_token" });
  }

  const providerType = typeof pushProvider === "string" && pushProvider.trim().length > 0 ? pushProvider : "apn";
  const providerName =
    typeof pushProviderName === "string" && pushProviderName.trim().length > 0
      ? pushProviderName.trim()
      : defaultProviderName;

  try {
    const serverClient = StreamChat.getInstance(apiKey, apiSecret);
    await serverClient.addDevice(deviceToken, providerType as "apn" | "apn_voip", userId.trim(), providerName);
    return res.status(200).json({ status: "ok" });
  } catch (error) {
    console.error("Push registration failed", error);
    const message = error instanceof Error ? error.message : "Push registration failed";
    return res.status(500).json({ error: message });
  }
}
