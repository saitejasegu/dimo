import { describe, expect, it } from "vitest";
import { EMPTY_PULLED_REVISIONS } from "@/data/db";
import { isPermanentSyncError, pullCursorFor } from "@/sync/coordinator";

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

describe("pullCursorFor", () => {
  it("resumes a type from its own recorded cursor", () => {
    const meta = {
      pulledRevisions: { ...EMPTY_PULLED_REVISIONS, lend: 12, transaction: 900 },
    };
    expect(pullCursorFor(meta, "lend")).toBe(12);
  });

  it("restarts a type whose cursor is missing instead of using the workspace maximum", () => {
    const meta = {
      pulledRevisions: { transaction: 900 } as (typeof EMPTY_PULLED_REVISIONS),
    };
    expect(pullCursorFor(meta, "lend")).toBe(0);
    expect(pullCursorFor(undefined, "lend")).toBe(0);
  });
});
