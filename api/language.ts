import type { VercelRequest, VercelResponse } from "@vercel/node";
import { StreamChat } from "stream-chat";

const apiKey = process.env.STREAM_API_KEY;
const apiSecret = process.env.STREAM_API_SECRET;

if (!apiKey || !apiSecret) {
  // eslint-disable-next-line no-console
  console.warn("STREAM_API_KEY or STREAM_API_SECRET is not configured.");
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method Not Allowed" });
  }

  if (!apiKey || !apiSecret) {
    return res.status(500).json({ error: "Stream credentials missing on server" });
  }

  const { user_id: userIdInput, language: languageInput } = (await parseJSON(req.body)) ?? {};

  if (typeof userIdInput !== "string" || userIdInput.trim().length === 0) {
    return res.status(400).json({ error: "Missing user_id" });
  }

  if (typeof languageInput !== "string" || languageInput.trim().length === 0) {
    return res.status(400).json({ error: "Missing language" });
  }

  const userId = sanitizeStreamUserId(userIdInput.trim());
  const language = sanitizeLanguage(languageInput.trim());
  if (!language) {
    return res.status(400).json({ error: "Unsupported language code" });
  }

  try {
    const serverClient = StreamChat.getInstance(apiKey, apiSecret);
    await serverClient.upsertUser({ id: userId, language });
    return res.status(200).json({ status: "ok" });
  } catch (error) {
    console.error("Language update failed", error);
    return res.status(500).json({ error: "Unable to update language" });
  }
}

async function parseJSON(body: unknown) {
  if (!body) {
    return {};
  }
  if (typeof body === "object") {
    return body as Record<string, unknown>;
  }
  try {
    return JSON.parse(String(body));
  } catch {
    return {};
  }
}

function sanitizeStreamUserId(id: string): string {
  const sanitized = id.replace(/[^A-Za-z0-9@_-]/g, "-");
  if (sanitized.length > 0) {
    return sanitized;
  }
  return "user-" + Math.random().toString(36).replace(/[^a-z0-9]/g, "").slice(0, 8);
}

function sanitizeLanguage(code: string): string | undefined {
  const normalized = code.trim();
  if (!/^[A-Za-z-]{2,10}$/.test(normalized)) {
    return undefined;
  }
  return normalized;
}
