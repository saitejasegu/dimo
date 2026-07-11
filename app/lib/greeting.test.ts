import { describe, expect, it } from "vitest";
import { greetingFor } from "@/lib/greeting";

describe("greetingFor", () => {
  it.each([
    [0, "Good morning"],
    [11, "Good morning"],
    [12, "Good afternoon"],
    [16, "Good afternoon"],
    [17, "Good evening"],
    [23, "Good evening"],
  ])("returns the greeting for hour %i", (hour, expected) => {
    expect(greetingFor(new Date(2026, 0, 1, hour))).toBe(expected);
  });
});
