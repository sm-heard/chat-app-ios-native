import type { VercelRequest, VercelResponse } from "@vercel/node";
import OpenAI from "openai";

type SupportedTask = "translate" | "explain" | "tone" | "smart_replies";

type TranslatePayload = {
  text?: unknown;
  target?: unknown;
  source?: unknown;
  message_id?: unknown;
};

type ExplainPayload = {
  text?: unknown;
  target?: unknown;
};

type TonePayload = {
  text?: unknown;
  target?: unknown;
  style?: unknown;
};

type SmartRepliesPayload = {
  messages?: unknown;
  target?: unknown;
};

type SmartReplyMessage = {
  role: "user" | "other";
  text: string;
  lang?: string;
};

const MODEL = process.env.OPENAI_MODEL?.trim() || "gpt-4o-mini";
const MAX_TEXT_LENGTH = 1_500;
const MAX_HISTORY_MESSAGES = 6;

const apiKey = process.env.OPENAI_API_KEY?.trim();
const client = apiKey ? new OpenAI({ apiKey }) : null;

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method Not Allowed" });
  }

  if (!client) {
    return res.status(500).json({ error: "OPENAI_API_KEY is not configured" });
  }

  const task = typeof req.body?.task === "string" ? (req.body.task as SupportedTask) : undefined;
  const payload = req.body?.payload;

  if (!task || !isSupportedTask(task)) {
    return res.status(400).json({ error: "Missing or unsupported task" });
  }

  try {
    switch (task) {
      case "translate":
        return res.status(200).json(await handleTranslate(payload as TranslatePayload));
      case "explain":
        return res.status(200).json(await handleExplain(payload as ExplainPayload));
      case "tone":
        return res.status(200).json(await handleTone(payload as TonePayload));
      case "smart_replies":
        return res.status(200).json(await handleSmartReplies(payload as SmartRepliesPayload));
      default:
        return res.status(400).json({ error: "Unsupported task" });
    }
  } catch (error) {
    console.error("AI task failed", error);
    if (isHttpError(error)) {
      return res.status(error.status).json({ error: error.message });
    }
    return res.status(500).json({ error: "AI request failed" });
  }
}

const SUPPORTED_TASKS: Set<SupportedTask> = new Set(["translate", "explain", "tone", "smart_replies"]);

function isSupportedTask(task: string): task is SupportedTask {
  return SUPPORTED_TASKS.has(task as SupportedTask);
}

class HttpError extends Error {
  constructor(message: string, public readonly status: number) {
    super(message);
    this.name = "HttpError";
  }
}

function isHttpError(error: unknown): error is HttpError {
  return error instanceof HttpError;
}

function validateText(field: string, value: unknown): string {
  if (typeof value !== "string") {
    throw new HttpError(`${field} must be a string`, 400);
  }
  const trimmed = value.trim();
  if (!trimmed) {
    throw new HttpError(`${field} is required`, 400);
  }
  if (trimmed.length > MAX_TEXT_LENGTH) {
    throw new HttpError(`${field} exceeds max length of ${MAX_TEXT_LENGTH} characters`, 400);
  }
  return trimmed;
}

function validateLanguage(field: string, value: unknown): string {
  if (typeof value !== "string") {
    throw new HttpError(`${field} must be a string`, 400);
  }
  const trimmed = value.trim();
  if (!trimmed) {
    throw new HttpError(`${field} is required`, 400);
  }
  return trimmed.slice(0, 32);
}

function normalizeLanguage(code: string | undefined): string | undefined {
  if (!code) {
    return undefined;
  }
  return code.toLowerCase();
}

async function handleTranslate(raw: TranslatePayload) {
  const text = validateText("text", raw.text);
  const target = normalizeLanguage(validateLanguage("target", raw.target));
  const source = normalizeLanguage(typeof raw.source === "string" ? raw.source : undefined);

  const instructions = `You are a precise translation assistant. Translate the provided text into the target language while preserving intent, tone, emojis, and formatting. If the text already matches the target language, return the original unchanged. Provide JSON with keys: translation (string), detected_language (BCP-47 code), and quality (one of excellent|good|fair).`;

  const response = await client!.responses.create({
    model: MODEL,
    temperature: 0.2,
    input: [
      {
        role: "system",
        content: `${instructions} Respond with a single JSON object only.`,
      },
      {
        role: "user",
        content: JSON.stringify({
          text,
          target_language: target,
          source_language: source ?? "auto",
        }),
      },
    ],
  });

  const parsed = safeParseJSON(extractText(response));
  const translation = validateText("translation", parsed.translation);

  return {
    translation,
    detectedLanguage: typeof parsed.detected_language === "string" ? parsed.detected_language : source,
    quality: typeof parsed.quality === "string" ? parsed.quality : undefined,
  };
}

async function handleExplain(raw: ExplainPayload) {
  const text = validateText("text", raw.text);
  const target = normalizeLanguage(validateLanguage("target", raw.target));

  const response = await client!.responses.create({
    model: MODEL,
    temperature: 0.3,
    input: [
      {
        role: "system",
        content:
          "You clarify slang, idioms, and cultural nuances succinctly. Reply with JSON { explanation, tips } where tips is optional guidance for tone, politeness, or context. Keep responses under 120 words in the target language. Respond with a single JSON object only.",
      },
      {
        role: "user",
        content: JSON.stringify({ text, target_language: target }),
      },
    ],
  });

  const parsed = safeParseJSON(extractText(response));
  const explanation = validateText("explanation", parsed.explanation);

  return {
    explanation,
    tips: typeof parsed.tips === "string" ? parsed.tips.trim() : undefined,
  };
}

