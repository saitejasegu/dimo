import { convexTest } from "convex-test";
import { describe, expect, it, vi, afterEach } from "vitest";
import { makeFunctionReference } from "convex/server";
import schema from "./schema";
import { workosUserIdFromIdentity } from "./accountDeletionLib";

const modules = import.meta.glob("./**/*.ts");

const deleteWorkOSUser = makeFunctionReference<"action">(
  "accountDeletion:deleteWorkOSUser",
);

describe("workosUserIdFromIdentity", () => {
  it("parses WorkOS user id from tokenIdentifier", () => {
    expect(
      workosUserIdFromIdentity({
        tokenIdentifier: "https://api.workos.com/|user_01ABC",
      }),
    ).toBe("user_01ABC");
    expect(
      workosUserIdFromIdentity({
        tokenIdentifier: "issuer-only",
        subject: "user_subject",
      }),
    ).toBe("user_subject");
  });
});

describe("deleteWorkOSUser", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    delete process.env.WORKOS_API_KEY;
  });

  it("returns identityDeleted false when WORKOS_API_KEY is unset", async () => {
    delete process.env.WORKOS_API_KEY;
    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|user-a",
    });
    const result = await t.action(deleteWorkOSUser, {});
    expect(result.identityDeleted).toBe(false);
    expect(result.reason).toMatch(/WORKOS_API_KEY/);
  });

  it("deletes the WorkOS user when the API key is configured", async () => {
    process.env.WORKOS_API_KEY = "sk_test";
    const fetchMock = vi.fn(async () => new Response(null, { status: 204 }));
    vi.stubGlobal("fetch", fetchMock);

    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|user_01ABC",
    });
    const result = await t.action(deleteWorkOSUser, {});
    expect(result).toEqual({ identityDeleted: true, reason: null });
    expect(fetchMock).toHaveBeenCalledWith(
      "https://api.workos.com/user_management/users/user_01ABC",
      expect.objectContaining({ method: "DELETE" }),
    );
  });
});
