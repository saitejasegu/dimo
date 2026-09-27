import { describe, expect, it } from "vitest";
import { splitShares } from "@/features/transactions/split";

const people = (...values: number[]) =>
  values.map((value, index) => ({ contactId: `c${index}`, value }));

const total = (shares: NonNullable<ReturnType<typeof splitShares>>) =>
  shares.mine + shares.others.reduce((sum, other) => sum + other.share, 0);

describe("splitShares", () => {
  it("splits equally and gives leftover minor units to the user first", () => {
    expect(splitShares(90_000, "equal", people(0))).toEqual({
      mine: 45_000,
      others: [{ contactId: "c0", share: 45_000 }],
    });
    const uneven = splitShares(101, "equal", people(0, 0));
    expect(uneven).toEqual({
      mine: 34,
      others: [
        { contactId: "c0", share: 34 },
        { contactId: "c1", share: 33 },
      ],
    });
    expect(total(uneven!)).toBe(101);
  });

  it("leaves the remainder of exact amounts to the user", () => {
    expect(splitShares(1_000, "exact", people(300, 200))).toEqual({
      mine: 500,
      others: [
        { contactId: "c0", share: 300 },
        { contactId: "c1", share: 200 },
      ],
    });
    expect(splitShares(1_000, "exact", people(1_000))?.mine).toBe(0);
    expect(splitShares(1_000, "exact", people(600, 401))).toBeNull();
  });

  it("rounds percentages down so shares still add up", () => {
    const shares = splitShares(1_001, "percent", people(33.33, 33.33));
    expect(shares?.others.map((other) => other.share)).toEqual([333, 333]);
    expect(total(shares!)).toBe(1_001);
    expect(splitShares(1_000, "percent", people(60, 50))).toBeNull();
  });

  it("rejects an empty split, a zero total or negative values", () => {
    expect(splitShares(1_000, "equal", [])).toBeNull();
    expect(splitShares(0, "equal", people(0))).toBeNull();
    expect(splitShares(1_000, "exact", people(-1))).toBeNull();
    expect(splitShares(1_000, "percent", people(Number.NaN))).toBeNull();
  });
});
