import {
  actionGeneric,
  internalMutationGeneric,
} from "convex/server";
import { v } from "convex/values";
import { internal } from "./_generated/api";
import {
  HOUR_MS,
  HOURLY_ANALYSIS_LIMIT,
  STANDARD_OUTPUT_TOKEN_LIMIT,
  buildChatCompletionPayload,
  filterFreeModels,
  type OpenRouterCatalogModel,
  type OpenRouterFreeModel,
  type OpenRouterZDREndpoint,
} from "./openRouterLib";

/* eslint-disable @typescript-eslint/no-explicit-any */

type AuthIdentity = {
  tokenIdentifier: string;
};

const OPENROUTER_BASE = "https://openrouter.ai/api/v1";

const freeModelValidator = v.object({
  id: v.string(),
  name: v.string(),
  contextLength: v.number(),
  pricing: v.object({
    prompt: v.union(v.string(), v.null()),
    completion: v.union(v.string(), v.null()),
  }),
  supportedParameters: v.array(v.string()),
  hasZDREndpoint: v.boolean(),
  zdrSupportedParameters: v.array(v.string()),
});

async function requireIdentity(ctx: {
  auth: { getUserIdentity(): Promise<AuthIdentity | null> };
}) {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) throw new Error("Not authenticated");
  return identity;
}

function requireOpenRouterApiKey(): string {
  const key = process.env.OPENROUTER_API_KEY?.trim() ?? "";
  if (!key) {
    throw new Error(
      "Free OpenRouter models are unavailable. OPENROUTER_API_KEY is not configured.",
    );
  }
  return key;
}

async function openRouterFetch(
  path: string,
  apiKey: string,
  init?: RequestInit,
): Promise<Response> {
  const response = await fetch(`${OPENROUTER_BASE}/${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${apiKey}`,
      Accept: "application/json",
      "Content-Type": "application/json",
      "X-OpenRouter-Title": "Dimo",
      ...(init?.headers ?? {}),
    },
  });
  return response;
}

function openRouterErrorMessage(status: number, bodyText: string): string {
  try {
    const parsed = JSON.parse(bodyText) as {
      error?: { message?: string; metadata?: { raw?: unknown; provider_name?: string } };
    };
    const top = parsed.error?.message?.trim();
    const provider = parsed.error?.metadata?.provider_name?.trim();
    const raw = parsed.error?.metadata?.raw;
    let rawMessage = "";
    if (typeof raw === "string") {
      try {
        const nested = JSON.parse(raw) as { error?: { message?: string }; message?: string };
        rawMessage =
          nested.error?.message?.trim() || nested.message?.trim() || raw.trim();
      } catch {
        rawMessage = raw.trim();
      }
    }
    const parts = [
      provider ? `[${provider}]` : null,
      rawMessage && rawMessage !== top ? rawMessage : top,
    ].filter(Boolean);
    if (parts.length > 0) return parts.join(" ");
  } catch {
    // fall through
  }
  const trimmed = bodyText.trim();
  if (trimmed) return trimmed.slice(0, 500);
  return `OpenRouter request failed (HTTP ${status}).`;
}

async function loadFreeModels(apiKey: string): Promise<OpenRouterFreeModel[]> {
  const [catalogResponse, zdrResponse] = await Promise.all([
    openRouterFetch("models/user", apiKey),
    openRouterFetch("endpoints/zdr", apiKey),
  ]);
  if (!catalogResponse.ok) {
    throw new Error(
      openRouterErrorMessage(catalogResponse.status, await catalogResponse.text()),
    );
  }
  if (!zdrResponse.ok) {
    throw new Error(
      openRouterErrorMessage(zdrResponse.status, await zdrResponse.text()),
    );
  }
  const catalogJson = (await catalogResponse.json()) as {
    data?: OpenRouterCatalogModel[];
  };
  const zdrJson = (await zdrResponse.json()) as {
    data?: OpenRouterZDREndpoint[];
  };
  return filterFreeModels(catalogJson.data ?? [], zdrJson.data ?? []);
}

