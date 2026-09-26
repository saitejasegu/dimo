/// <reference types="vite/client" />
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { convexTest } from "convex-test";
import { makeFunctionReference } from "convex/server";
import schema from "./schema";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
const pushLends = makeFunctionReference<"mutation">("syncTyped:pushLends");
const pullLends = makeFunctionReference<"query">("syncTyped:pullLends");
const clearWorkspace = makeFunctionReference<"mutation">("syncTyped:clearWorkspace");
const findLendUser = makeFunctionReference<"query">("lending:findLendUser");
const sendLendInvite = makeFunctionReference<"mutation">("lending:sendLendInvite");
const cancelLendInvite = makeFunctionReference<"mutation">("lending:cancelLendInvite");
const acceptLendInvite = makeFunctionReference<"mutation">("lending:acceptLendInvite");
const listLendConnections = makeFunctionReference<"query">("lending:listLendConnections");
const revokeLendConnection = makeFunctionReference<"mutation">("lending:revokeLendConnection");
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

type Env = ReturnType<typeof setup>;
type Client = Env["alice"];

/** Stands in for `refreshVerifiedEmail`, which reads the address from WorkOS. */
async function verify(env: Env, identity: { tokenIdentifier: string }, email: string) {
  await env.t.run(async (ctx) => {
    await ctx.db.insert("accountEmails", {
      ownerId: identity.tokenIdentifier,
      email,
      verifiedAt: Date.now(),
    });
  });
}

async function findUser(client: Client, email: string) {
  return (await client.query(findLendUser, { email })) as {
    userId: string;
    name: string;
    email: string;
    relation: "none" | "self" | "connected" | "invited" | "invitedYou";
    contactId?: string;
  } | null;
}

