// ============================================================
// 📲 Edge Function: send-push (FCM HTTP v1 API)
// ============================================================
// يُرسِل إشعار FCM لِكلّ أَجهزة المُستَخدِم النَشطة عَبر HTTP v1 API.
//
// يُستَدعى من:
//   1. Database trigger (تلقائيّاً عند INSERT في notifications)
//   2. أو مُباشَرةً من الـclient عَبر supabase.functions.invoke()
//
// Body (JSON):
//   {
//     "user_id": "uuid",        ← المُستَخدِم المُستَقبِل
//     "title":   "...",         ← عُنوان الإشعار
//     "body":    "...",         ← (اختياريّ)
//     "data":    {...},         ← (اختياريّ) لِلـdeep linking
//     "priority": "high"        ← (اختياريّ)
//   }
//
// المُتَطَلَّبات (Environment variables):
//   - SUPABASE_URL                   (تلقائيّ)
//   - SUPABASE_SERVICE_ROLE_KEY      (تلقائيّ)
//   - FCM_SERVICE_ACCOUNT            ← JSON string لِـ Firebase service account
//
// كَيف تَحصُل عَلى FCM_SERVICE_ACCOUNT:
//   Firebase Console → ⚙ Project Settings → Service accounts
//   → "Generate new private key" → JSON file → اِنسَخ مُحتَواه كامِلاً
// ============================================================

import { serve } from "https://deno.land/std@0.220.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";
import { create as createJwt, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface PushPayload {
  user_id: string;
  title: string;
  body?: string;
  data?: Record<string, unknown>;
  priority?: "low" | "normal" | "high" | "urgent";
}

interface DeviceToken {
  token: string;
  platform: string;
}

interface FcmResult {
  total: number;
  sent: number;
  failed: number;
  invalid_tokens_removed: number;
  errors?: string[];
}

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
  token_uri: string;
}

// ============================================================
// 🔐 OAuth2 token cache (per function instance)
// ============================================================
let cachedToken: { token: string; expiresAt: number } | null = null;

async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt > now + 60) {
    return cachedToken.token;
  }

  const iat = getNumericDate(0);
  const exp = getNumericDate(60 * 60);

  const payload = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: sa.token_uri || "https://oauth2.googleapis.com/token",
    iat,
    exp,
  };

  const pem = sa.private_key.replace(/\\n/g, "\n");
  const cryptoKey = await importPemKey(pem);

  const jwt = await createJwt({ alg: "RS256", typ: "JWT" }, payload, cryptoKey);

  const resp = await fetch(sa.token_uri || "https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!resp.ok) {
    const errText = await resp.text();
    throw new Error(`OAuth2 token exchange failed: ${resp.status} ${errText}`);
  }

  const data = await resp.json();
  cachedToken = {
    token: data.access_token,
    expiresAt: now + (data.expires_in ?? 3600),
  };
  return cachedToken.token;
}

async function importPemKey(pem: string): Promise<CryptoKey> {
  const pemHeader = "-----BEGIN PRIVATE KEY-----";
  const pemFooter = "-----END PRIVATE KEY-----";
  const pemContents = pem
    .replace(pemHeader, "")
    .replace(pemFooter, "")
    .replace(/\s+/g, "");
  const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    binaryDer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

async function sendToToken(
  accessToken: string,
  projectId: string,
  token: string,
  payload: PushPayload,
): Promise<{ ok: boolean; invalidToken: boolean; error?: string }> {
  const isHigh = payload.priority === "high" || payload.priority === "urgent";

  const message: Record<string, unknown> = {
    token,
    notification: {
      title: payload.title,
      body: payload.body ?? "",
    },
    data: Object.fromEntries(
      Object.entries(payload.data ?? {}).map(([k, v]) => [k, String(v)]),
    ),
    android: {
      priority: "HIGH", // دائِماً HIGH لِظُهور heads-up + صَوت
      notification: {
        sound: "default",
        channel_id: "m7_default", // مُطابِق لِلقَناة المُعَرَّفة في Flutter
        default_sound: true,
        default_vibrate_timings: true,
        notification_priority: "PRIORITY_MAX",
        visibility: "PUBLIC",
      },
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
          "content-available": 1,
        },
      },
      headers: {
        "apns-priority": isHigh ? "10" : "5",
      },
    },
  };

  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
  const resp = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ message }),
  });

  if (resp.ok) {
    return { ok: true, invalidToken: false };
  }

  const errBody = await resp.text();
  const invalid =
    resp.status === 404 ||
    errBody.includes("UNREGISTERED") ||
    errBody.includes("registration-token-not-registered") ||
    errBody.includes("INVALID_ARGUMENT");

  return {
    ok: false,
    invalidToken: invalid,
    error: `${resp.status}: ${errBody.slice(0, 200)}`,
  };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supaUrl = Deno.env.get("SUPABASE_URL");
    const supaKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const saJson = Deno.env.get("FCM_SERVICE_ACCOUNT");

    if (!supaUrl || !supaKey) {
      return new Response(
        JSON.stringify({ error: "Supabase env vars missing" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
    if (!saJson) {
      return new Response(
        JSON.stringify({ error: "FCM_SERVICE_ACCOUNT env var is not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    let sa: ServiceAccount;
    try {
      sa = JSON.parse(saJson);
      if (!sa.client_email || !sa.private_key || !sa.project_id) {
        throw new Error("Missing required fields in service account JSON");
      }
    } catch (e) {
      return new Response(
        JSON.stringify({ error: `Invalid FCM_SERVICE_ACCOUNT JSON: ${e}` }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const payload = (await req.json()) as PushPayload;
    if (!payload.user_id || !payload.title) {
      return new Response(
        JSON.stringify({ error: "user_id and title are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const supabase = createClient(supaUrl, supaKey);

    const { data: tokens, error: tokensErr } = await supabase
      .from("device_tokens")
      .select("token, platform")
      .eq("user_id", payload.user_id)
      .eq("is_active", true);

    if (tokensErr) {
      return new Response(
        JSON.stringify({ error: `DB error: ${tokensErr.message}` }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const list = (tokens ?? []) as DeviceToken[];
    const result: FcmResult = {
      total: list.length,
      sent: 0,
      failed: 0,
      invalid_tokens_removed: 0,
      errors: [],
    };

    if (list.length === 0) {
      return new Response(JSON.stringify(result), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const accessToken = await getAccessToken(sa);

    const invalidTokens: string[] = [];
    for (const dt of list) {
      try {
        const r = await sendToToken(accessToken, sa.project_id, dt.token, payload);
        if (r.ok) {
          result.sent++;
        } else {
          result.failed++;
          if (r.invalidToken) {
            invalidTokens.push(dt.token);
          }
          if (r.error) {
            result.errors!.push(r.error);
          }
        }
      } catch (e) {
        result.failed++;
        result.errors!.push(String(e));
      }
    }

    if (invalidTokens.length > 0) {
      await supabase
        .from("device_tokens")
        .update({ is_active: false })
        .in("token", invalidTokens);
      result.invalid_tokens_removed = invalidTokens.length;
    }

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(
      JSON.stringify({ error: `Unhandled: ${e}` }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