async function handleTone(raw: TonePayload) {
  const text = validateText("text", raw.text);
  const target = normalizeLanguage(validateLanguage("target", raw.target));
  const style = validateToneStyle(raw.style);

  const response = await client!.responses.create({
    model: MODEL,
    temperature: 0.4,
    input: [
      {
        role: "system",
        content:
          "Rewrite the message in the requested tone (formal, neutral, or casual) while keeping meaning intact. Output JSON { rewritten, notes }. Keep rewritten message ready to send. Respond with a single JSON object only.",
      },
      {
        role: "user",
        content: JSON.stringify({ text, target_language: target, tone: style }),
      },
    ],
  });

  const parsed = safeParseJSON(extractText(response));
  const rewritten = validateText("rewritten", parsed.rewritten);

  return {
    rewritten,
    notes: typeof parsed.notes === "string" ? parsed.notes.trim() : undefined,
  };
}

async function handleSmartReplies(raw: SmartRepliesPayload) {
  if (!Array.isArray(raw.messages)) {
    throw new HttpError("messages must be an array", 400);
  }
  const target = normalizeLanguage(validateLanguage("target", raw.target));

  const history: SmartReplyMessage[] = raw.messages
    .map((msg) => {
      if (!msg || typeof msg !== "object") {
        return undefined;
      }
      const role = (msg as SmartReplyMessage).role;
      const text = (msg as SmartReplyMessage).text;
      if ((role !== "user" && role !== "other") || typeof text !== "string" || !text.trim()) {
        return undefined;
      }
      const lang = typeof (msg as SmartReplyMessage).lang === "string" ? (msg as SmartReplyMessage).lang : undefined;
      return { role, text: text.trim(), lang: normalizeLanguage(lang) } satisfies SmartReplyMessage;
    })
    .filter((msg): msg is SmartReplyMessage => Boolean(msg))
    .slice(-MAX_HISTORY_MESSAGES);

  if (history.length === 0) {
    throw new HttpError("messages array cannot be empty", 400);
  }

  const latest = history[history.length - 1];

  const response = await client!.responses.create({
    model: MODEL,
    temperature: 0.4,
    input: [
      {
        role: "system",
        content:
          "You generate thoughtful reply suggestions for a chat user. Each suggestion must sound like a natural continuation of the conversation and should directly address the most recent message. Lean on prior turns for context, reference specific details (names, plans, questions), and avoid bland small talk. Offer up to three varied options that are concise and ready to send. Return only JSON shaped as {\"suggestions\": [string...]}.",
      },
      {
        role: "user",
        content: JSON.stringify({
          target_language: target,
          latest_message: {
            speaker: latest.role,
            text: latest.text,
            language: latest.lang,
          },
          history: history.map((message) => ({
            speaker: message.role,
            text: message.text,
            language: message.lang,
          })),
        }),
      },
    ],
  });

  const parsed = safeParseJSON(extractText(response));
  const suggestions = Array.isArray(parsed.suggestions)
    ? parsed.suggestions
        .map((item: unknown) => (typeof item === "string" ? item.trim() : ""))
        .filter((item: string) => item.length > 0)
        .slice(0, 3)
    : [];

  if (suggestions.length === 0) {
    throw new HttpError("No suggestions produced", 502);
  }

  return { suggestions };
}

function validateToneStyle(value: unknown): "formal" | "neutral" | "casual" {
  if (typeof value !== "string") {
    throw new HttpError("style must be a string", 400);
  }
  const normalized = value.trim().toLowerCase();
  if (normalized === "formal" || normalized === "neutral" || normalized === "casual") {
    return normalized;
  }
  throw new HttpError("style must be one of formal, neutral, or casual", 400);
}

function safeParseJSON(value: string) {
  try {
    return JSON.parse(value);
  } catch (error) {
    console.warn("Failed to parse JSON response", value, error);
    throw new HttpError("AI returned invalid JSON", 502);
  }
}

function extractText(response: any): string {
  if (response.output_text && typeof response.output_text === "string" && response.output_text.trim()) {
    return cleanJSONText(response.output_text);
  }

  if (Array.isArray(response.output)) {
    const text = response.output
      .flatMap((item: any) => item.content ?? [])
      .filter((content: any) => content.type === "output_text" && content.text != null)
      .map((content: any) => extractContentText(content.text))
      .join("\n");
    if (text.trim()) {
      return cleanJSONText(text);
    }
  }

  if (response.data?.[0]?.content?.[0]?.text) {
    return cleanJSONText(extractContentText(response.data[0].content[0].text));
  }

  throw new HttpError("AI returned empty response", 502);
}

function cleanJSONText(value: string): string {
  const trimmed = value.trim();
  if (trimmed.startsWith("```")) {
    return trimmed.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();
  }
  return trimmed;
}

function extractContentText(value: any): string {
  if (typeof value === "string") {
    return value;
  }
  if (value && typeof value === "object" && typeof value.value === "string") {
    return value.value;
  }
  return String(value ?? "");
}