/** `from` finds `toEmail` and invites them; returns the invite id. */
async function invite(
  from: Client,
  toEmail: string,
  fields: { contactName?: string; contactId?: string } = {},
) {
  const user = await findUser(from, toEmail);
  if (!user) throw new Error(`No user for ${toEmail}`);
  const { inviteId } = await from.mutation(sendLendInvite, {
    userId: user.userId,
    contactName: fields.contactName ?? "Bobby",
    ...(fields.contactId ? { contactId: fields.contactId } : {}),
  });
  return inviteId as string;
}

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
  env: Env,
  options: {
    inviterContactId?: string;
    accepterContactId?: string;
    history?: "both" | "inviter" | "accepter";
  } = {},
) {
  await verify(env, BOB, "bob@example.com");
  const inviteId = await invite(env.alice, "bob@example.com", {
    contactId: options.inviterContactId,
  });
  const accepted = await env.bob.mutation(acceptLendInvite, {
    inviteId,
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

  it("finds accounts only by their exact verified email", async () => {
    const env = setup();
    await verify(env, ALICE, "alice@example.com");
    await verify(env, BOB, "bob@example.com");
    expect(await findUser(env.alice, "  BOB@example.com ")).toMatchObject({
      email: "bob@example.com",
      name: "bob",
      relation: "none",
    });
    expect(await findUser(env.alice, "bob@example")).toBeNull();
    expect(await findUser(env.alice, "nobody@example.com")).toBeNull();
    expect((await findUser(env.alice, "alice@example.com"))?.relation).toBe("self");
  });

  it("keeps entries private until the invite is accepted", async () => {
    const env = setup();
    await env.alice.mutation(pushLends, {
      workspaceId: "global",
      operations: [lendOp("alice-old", { contactId: "cn-bob", timestamp: 10 })],
    });
    await verify(env, BOB, "bob@example.com");
    const inviteId = await invite(env.alice, "bob@example.com", { contactId: "cn-bob" });
    await env.t.finishAllScheduledFunctions(vi.runAllTimers);

    expect(await byId(env.alice, "alice-old")).toMatchObject({ contactId: "cn-bob" });
    expect(await pull(env.bob)).toEqual([]);
    expect(await env.alice.query(listOutgoing, {})).toMatchObject([
      { inviteId, contactId: "cn-bob", contactName: "Bobby", inviteeEmail: "bob@example.com" },
    ]);
    expect(await env.bob.query(listIncoming, {})).toMatchObject([
      { inviteId, inviterName: "Alice" },
    ]);
    expect(await findUser(env.alice, "bob@example.com")).toMatchObject({
      relation: "invited",
      contactId: "cn-bob",
    });
  });

  it("only lets the invitee accept, once", async () => {
    const env = setup();
    await verify(env, ALICE, "alice@example.com");
    await verify(env, BOB, "bob@example.com");
    const inviteId = await invite(env.alice, "bob@example.com");

    await expect(
      env.alice.mutation(acceptLendInvite, { inviteId, history: "both" }),
    ).rejects.toThrow("not found");
    await expect(
      env.carol.mutation(acceptLendInvite, { inviteId, history: "both" }),
    ).rejects.toThrow("not found");

    const { contactId } = await env.bob.mutation(acceptLendInvite, { inviteId, history: "both" });
    await expect(
      env.bob.mutation(acceptLendInvite, { inviteId, history: "both" }),
    ).rejects.toThrow("no longer valid");
    expect(await env.bob.query(listIncoming, {})).toEqual([]);
    expect(await env.alice.query(listOutgoing, {})).toEqual([]);
    expect(await findUser(env.alice, "bob@example.com")).toMatchObject({
      relation: "connected",
      contactId,
    });
    await expect(invite(env.bob, "alice@example.com")).rejects.toThrow("already share a ledger");
  });

  it("rejects inviting yourself or someone who already invited you", async () => {
    const env = setup();
    await verify(env, ALICE, "alice@example.com");
    await verify(env, BOB, "bob@example.com");
    await expect(invite(env.alice, "alice@example.com")).rejects.toThrow("invite yourself");

    await invite(env.alice, "bob@example.com");
    expect((await findUser(env.bob, "alice@example.com"))?.relation).toBe("invitedYou");
    await expect(invite(env.bob, "alice@example.com")).rejects.toThrow("already invited you");
  });

  it("replaces an earlier invite to the same person", async () => {
    const env = setup();
    await verify(env, BOB, "bob@example.com");
    const first = await invite(env.alice, "bob@example.com", { contactName: "Bob" });
    const second = await invite(env.alice, "bob@example.com", { contactName: "Bobby" });
    expect(await env.bob.query(listIncoming, {})).toMatchObject([{ inviteId: second }]);
    await expect(
      env.bob.mutation(acceptLendInvite, { inviteId: first, history: "both" }),
    ).rejects.toThrow("no longer valid");
  });

  it("lets the inviter cancel and the invitee decline", async () => {
    const env = setup();
    await verify(env, BOB, "bob@example.com");
    await verify(env, CAROL, "carol@example.com");
    const toBob = await invite(env.alice, "bob@example.com");
    const toCarol = await invite(env.alice, "carol@example.com", { contactName: "Carol" });

    await expect(env.bob.mutation(cancelLendInvite, { inviteId: toBob })).rejects.toThrow(
      "not found",
    );
    await env.alice.mutation(cancelLendInvite, { inviteId: toBob });
    expect(await env.bob.query(listIncoming, {})).toEqual([]);

    await expect(env.bob.mutation(declineLendInvite, { inviteId: toCarol })).rejects.toThrow(
      "not found",
    );
    await env.carol.mutation(declineLendInvite, { inviteId: toCarol });
    expect(await env.alice.query(listOutgoing, {})).toEqual([]);
    await expect(
      env.carol.mutation(acceptLendInvite, { inviteId: toCarol, history: "both" }),
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

  describe("verified email", () => {
    const emails: Record<string, { email: string; email_verified: boolean }> = {
      user_alice: { email: "Alice@Example.com", email_verified: true },
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

    it("only makes verified addresses findable", async () => {
      const env = setup();
      expect(await env.alice.action(refreshVerifiedEmail, {})).toEqual({
        available: true,
        email: "alice@example.com",
      });
      expect(await env.carol.action(refreshVerifiedEmail, {})).toEqual({
        available: true,
        email: null,
      });
      expect(await findUser(env.bob, "alice@example.com")).toMatchObject({ name: "alice" });
      expect(await findUser(env.bob, "carol@example.com")).toBeNull();
    });
  });
});
