import type { VercelRequest, VercelResponse } from "@vercel/node";
import { createRemoteJWKSet, importPKCS8, jwtVerify, SignJWT, type JWTPayload } from "jose";
import { StreamChat } from "stream-chat";

const apiKey = process.env.STREAM_API_KEY;
const apiSecret = process.env.STREAM_API_SECRET;
const appleClientId =
  process.env.APPLE_CLIENT_ID ?? process.env.APPLE_APP_ID ?? "com.smheard.chat-app-ios-native";
const appleTeamId = process.env.APPLE_TEAM_ID;
const appleKeyId = process.env.APPLE_KEY_ID;
const applePrivateKey = process.env.APPLE_PRIVATE_KEY?.replace(/\\n/g, "\n");
const canUseAppleTokenAPI = Boolean(appleTeamId && appleKeyId && applePrivateKey);

if (!apiKey || !apiSecret) {
  // eslint-disable-next-line no-console
  console.warn("STREAM_API_KEY or STREAM_API_SECRET is not configured.");
}

if (!process.env.APPLE_CLIENT_ID && !process.env.APPLE_APP_ID) {
  // eslint-disable-next-line no-console
  console.warn("APPLE_CLIENT_ID is not configured. Falling back to bundle identifier for audience.");
}

if (!canUseAppleTokenAPI) {
  // eslint-disable-next-line no-console
  console.warn("APPLE_TEAM_ID, APPLE_KEY_ID, or APPLE_PRIVATE_KEY is missing. Token exchanges will be skipped.");
}

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
    apple_user_id: appleUserIdInput,
    name,
    image,
    email,
    identityToken,
    authorizationCode,
    refreshToken,
    language,
  }: {
    user_id?: unknown;
    apple_user_id?: unknown;
    name?: unknown;
    image?: unknown;
    email?: unknown;
    identityToken?: unknown;
    authorizationCode?: unknown;
    refreshToken?: unknown;
    language?: unknown;
  } = req.body ?? {};

  if (typeof userId !== "string" || userId.trim().length === 0) {
    return res.status(400).json({ error: "Missing user_id" });
  }

  const streamUserId = sanitizeStreamUserId(userId.trim());

  const normalizedLanguage = typeof language === "string" && language.trim().length > 0 ? sanitizeLanguage(language.trim()) : undefined;

  let appleUserId = typeof appleUserIdInput === "string" ? appleUserIdInput.trim() : undefined;
  if (!appleUserId || appleUserId.length === 0) {
    appleUserId = userId.trim();
  }

  if (!appleUserId) {
    return res.status(400).json({ error: "Missing apple_user_id" });
  }

  try {
    let identityTokenForVerification =
      typeof identityToken === "string" && identityToken.trim().length > 0 ? identityToken : undefined;
    let refreshTokenValue =
      typeof refreshToken === "string" && refreshToken.trim().length > 0 ? refreshToken : undefined;
    const authorizationCodeValue =
      typeof authorizationCode === "string" && authorizationCode.trim().length > 0
        ? authorizationCode
        : undefined;

    const identityResult = await ensureIdentityToken(identityTokenForVerification, refreshTokenValue);
    identityTokenForVerification = identityResult.identityToken;
    refreshTokenValue = identityResult.refreshToken ?? refreshTokenValue;

    let appleProfile = await verifyAppleIdentityToken(identityTokenForVerification, appleUserId);

    if (authorizationCodeValue && canUseAppleTokenAPI) {
      const codeTokens = await exchangeAuthorizationCode(authorizationCodeValue);
      if (codeTokens.refresh_token && codeTokens.refresh_token.trim().length > 0) {
        refreshTokenValue = codeTokens.refresh_token;
      }
      if (codeTokens.id_token && codeTokens.id_token.trim().length > 0) {
        identityTokenForVerification = codeTokens.id_token;
        appleProfile = await verifyAppleIdentityToken(identityTokenForVerification, appleUserId);
      }
    }

    const emailFromApple =
      typeof appleProfile.email === "string" && isEmailVerified(appleProfile.email_verified)
        ? appleProfile.email
        : undefined;
    const finalEmail =
      typeof email === "string" && email.trim().length > 0 ? email : emailFromApple ?? undefined;

    const serverClient = StreamChat.getInstance(apiKey, apiSecret);

    await serverClient.upsertUser({
      id: streamUserId,
      name,
      image,
      email: finalEmail,
      language: normalizedLanguage,
    });

    await ensureGeneralChannelMembership(serverClient, streamUserId);

    const token = serverClient.createToken(streamUserId);

    return res.status(200).json({
      token,
      user: { id: streamUserId, name, image, email: finalEmail, language: normalizedLanguage },
      apiKey,
      refreshToken: refreshTokenValue,
      appleIdentityToken: identityTokenForVerification,
      appleUserId,
    });
  } catch (error) {
    console.error("Token issuance failed", error);
    if (error instanceof AppleIdentityError) {
      return res.status(error.statusCode).json({ error: error.message });
    }
    return res.status(500).json({ error: "Token issuance failed" });
  }
}

const appleIssuer = "https://appleid.apple.com";
const appleJWKS = createRemoteJWKSet(new URL(`${appleIssuer}/auth/keys`));
const appleTokenURL = `${appleIssuer}/auth/token`;
let cachedPrivateKey: CryptoKey | undefined;

