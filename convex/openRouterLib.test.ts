import { describe, expect, it } from "vitest";
import {
  buildChatCompletionPayload,
  filterFreeModels,
  isFreePricing,
  resolvedOutputTokenLimit,
  supportsStructuredOutputs,
} from "./openRouterLib";

describe("openRouterLib", () => {
  it("detects free pricing only when both sides are zero", () => {
    expect(isFreePricing({ prompt: "0", completion: "0" })).toBe(true);
    expect(isFreePricing({ prompt: "0.0", completion: "0" })).toBe(true);
    expect(isFreePricing({ prompt: "0", completion: "0.000001" })).toBe(false);
    expect(isFreePricing({ prompt: "0", completion: undefined })).toBe(false);
  });

  it("requires structured output parameters", () => {
    expect(
      supportsStructuredOutputs(["structured_outputs", "response_format"]),
    ).toBe(true);
    expect(supportsStructuredOutputs(["response_format"])).toBe(false);
  });

  it("filters catalog to free structured models and merges ZDR", () => {
    const models = filterFreeModels(
      [
        {
          id: "paid/structured",
          name: "Paid",
          context_length: 8192,
          pricing: { prompt: "0.000001", completion: "0.000002" },
          supported_parameters: ["structured_outputs", "response_format"],
        },
        {
          id: "free/structured",
          name: "Free Structured",
          context_length: 4096,
          pricing: { prompt: "0", completion: "0" },
          supported_parameters: ["structured_outputs", "response_format", "max_tokens"],
        },
        {
          id: "free/plain",
          name: "Free Plain",
          context_length: 4096,
          pricing: { prompt: "0", completion: "0" },
          supported_parameters: [],
        },
        {
          id: "free/zdr",
          name: "Free ZDR",
          context_length: 8192,
          pricing: { prompt: "0", completion: "0" },
          supported_parameters: [
            "structured_outputs",
            "response_format",
            "max_tokens",
            "temperature",
          ],
        },
      ],
      [
        {
          model_id: "free/zdr",
          supported_parameters: [
            "structured_outputs",
            "response_format",
            "max_tokens",
            "temperature",
          ],
        },
        {
          model_id: "paid/structured",
          supported_parameters: ["structured_outputs", "response_format"],
        },
      ],
    );

    expect(models.map((model) => model.id)).toEqual([
      "free/structured",
      "free/zdr",
    ]);
    expect(models[0]?.hasZDREndpoint).toBe(false);
    expect(models[1]?.hasZDREndpoint).toBe(true);
    expect(models[1]?.zdrSupportedParameters).toEqual([
      "max_tokens",
      "response_format",
      "structured_outputs",
      "temperature",
    ]);
  });

  it("rejects paid models from free analysis payloads", () => {
    const freeOnly = filterFreeModels(
      [
        {
          id: "paid/model",
          name: "Paid",
          pricing: { prompt: "1", completion: "1" },
          supported_parameters: ["structured_outputs", "response_format"],
        },
      ],
      [],
    );
    expect(freeOnly.find((model) => model.id === "paid/model")).toBeUndefined();
  });

  it("builds chat payloads with ZDR and token limits", () => {
    const payload = buildChatCompletionPayload({
      modelId: "free/zdr",
      prompt: "analyze this",
      privacyMode: "zdrOnly",
      outputTokenLimit: 512,
      supportedParameters: [
        "structured_outputs",
        "response_format",
        "max_tokens",
        "temperature",
        "reasoning",
      ],
      zdrSupportedParameters: [
        "structured_outputs",
        "response_format",
        "max_tokens",
        "temperature",
        "reasoning",
      ],
    });

    expect(payload.model).toBe("free/zdr");
    expect(payload.provider).toEqual({
      require_parameters: true,
      zdr: true,
    });
    expect(payload.max_tokens).toBe(
      resolvedOutputTokenLimit(512, "free/zdr", true),
    );
    expect(payload.temperature).toBe(0);
    expect(payload.reasoning).toEqual({ effort: "low", exclude: true });
  });
});