/** Consume one slot in the per-owner hourly analysis budget. */
export const consumeAnalysisSlot = internalMutationGeneric({
  args: {
    ownerId: v.string(),
    nowMs: v.number(),
  },
  returns: v.object({
    allowed: v.boolean(),
    requestCount: v.number(),
    retryAfterSeconds: v.union(v.number(), v.null()),
  }),
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("openRouterUsage")
      .withIndex("by_owner", (q: any) => q.eq("ownerId", args.ownerId))
      .unique();

    const windowExpired =
      !existing || args.nowMs - existing.windowStartMs >= HOUR_MS;

    if (!existing || windowExpired) {
      if (existing) {
        await ctx.db.patch(existing._id, {
          windowStartMs: args.nowMs,
          requestCount: 1,
        });
      } else {
        await ctx.db.insert("openRouterUsage", {
          ownerId: args.ownerId,
          windowStartMs: args.nowMs,
          requestCount: 1,
        });
      }
      return { allowed: true, requestCount: 1, retryAfterSeconds: null };
    }

    if (existing.requestCount >= HOURLY_ANALYSIS_LIMIT) {
      const retryAfterSeconds = Math.max(
        1,
        Math.ceil((existing.windowStartMs + HOUR_MS - args.nowMs) / 1000),
      );
      return {
        allowed: false,
        requestCount: existing.requestCount,
        retryAfterSeconds,
      };
    }

    const nextCount = existing.requestCount + 1;
    await ctx.db.patch(existing._id, { requestCount: nextCount });
    return { allowed: true, requestCount: nextCount, retryAfterSeconds: null };
  },
});

export const listFreeModels = actionGeneric({
  args: {},
  returns: v.array(freeModelValidator),
  handler: async (ctx): Promise<OpenRouterFreeModel[]> => {
    await requireIdentity(ctx);
    const apiKey = requireOpenRouterApiKey();
    return await loadFreeModels(apiKey);
  },
});

export const analyzeEmail = actionGeneric({
  args: {
    modelId: v.string(),
    privacyMode: v.union(v.literal("zdrOnly"), v.literal("allowNonZDR")),
    prompt: v.string(),
    outputTokenLimit: v.optional(v.number()),
  },
  returns: v.object({
    content: v.string(),
    modelId: v.string(),
    requestId: v.union(v.string(), v.null()),
  }),
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const apiKey = requireOpenRouterApiKey();

    if (!args.prompt.trim()) {
      throw new Error("Analysis prompt is empty.");
    }
    if (args.prompt.length > 200_000) {
      throw new Error("Analysis prompt is too large.");
    }

    const slot: {
      allowed: boolean;
      requestCount: number;
      retryAfterSeconds: number | null;
    } = await ctx.runMutation(internal.openRouter.consumeAnalysisSlot, {
      ownerId: identity.tokenIdentifier,
      nowMs: Date.now(),
    });
    if (!slot.allowed) {
      throw new Error(
        `Free OpenRouter analysis rate limit reached. Retry in ${slot.retryAfterSeconds ?? 60} seconds.`,
      );
    }

    const models = await loadFreeModels(apiKey);
    const model = models.find((entry) => entry.id === args.modelId);
    if (!model) {
      throw new Error(
        "The selected model is unavailable for free OpenRouter analysis.",
      );
    }
    if (args.privacyMode === "zdrOnly" && !model.hasZDREndpoint) {
      throw new Error(
        "The selected free model has no zero-data-retention route.",
      );
    }

    const payload = buildChatCompletionPayload({
      modelId: model.id,
      prompt: args.prompt,
      privacyMode: args.privacyMode,
      outputTokenLimit: args.outputTokenLimit ?? STANDARD_OUTPUT_TOKEN_LIMIT,
      supportedParameters: model.supportedParameters,
      zdrSupportedParameters: model.zdrSupportedParameters,
    });

    const response = await openRouterFetch("chat/completions", apiKey, {
      method: "POST",
      body: JSON.stringify(payload),
    });
    const bodyText = await response.text();
    if (!response.ok) {
      throw new Error(openRouterErrorMessage(response.status, bodyText));
    }

    let decoded: {
      id?: string;
      model?: string;
      choices?: Array<{
        message?: {
          content?: string | Array<{ type?: string; text?: string }>;
        };
      }>;
    };
    try {
      decoded = JSON.parse(bodyText) as typeof decoded;
    } catch {
      throw new Error("OpenRouter returned an invalid response.");
    }

    const choice = decoded.choices?.[0]?.message?.content;
    let content = "";
    if (typeof choice === "string") {
      content = choice;
    } else if (Array.isArray(choice)) {
      content = choice.map((part) => part.text ?? "").join("");
    }
    content = content.trim();
    if (!content) {
      throw new Error("OpenRouter returned an empty analysis response.");
    }

    const requestId =
      response.headers.get("x-request-id") ??
      response.headers.get("x-openrouter-request-id") ??
      decoded.id ??
      null;

    return {
      content,
      modelId: decoded.model ?? model.id,
      requestId,
    };
  },
});