class AppleIdentityError extends Error {
  constructor(message: string, public readonly statusCode: number, cause?: unknown) {
    super(message);
    this.name = "AppleIdentityError";
    if (cause) {
      // Attach cause for debugging in environments that support it.
      (this as Error & { cause?: unknown }).cause = cause;
    }
  }
}

type AppleIdentityPayload = JWTPayload & {
  sub: string;
  email?: string;
  email_verified?: string | boolean;
};

async function verifyAppleIdentityToken(identityToken: string, expectedUserId: string) {
  let payload: AppleIdentityPayload;
  try {
    const result = await jwtVerify(identityToken, appleJWKS, {
      issuer: appleIssuer,
      audience: appleClientId,
      algorithms: ["RS256"],
    });
    payload = result.payload as AppleIdentityPayload;
  } catch (error) {
    throw new AppleIdentityError("Invalid Sign in with Apple token", 401, error);
  }

  if (!payload.sub || payload.sub !== expectedUserId) {
    throw new AppleIdentityError("Apple identity mismatch", 401);
  }

  return payload;
}

function isEmailVerified(value: AppleIdentityPayload["email_verified"]): boolean {
  if (typeof value === "boolean") {
    return value;
  }
  if (typeof value === "string") {
    return value.toLowerCase() === "true";
  }
  return false;
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

type IdentityResolutionResult = {
  identityToken: string;
  refreshToken?: string;
};

type AppleTokenResponse = {
  access_token?: string;
  expires_in?: number;
  id_token?: string;
  refresh_token?: string;
  token_type?: string;
  error?: string;
  error_description?: string;
};

async function ensureIdentityToken(
  identityToken: string | undefined,
  refreshToken: string | undefined
): Promise<IdentityResolutionResult> {
  if (identityToken && identityToken.trim().length > 0) {
    return { identityToken };
  }

  if (!refreshToken || refreshToken.trim().length === 0) {
    throw new AppleIdentityError("Missing identityToken", 401);
  }

  const refreshedTokens = await refreshWithApple(refreshToken);
  if (!refreshedTokens.id_token || refreshedTokens.id_token.trim().length === 0) {
    throw new AppleIdentityError("Unable to refresh Sign in with Apple token", 401);
  }

  const normalizedRefresh =
    refreshedTokens.refresh_token && refreshedTokens.refresh_token.trim().length > 0
      ? refreshedTokens.refresh_token
      : refreshToken;

  return {
    identityToken: refreshedTokens.id_token,
    refreshToken: normalizedRefresh,
  };
}

async function exchangeAuthorizationCode(code: string): Promise<AppleTokenResponse> {
  if (!canUseAppleTokenAPI) {
    return {};
  }
  const clientSecret = await generateAppleClientSecret();
  const params = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    client_id: appleClientId,
    client_secret: clientSecret,
  });
  return postToAppleTokenEndpoint(params);
}

async function refreshWithApple(refreshToken: string): Promise<AppleTokenResponse> {
  if (!canUseAppleTokenAPI) {
    throw new AppleIdentityError("Sign in with Apple refresh unavailable on server", 500);
  }
  const clientSecret = await generateAppleClientSecret();
  const params = new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: refreshToken,
    client_id: appleClientId,
    client_secret: clientSecret,
  });
  return postToAppleTokenEndpoint(params);
}

async function postToAppleTokenEndpoint(params: URLSearchParams): Promise<AppleTokenResponse> {
  const response = await fetch(appleTokenURL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: params.toString(),
  });

  let body: AppleTokenResponse;
  try {
    body = (await response.json()) as AppleTokenResponse;
  } catch (error) {
    throw new AppleIdentityError("Apple token endpoint returned invalid JSON", 502, error);
  }

  if (!response.ok) {
    const description = body.error_description ?? body.error ?? "Apple token exchange failed";
    const status = response.status === 400 ? 401 : response.status;
    throw new AppleIdentityError(description, status);
  }

  return body;
}

async function generateAppleClientSecret(): Promise<string> {
  if (!appleTeamId || !appleKeyId || !applePrivateKey) {
    throw new AppleIdentityError("Apple Sign in with Apple key not configured on server", 500);
  }

  const privateKey = await getApplePrivateKey();
  const now = Math.floor(Date.now() / 1000);
  return new SignJWT({})
    .setIssuer(appleTeamId)
    .setSubject(appleClientId)
    .setAudience(appleIssuer)
    .setIssuedAt(now)
    .setExpirationTime(now + 300) // 5 minutes
    .setProtectedHeader({ alg: "ES256", kid: appleKeyId })
    .sign(privateKey);
}

async function getApplePrivateKey(): Promise<CryptoKey> {
  if (cachedPrivateKey) {
    return cachedPrivateKey;
  }
  if (!applePrivateKey) {
    throw new AppleIdentityError("APPLE_PRIVATE_KEY is not configured", 500);
  }
  cachedPrivateKey = await importPKCS8(applePrivateKey, "ES256");
  return cachedPrivateKey;
}

async function ensureGeneralChannelMembership(client: StreamChat, userId: string) {
  try {
    const channel = client.channel("messaging", "babel-general", {
      name: "General",
    });

    try {
      await channel.create();
    } catch (error: any) {
      if (!(error instanceof Error) || !("code" in error) || (error as any).code !== 17) {
        throw error;
      }
    }

    try {
      await channel.addMembers([userId]);
    } catch (error: any) {
      if (!(error instanceof Error) || !("code" in error) || ![4, 40].includes((error as any).code)) {
        throw error;
      }
    }
  } catch (error) {
    console.warn("Failed to ensure General channel membership", error);
  }
}
