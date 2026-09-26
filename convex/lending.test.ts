/// <reference types="vite/client" />
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { convexTest } from "convex-test";
import { makeFunctionReference } from "convex/server";
import schema from "./schema";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
const pushLends = makeFunctionReference<"mutation">("syncTyped:pushLends");
const pullLends = makeFunctionReference<"query">("syncTyped:pullLends");
const clearWorkspace = makeFunctionReference<"mutation">("syncTyped:clearWorkspace");
const createLendInvite = makeFunctionReference<"mutation">("lending:createLendInvite");
const cancelLendInvite = makeFunctionReference<"mutation">("lending:cancelLendInvite");
const previewLendInvite = makeFunctionReference<"query">("lending:previewLendInvite");
const acceptLendInvite = makeFunctionReference<"mutation">("lending:acceptLendInvite");
const listLendConnections = makeFunctionReference<"query">("lending:listLendConnections");
const revokeLendConnection = makeFunctionReference<"mutation">("lending:revokeLendConnection");
const inviteByEmail = makeFunctionReference<"mutation">("lending:inviteLendContactByEmail");
const listIncoming = makeFunctionReference<"query">("lending:listIncomingLendInvites");
const listOutgoing = makeFunctionReference<"query">("lending:listOutgoingLendInvites");
const declineLendInvite = makeFunctionReference<"mutation">("lending:declineLendInvite");
const refreshVerifiedEmail = makeFunctionReference<"action">("lendingEmail:refreshVerifiedEmail");

const ALICE = { tokenIdentifier: "https://api.workos.com/|alice", subject: "user_alice", name: "Alice" };
const BOB = { tokenIdentifier: "https://api.workos.com/|bob", subject: "user_bob", name: "Bob" };
const CAROL = { tokenIdentifier: "https://api.workos.com/|carol", subject: "user_carol", name: "Carol" };

type LendKind = "lent" | "repaid" | "borrowed" | "returned";
type PulledLend = {
  entityId: string;
  contactName: string;
  contactId?: string;
  amountMinor: number;
  kind?: LendKind;
  deleted: boolean;
  currency?: string;
  connectionId?: string;
  createdBy?: "me" | "contact";
  lastEditedBy?: "me" | "contact";
  version: { timestamp: number; counter: number; deviceId: string };
};

function lendOp(
  entityId: string,
  fields: {
    contactId: string;
    contactName?: string;
    amountMinor?: number;
    kind?: LendKind;
    timestamp: number;
    deleted?: boolean;
    comment?: string;
    currency?: string;
  },
) {
  return {
    operationId: `${entityId}-${fields.timestamp}`,
    workspaceId: "global",
    entityId,
    version: { timestamp: fields.timestamp, counter: 0, deviceId: "device" },
    deleted: fields.deleted ?? false,
    contactName: fields.contactName ?? "Someone",
    contactId: fields.contactId,
    amountMinor: fields.amountMinor ?? 50_000,
    occurredAt: fields.timestamp,
    comment: fields.comment ?? "",
    kind: fields.kind ?? "lent",
    ...(fields.currency ? { currency: fields.currency } : {}),
  };
}

function setup() {
  const t = convexTest(schema, modules);
  return {
    t,
    alice: t.withIdentity(ALICE),
    bob: t.withIdentity(BOB),
    carol: t.withIdentity(CAROL),
  };
}

type Client = ReturnType<typeof setup>["alice"];

async function pull(client: Client): Promise<PulledLend[]> {
  const page = await client.query(pullLends, {
    workspaceId: "global",
    afterRevision: 0,
    limit: 200,
  });
  return page.entities as PulledLend[];
}

async function byId(client: Client, entityId: string) {
  return (await pull(client)).find((lend) => lend.entityId === entityId);
}

