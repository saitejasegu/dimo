import { describe, expect, it } from "vitest";
import { isPermanentSyncError } from "@/sync/coordinator";

describe("isPermanentSyncError", () => {
  it("treats Convex argument validation as permanent", () => {
    expect(
      isPermanentSyncError(
        "ArgumentValidationError: Value does not match validator. Path: .operations[0].payload",
      ),
    ).toBe(true);
  });

  it("does not treat auth or transport errors as permanent", () => {
    expect(isPermanentSyncError("Not authenticated")).toBe(false);
    expect(isPermanentSyncError("JWT invalid signature")).toBe(false);
    expect(isPermanentSyncError("NetworkError: Failed to fetch")).toBe(false);
    expect(
      isPermanentSyncError("Could not find public function for 'syncTyped:clearWorkspace'"),
    ).toBe(false);
  });
});
