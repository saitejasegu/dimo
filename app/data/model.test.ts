import { describe, expect, it } from "vitest";
import {
  ALL_CLOUD_ENTITY_TYPES,
  OWNED_ENTITY_TYPES,
} from "@/data/model";

describe("entity ownership", () => {
  it("keeps native-owned lend and emailMessage out of web Sync now replacement", () => {
    expect(OWNED_ENTITY_TYPES).not.toContain("lend");
    expect(OWNED_ENTITY_TYPES).not.toContain("emailMessage");
    expect(ALL_CLOUD_ENTITY_TYPES).toContain("lend");
    expect(ALL_CLOUD_ENTITY_TYPES).toContain("emailMessage");
  });
});
