import { describe, expect, it } from "vitest";
import { compareVersions } from "@/data/model";

describe("logical versions", () => {
  it("orders by timestamp, counter, then device ID", () => {
    const base = { timestamp: 100, counter: 1, deviceId: "a" };
    expect(compareVersions({ ...base, timestamp: 101 }, base)).toBeGreaterThan(0);
    expect(compareVersions({ ...base, counter: 2 }, base)).toBeGreaterThan(0);
    expect(compareVersions({ ...base, deviceId: "b" }, base)).toBeGreaterThan(0);
    expect(compareVersions(base, { ...base })).toBe(0);
  });
});
