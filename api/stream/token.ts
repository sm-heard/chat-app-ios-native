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

  const { user_id: userId, name, image } = req.body ?? {};

  if (typeof userId !== "string" || userId.trim().length === 0) {
    return res.status(400).json({ error: "Missing user_id" });
  }

  try {
    const serverClient = StreamChat.getInstance(apiKey, apiSecret);

    await serverClient.upsertUser({
      id: userId,
      name,
      image,
    });

    const token = serverClient.createToken(userId);

    return res.status(200).json({
      token,
      user: { id: userId, name, image },
      apiKey,
    });
  } catch (error) {
    console.error("Token issuance failed", error);
    return res.status(500).json({ error: "Token issuance failed" });
  }
}

