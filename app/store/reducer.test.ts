import { describe, expect, it } from "vitest";
import { DEFAULT_PREFERENCES } from "@/data/model";
import { reducer } from "@/store/reducer";
import { createInitialState, type HydratedData } from "@/store/state";

function hydratedData(defaultStatsRange: HydratedData["preferences"]["defaultStatsRange"]): HydratedData {
  return {
    transactions: [],
    recurring: [],
    lends: [],
    categories: [],
    limits: {},
    paymentMethods: [],
    preferences: { ...DEFAULT_PREFERENCES, defaultStatsRange },
    lastPaymentMethod: null,
  };
}

describe("store hydration", () => {
  it("applies a pulled stats default after bootstrap hydration", () => {
    const bootstrapped = reducer(createInitialState(), {
      type: "HYDRATE_DATA",
      data: hydratedData("1Y"),
    });

    const pulled = reducer(bootstrapped, {
      type: "HYDRATE_DATA",
      data: hydratedData("3M"),
    });

    expect(pulled.defaultStatsRange).toBe("3M");
    expect(pulled.statsRange).toBe("3M");
  });

  it("preserves a stats range the user selected during hydration", () => {
    const bootstrapped = reducer(createInitialState(), {
      type: "HYDRATE_DATA",
      data: hydratedData("1Y"),
    });
    const selected = reducer(bootstrapped, {
      type: "SET_STATS_RANGE",
      range: "6M",
    });

    const pulled = reducer(selected, {
      type: "HYDRATE_DATA",
      data: hydratedData("3M"),
    });

    expect(pulled.defaultStatsRange).toBe("3M");
    expect(pulled.statsRange).toBe("6M");
  });
});

describe("legacy navigation", () => {
  it("maps the retired recurring destination to home", () => {
    const state = reducer(createInitialState(), {
      type: "SET_VIEW",
      view: "recurring",
    });
    expect(state.view).toBe("home");
  });
});