/** Alice invites Bob and Bob accepts; returns the shared contact id. */
async function connect(
  env: ReturnType<typeof setup>,
  options: {
    inviterContactId?: string;
    accepterContactId?: string;
    history?: "both" | "inviter" | "accepter";
  } = {},
) {
  const { code } = await env.alice.mutation(createLendInvite, {
    contactName: "Bobby",
    ...(options.inviterContactId ? { contactId: options.inviterContactId } : {}),
  });
  const accepted = await env.bob.mutation(acceptLendInvite, {
    code,
    history: options.history ?? "both",
    ...(options.accepterContactId ? { contactId: options.accepterContactId } : {}),
  });
  await env.t.finishAllScheduledFunctions(vi.runAllTimers);
  return accepted as { connectionId: string; contactId: string };
}

describe("collaborative lending", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it("mirrors a new shared entry into the other member's ledger, flipped", async () => {
    const env = setup();
    const { contactId, connectionId } = await connect(env);
    expect(contactId).toBe(`dimo:${connectionId}`);

    await env.alice.mutation(pushLends, {
      workspaceId: "global",
      operations: [lendOp("lend-1", { contactId, kind: "lent", timestamp: 100, currency: "INR" })],
    });

    const mine = await byId(env.alice, "lend-1");
    const theirs = await byId(env.bob, "lend-1");
    expect(mine).toMatchObject({
      kind: "lent",
      contactName: "Bobby",
      contactId,
      connectionId,
      createdBy: "me",
      lastEditedBy: "me",
      currency: "INR",
    });
    expect(theirs).toMatchObject({
      kind: "borrowed",
      contactName: "Alice",
      contactId,
      amountMinor: 50_000,
      createdBy: "contact",
      lastEditedBy: "contact",
      currency: "INR",
    });
    expect(theirs?.version).toEqual(mine?.version);
  });

  it("flips every direction between the two members", async () => {
    const env = setup();
    const { contactId } = await connect(env);
    const kinds: LendKind[] = ["lent", "repaid", "borrowed", "returned"];
    await env.alice.mutation(pushLends, {
      workspaceId: "global",
      operations: kinds.map((kind, index) =>
        lendOp(`lend-${kind}`, { contactId, kind, timestamp: 100 + index }),
      ),
    });
    const bobKinds = Object.fromEntries(
      (await pull(env.bob)).map((lend) => [lend.entityId, lend.kind]),
    );
    expect(bobKinds).toEqual({
      "lend-lent": "borrowed",
      "lend-repaid": "returned",
      "lend-borrowed": "lent",
      "lend-returned": "repaid",
    });
  });

  it("lets either member edit and keeps the newest version on both sides", async () => {
    const env = setup();
    const { contactId } = await connect(env);
    await env.alice.mutation(pushLends, {
      workspaceId: "global",
      operations: [lendOp("lend-1", { contactId, kind: "lent", timestamp: 100 })],
    });

    // Bob corrects the amount on his (borrowed) copy.
    const edit = await env.bob.mutation(pushLends, {
      workspaceId: "global",
      operations: [
        lendOp("lend-1", { contactId, kind: "borrowed", amountMinor: 40_000, timestamp: 200 }),
      ],
    });
    expect(edit.acknowledgements[0].applied).toBe(true);
    expect(await byId(env.alice, "lend-1")).toMatchObject({
      amountMinor: 40_000,
      kind: "lent",
      createdBy: "me",
      lastEditedBy: "contact",
    });

    // Alice's stale offline edit loses.
    const stale = await env.alice.mutation(pushLends, {
      workspaceId: "global",
      operations: [lendOp("lend-1", { contactId, amountMinor: 99_000, timestamp: 150 })],
    });
    expect(stale.acknowledgements[0].applied).toBe(false);
    expect((await byId(env.bob, "lend-1"))?.amountMinor).toBe(40_000);
  });

  it("propagates deletes as tombstones to both members", async () => {
    const env = setup();
    const { contactId } = await connect(env);
    await env.alice.mutation(pushLends, {
      workspaceId: "global",
      operations: [lendOp("lend-1", { contactId, timestamp: 100 })],
    });
    await env.bob.mutation(pushLends, {
      workspaceId: "global",
      operations: [lendOp("lend-1", { contactId, kind: "borrowed", timestamp: 200, deleted: true })],
    });
    expect((await byId(env.alice, "lend-1"))?.deleted).toBe(true);
    expect((await byId(env.bob, "lend-1"))?.deleted).toBe(true);
  });

  it("advances the other member's revision so their sync sees the change", async () => {
    const env = setup();
    const { contactId } = await connect(env);
    const before = await env.bob.query(pullLends, { workspaceId: "global", afterRevision: 0, limit: 10 });
    await env.alice.mutation(pushLends, {
      workspaceId: "global",
      operations: [lendOp("lend-1", { contactId, timestamp: 100 })],
    });
    const after = await env.bob.query(pullLends, {
      workspaceId: "global",
      afterRevision: before.latestRevision,
      limit: 10,
    });
    expect(after.latestRevision).toBeGreaterThan(before.latestRevision);
    expect(after.entities).toHaveLength(1);
  });

  it("rejects writes from accounts outside the connection", async () => {
    const env = setup();
    const { contactId } = await connect(env);
    await expect(
      env.carol.mutation(pushLends, {
        workspaceId: "global",
        operations: [lendOp("lend-1", { contactId, timestamp: 100 })],
      }),
    ).rejects.toThrow("Not a member of this lending connection");
    await expect(
      env.carol.mutation(pushLends, {
        workspaceId: "global",
        operations: [lendOp("lend-1", { contactId: "dimo:not-an-id", timestamp: 100 })],
      }),
    ).rejects.toThrow("Unknown lending connection");
  });

  it("never overwrites the other member's private entry with a colliding id", async () => {
    const env = setup();
    const { contactId } = await connect(env);
    await env.bob.mutation(pushLends, {
      workspaceId: "global",
      operations: [lendOp("bob-private", { contactId: "cn-dave", amountMinor: 1_000, timestamp: 100 })],
    });
    await expect(
      env.alice.mutation(pushLends, {
        workspaceId: "global",
        operations: [lendOp("bob-private", { contactId, timestamp: 200 })],
      }),
    ).rejects.toThrow("collides");
    expect(await byId(env.bob, "bob-private")).toMatchObject({
      contactId: "cn-dave",
      amountMinor: 1_000,
    });
  });

  it("keeps an entry shared when a stale client sends its old contact id", async () => {
    const env = setup();
    const { contactId } = await connect(env);
    await env.alice.mutation(pushLends, {
      workspaceId: "global",
      operations: [lendOp("lend-1", { contactId, timestamp: 100 })],
    });
    await env.alice.mutation(pushLends, {
      workspaceId: "global",
      operations: [lendOp("lend-1", { contactId: "cn-bob", amountMinor: 70_000, timestamp: 200 })],
    });
    expect(await byId(env.alice, "lend-1")).toMatchObject({ contactId, amountMinor: 70_000 });
    expect((await byId(env.bob, "lend-1"))?.amountMinor).toBe(70_000);
  });

  it("shares both members' past history when accepting with 'both'", async () => {
    const env = setup();
    await env.alice.mutation(pushLends, {
      workspaceId: "global",
      operations: [
        lendOp("alice-old", { contactId: "cn-bob", kind: "lent", amountMinor: 10_000, timestamp: 10 }),
        lendOp("alice-other", { contactId: "cn-dave", timestamp: 11 }),
      ],
    });
    await env.bob.mutation(pushLends, {
      workspaceId: "global",
      operations: [
        lendOp("bob-old", { contactId: "cn-alice", kind: "lent", amountMinor: 3_000, timestamp: 12 }),
      ],
    });

    const { contactId } = await connect(env, {
      inviterContactId: "cn-bob",
      accepterContactId: "cn-alice",
      history: "both",
    });

    const alice = await pull(env.alice);
    const bob = await pull(env.bob);
    expect(alice.find((l) => l.entityId === "alice-old")).toMatchObject({ contactId, kind: "lent" });
    expect(alice.find((l) => l.entityId === "bob-old")).toMatchObject({ contactId, kind: "borrowed" });
    expect(alice.find((l) => l.entityId === "alice-other")?.contactId).toBe("cn-dave");
    expect(bob.find((l) => l.entityId === "alice-old")).toMatchObject({
      contactId,
      kind: "borrowed",
      createdBy: "contact",
    });
    expect(bob.find((l) => l.entityId === "bob-old")).toMatchObject({ contactId, kind: "lent" });
  });

  it("deletes the accepter's duplicate history when the inviter's is chosen", async () => {
    const env = setup();
    await env.alice.mutation(pushLends, {
      workspaceId: "global",
      operations: [lendOp("alice-old", { contactId: "cn-bob", timestamp: 10 })],
    });
    await env.bob.mutation(pushLends, {
      workspaceId: "global",
      operations: [lendOp("bob-dup", { contactId: "cn-alice", kind: "borrowed", timestamp: 11 })],
    });

    const { contactId } = await connect(env, {
      inviterContactId: "cn-bob",
      accepterContactId: "cn-alice",
      history: "inviter",
    });

    expect((await byId(env.bob, "bob-dup"))?.deleted).toBe(true);
    expect(await byId(env.bob, "alice-old")).toMatchObject({ contactId, kind: "borrowed" });
    expect(await byId(env.alice, "bob-dup")).toBeUndefined();
  });

  it("links history in batches larger than one mutation", async () => {
    const env = setup();
    for (let batch = 0; batch < 3; batch += 1) {
      await env.alice.mutation(pushLends, {
        workspaceId: "global",
        operations: Array.from({ length: 50 }, (_, index) =>
          lendOp(`old-${batch}-${index}`, { contactId: "cn-bob", timestamp: batch * 100 + index + 1 }),
        ),
      });
    }
    const { contactId } = await connect(env, { inviterContactId: "cn-bob" });
    const bob = await pull(env.bob);
    expect(bob).toHaveLength(150);
    expect(bob.every((lend) => lend.contactId === contactId && lend.kind === "borrowed")).toBe(true);
  });

  it("validates invites", async () => {
    const env = setup();
    const { code } = await env.alice.mutation(createLendInvite, { contactName: "Bobby" });
    expect(code).toMatch(/^[A-Z2-9]{10}$/);

    await expect(
      env.alice.mutation(acceptLendInvite, { code, history: "both" }),
    ).rejects.toThrow("your own invite");
    expect(await env.bob.query(previewLendInvite, { code: code.toLowerCase() })).toMatchObject({
      inviterName: "Alice",
      status: "pending",
      isOwnInvite: false,
    });

    await env.bob.mutation(acceptLendInvite, { code, history: "both" });
    await expect(
      env.carol.mutation(acceptLendInvite, { code, history: "both" }),
    ).rejects.toThrow("no longer valid");

    const second = await env.alice.mutation(createLendInvite, { contactName: "Bob again" });
    await expect(
      env.bob.mutation(acceptLendInvite, { code: second.code, history: "both" }),
    ).rejects.toThrow("already share a ledger");

    const cancelled = await env.alice.mutation(createLendInvite, { contactName: "Carol" });
    await env.alice.mutation(cancelLendInvite, { code: cancelled.code });
    await expect(
      env.carol.mutation(acceptLendInvite, { code: cancelled.code, history: "both" }),
    ).rejects.toThrow("no longer valid");

    const expiring = await env.alice.mutation(createLendInvite, { contactName: "Carol" });
    vi.setSystemTime(Date.now() + 8 * 24 * 60 * 60 * 1000);
    await expect(
      env.carol.mutation(acceptLendInvite, { code: expiring.code, history: "both" }),
    ).rejects.toThrow("no longer valid");
  });

  it("lists connections with each member's own name for the other", async () => {
    const env = setup();
    const { connectionId } = await connect(env);
    expect(await env.alice.query(listLendConnections, {})).toMatchObject([
      { connectionId, contactName: "Bobby", status: "active" },
    ]);
    expect(await env.bob.query(listLendConnections, {})).toMatchObject([
      { connectionId, contactName: "Alice", status: "active" },
    ]);
    expect(await env.carol.query(listLendConnections, {})).toEqual([]);
  });

  it("stops mirroring after revoke but keeps each member's history", async () => {
    const env = setup();
    const { contactId, connectionId } = await connect(env);
    await env.alice.mutation(pushLends, {
      workspaceId: "global",
      operations: [lendOp("lend-1", { contactId, timestamp: 100 })],
    });
    await env.bob.mutation(revokeLendConnection, { connectionId });
    await env.t.finishAllScheduledFunctions(vi.runAllTimers);

    await env.alice.mutation(pushLends, {
      workspaceId: "global",
      operations: [
        lendOp("lend-1", { contactId, amountMinor: 1_000, timestamp: 200 }),
        lendOp("lend-2", { contactId, timestamp: 201 }),
      ],
    });
    expect(await byId(env.alice, "lend-1")).toMatchObject({
      amountMinor: 1_000,
      connectionId,
      createdBy: "me",
    });
    expect((await byId(env.bob, "lend-1"))?.amountMinor).toBe(50_000);
    expect(await byId(env.bob, "lend-2")).toBeUndefined();
    expect((await env.alice.query(listLendConnections, {}))[0].status).toBe("revoked");
  });

  it("keeps shared entries through a full cloud replacement", async () => {
    const env = setup();
    const { contactId } = await connect(env);
    await env.alice.mutation(pushLends, {
      workspaceId: "global",
      operations: [
        lendOp("shared", { contactId, timestamp: 100 }),
        lendOp("private", { contactId: "cn-dave", timestamp: 101 }),
      ],
    });
    // Bob edits, so Alice's local copy is now older than the shared version.
    await env.bob.mutation(pushLends, {
      workspaceId: "global",
      operations: [lendOp("shared", { contactId, kind: "borrowed", amountMinor: 1_000, timestamp: 200 })],
    });

    await env.alice.mutation(clearWorkspace, { workspaceId: "global", entityTypes: ["lend"] });
    // Re-upload from Alice's stale local database.
    await env.alice.mutation(pushLends, {
      workspaceId: "global",
      operations: [
        lendOp("shared", { contactId, timestamp: 100 }),
        lendOp("private", { contactId: "cn-dave", timestamp: 101 }),
      ],
    });

    expect(await byId(env.alice, "shared")).toMatchObject({ amountMinor: 1_000, deleted: false });
    expect(await byId(env.alice, "private")).toMatchObject({ contactId: "cn-dave" });
    expect((await byId(env.bob, "shared"))?.amountMinor).toBe(1_000);
  });

  it("removes shared entries and revokes connections on account deletion", async () => {
    const env = setup();
    const { contactId } = await connect(env);
    await env.alice.mutation(pushLends, {
      workspaceId: "global",
      operations: [lendOp("shared", { contactId, timestamp: 100 })],
    });
    await env.alice.mutation(clearWorkspace, {
      workspaceId: "global",
      entityTypes: ["lend"],
      includeSharedLends: true,
    });
    await env.t.finishAllScheduledFunctions(vi.runAllTimers);

    expect(await pull(env.alice)).toEqual([]);
    expect(await byId(env.bob, "shared")).toMatchObject({ deleted: false, kind: "borrowed" });
    expect((await env.bob.query(listLendConnections, {}))[0].status).toBe("revoked");
  });

  describe("email invites", () => {
    const emails: Record<string, { email: string; email_verified: boolean }> = {
      user_alice: { email: "Alice@Example.com", email_verified: true },
      user_bob: { email: "bob@example.com", email_verified: true },
      user_carol: { email: "carol@example.com", email_verified: false },
    };

    beforeEach(() => {
      process.env.WORKOS_API_KEY = "sk_test";
      vi.stubGlobal(
        "fetch",
        vi.fn(async (url: string, init?: { headers?: Record<string, string> }) => {
          expect(init?.headers?.Authorization).toBe("Bearer sk_test");
          const id = decodeURIComponent(url.split("/").pop() ?? "");
          const user = emails[id];
          return new Response(JSON.stringify(user ?? {}), { status: user ? 200 : 404 });
        }),
      );
    });
    afterEach(() => {
      delete process.env.WORKOS_API_KEY;
      vi.unstubAllGlobals();
    });

    it("reports unavailable without a WorkOS API key", async () => {
      delete process.env.WORKOS_API_KEY;
      const env = setup();
      expect(await env.alice.action(refreshVerifiedEmail, {})).toEqual({
        available: false,
        email: null,
      });
    });

    it("only records verified addresses", async () => {
      const env = setup();
      expect(await env.alice.action(refreshVerifiedEmail, {})).toEqual({
        available: true,
        email: "alice@example.com",
      });
      expect(await env.carol.action(refreshVerifiedEmail, {})).toEqual({
        available: true,
        email: null,
      });
    });

    it("delivers an invite to the verified account and only it may accept", async () => {
      const env = setup();
      await env.alice.action(refreshVerifiedEmail, {});
      const { code } = await env.bob.mutation(inviteByEmail, {
        email: "  ALICE@example.com ",
        contactName: "Alice",
      });

      expect(await env.alice.query(listIncoming, {})).toMatchObject([
        { code, inviterName: "Bob" },
      ]);
      expect(await env.bob.query(listOutgoing, {})).toMatchObject([
        { code, contactName: "Alice" },
      ]);
      await expect(
        env.carol.mutation(acceptLendInvite, { code, history: "both" }),
      ).rejects.toThrow("sent to someone else");

      await env.alice.mutation(acceptLendInvite, { code, history: "both" });
      expect(await env.alice.query(listIncoming, {})).toEqual([]);
      expect(await env.bob.query(listOutgoing, {})).toEqual([]);
      expect(await env.bob.query(listLendConnections, {})).toMatchObject([
        { contactName: "Alice", status: "active" },
      ]);
    });

    it("answers the same for unknown addresses and lets the code be shared", async () => {
      const env = setup();
      const unknown = await env.bob.mutation(inviteByEmail, {
        email: "nobody@example.com",
        contactName: "Nobody",
      });
      expect(unknown.code).toMatch(/^[A-Z2-9]{10}$/);
      expect(await env.alice.query(listIncoming, {})).toEqual([]);
      await env.carol.mutation(acceptLendInvite, { code: unknown.code, history: "both" });
      await expect(
        env.bob.mutation(inviteByEmail, { email: "not-an-email", contactName: "X" }),
      ).rejects.toThrow("valid email");
    });

    it("lets the addressee decline", async () => {
      const env = setup();
      await env.alice.action(refreshVerifiedEmail, {});
      const { code } = await env.bob.mutation(inviteByEmail, {
        email: "alice@example.com",
        contactName: "Alice",
      });
      await expect(env.carol.mutation(declineLendInvite, { code })).rejects.toThrow("not found");
      await env.alice.mutation(declineLendInvite, { code });
      expect(await env.alice.query(listIncoming, {})).toEqual([]);
      await expect(
        env.alice.mutation(acceptLendInvite, { code, history: "both" }),
      ).rejects.toThrow("no longer valid");
    });
  });
});
