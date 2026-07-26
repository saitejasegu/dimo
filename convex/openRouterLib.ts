/** Pure OpenRouter helpers shared by actions and unit tests. */

export type OpenRouterPricing = {
  prompt?: string | null;
  completion?: string | null;
};

export type OpenRouterCatalogModel = {
  id: string;
  name: string;
  context_length?: number | null;
  pricing?: OpenRouterPricing | null;
  supported_parameters?: string[] | null;
};

export type OpenRouterZDREndpoint = {
  model_id: string;
  supported_parameters?: string[] | null;
};

export type OpenRouterFreeModel = {
  id: string;
  name: string;
  contextLength: number;
  pricing: { prompt: string | null; completion: string | null };
  supportedParameters: string[];
  hasZDREndpoint: boolean;
  zdrSupportedParameters: string[];
};

export const HOURLY_ANALYSIS_LIMIT = 60;
export const HOUR_MS = 60 * 60 * 1000;

export const STANDARD_OUTPUT_TOKEN_LIMIT = 512;
export const INCOMPLETE_OUTPUT_RETRY_TOKEN_LIMIT = 2048;

export function pricePerToken(value: string | null | undefined): number | null {
  if (value == null || value === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

export function isFreePricing(pricing: OpenRouterPricing | null | undefined): boolean {
  return (
    pricePerToken(pricing?.prompt) === 0 && pricePerToken(pricing?.completion) === 0
  );
}

export function supportsStructuredOutputs(
  parameters: string[] | null | undefined,
): boolean {
  const set = new Set(parameters ?? []);
  return set.has("structured_outputs") && set.has("response_format");
}

export function isGoogleGeminiModel(modelId: string): boolean {
  return modelId.toLowerCase().startsWith("google/gemini");
}

export function resolvedOutputTokenLimit(
  requested: number,
  modelId: string,
  usesReasoning: boolean,
): number {
  if (!usesReasoning) return requested;
  if (isGoogleGeminiModel(modelId)) {
    return Math.max(requested, 4096);
  }
  return Math.max(requested, INCOMPLETE_OUTPUT_RETRY_TOKEN_LIMIT);
}

export function filterFreeModels(
  catalog: OpenRouterCatalogModel[],
  zdrEndpoints: OpenRouterZDREndpoint[],
): OpenRouterFreeModel[] {
  const byModel = new Map<string, OpenRouterZDREndpoint[]>();
  for (const endpoint of zdrEndpoints) {
    const list = byModel.get(endpoint.model_id) ?? [];
    list.push(endpoint);
    byModel.set(endpoint.model_id, list);
  }

  const models: OpenRouterFreeModel[] = [];
  for (const model of catalog) {
    if (!model.id || !model.name) continue;
    if (!isFreePricing(model.pricing)) continue;
    if (!supportsStructuredOutputs(model.supported_parameters)) continue;

    const compatible = (byModel.get(model.id) ?? []).filter((endpoint) =>
      supportsStructuredOutputs(endpoint.supported_parameters),
    );
    let zdrSupportedParameters: string[] = [];
    if (compatible.length > 0) {
      const first = new Set(compatible[0]?.supported_parameters ?? []);
      for (const endpoint of compatible.slice(1)) {
        const params = new Set(endpoint.supported_parameters ?? []);
        for (const value of [...first]) {
          if (!params.has(value)) first.delete(value);
        }
      }
      zdrSupportedParameters = [...first].sort();
    }

    models.push({
      id: model.id,
      name: model.name,
      contextLength:
        typeof model.context_length === "number" && model.context_length > 0
          ? model.context_length
          : 4096,
      pricing: {
        prompt: model.pricing?.prompt ?? null,
        completion: model.pricing?.completion ?? null,
      },
      supportedParameters: [...(model.supported_parameters ?? [])],
      hasZDREndpoint: compatible.length > 0,
      zdrSupportedParameters,
    });
  }

  return models.sort((a, b) =>
    a.name.localeCompare(b.name, undefined, { sensitivity: "base" }),
  );
}

export const emailAnalysisResponseFormat = {
  type: "json_schema",
  json_schema: {
    name: "email_analysis",
    strict: true,
    schema: {
      type: "object",
      additionalProperties: false,
      required: [
        "schemaVersion",
        "kind",
        "merchant",
        "amount",
        "currency",
        "occurredAt",
        "categoryId",
        "paymentMethodId",
        "paymentLastFour",
        "reference",
      ],
      properties: {
        schemaVersion: { type: "integer" },
        kind: {
          type: "string",
          enum: ["purchase", "debit", "refund", "irrelevant"],
        },
        merchant: { type: ["string", "null"] },
        amount: { type: ["string", "null"] },
        currency: { type: ["string", "null"] },
        occurredAt: { type: ["string", "null"] },
        categoryId: { type: ["string", "null"] },
        paymentMethodId: { type: ["string", "null"] },
        paymentLastFour: { type: ["string", "null"] },
        reference: { type: ["string", "null"] },
      },
    },
  },
} as const;

export function buildChatCompletionPayload(args: {
  modelId: string;
  prompt: string;
  privacyMode: "zdrOnly" | "allowNonZDR";
  outputTokenLimit: number;
  supportedParameters: string[];
  zdrSupportedParameters: string[];
}): Record<string, unknown> {
  const routeParameters = new Set(
    args.privacyMode === "zdrOnly"
      ? args.zdrSupportedParameters
      : args.supportedParameters,
  );
  const usesReasoning = routeParameters.has("reasoning");
  const resolvedLimit = resolvedOutputTokenLimit(
    args.outputTokenLimit,
    args.modelId,
    usesReasoning,
  );

  const provider: Record<string, unknown> = { require_parameters: true };
  if (args.privacyMode === "zdrOnly") provider.zdr = true;

  const payload: Record<string, unknown> = {
    model: args.modelId,
    messages: [{ role: "user", content: args.prompt }],
    stream: false,
    provider,
    response_format: emailAnalysisResponseFormat,
  };

  if (routeParameters.has("max_tokens")) {
    payload.max_tokens = resolvedLimit;
  } else if (routeParameters.has("max_completion_tokens")) {
    payload.max_completion_tokens = resolvedLimit;
  }
  if (routeParameters.has("temperature") && !isGoogleGeminiModel(args.modelId)) {
    payload.temperature = 0;
  }
  if (usesReasoning) {
    payload.reasoning = { effort: "low", exclude: true };
  }
  return payload;
}
