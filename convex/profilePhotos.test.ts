/// <reference types="vite/client" />
import { afterEach, describe, expect, it, vi } from "vitest";
import { convexTest } from "convex-test";
import { makeFunctionReference } from "convex/server";
import schema from "./schema";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
const backfill = makeFunctionReference<"action">("profilePhotos:backfillProfilePhotos");

describe("profile photo backfill", () => {
  afterEach(() => {
    delete process.env.WORKOS_API_KEY;
    vi.unstubAllGlobals();
  });

  it("fills missing photos from WorkOS and skips unknown users and other hosts", async () => {
    process.env.WORKOS_API_KEY = "sk_test";
    const pictures: Record<string, string> = {
      user_a: "https://workoscdn.com/images/v1/a",
      user_b: "https://tracker.example/b.png",
    };
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string) => {
        const id = decodeURIComponent(url.split("/").pop() ?? "");
        return id in pictures
          ? new Response(JSON.stringify({ profile_picture_url: pictures[id] }), { status: 200 })
          : new Response("{}", { status: 404 });
      }),
    );
    const t = convexTest(schema, modules);
    const ids = await t.run(async (ctx) => {
      const make = (subject: string, photoUrl?: string) =>
        ctx.db.insert("workspaces", {
          ownerId: `https://api.workos.com/|${subject}`,
          workspaceId: "global",
          revision: 0,
          ...(photoUrl ? { photoUrl } : {}),
        });
      return {
        a: await make("user_a"),
        b: await make("user_b"),
        c: await make("user_c"),
        kept: await make("user_a", "https://workoscdn.com/images/v1/kept"),
      };
    });

    expect(await t.action(backfill, {})).toEqual({ checked: 3, updated: 1, done: true });
    const photos = await t.run(async (ctx) =>
      Promise.all(Object.values(ids).map(async (id) => (await ctx.db.get(id))?.photoUrl ?? null)),
    );
    expect(photos).toEqual([
      "https://workoscdn.com/images/v1/a",
      null,
      null,
      "https://workoscdn.com/images/v1/kept",
    ]);
  });
});
