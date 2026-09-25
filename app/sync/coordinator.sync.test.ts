import "fake-indexeddb/auto";
import { afterAll, beforeEach, describe, expect, it, vi } from "vitest";
import { getFunctionName, type FunctionReference } from "convex/server";
import type { ConvexReactClient } from "convex/react";
import { db } from "@/data/db";
import { getStoredRow, initializeLocalDatabase, saveEntity } from "@/data/repository";
import { SyncCoordinator } from "@/sync/coordinator";

/** In-memory stand-in for Convex that records every round-trip by function name. */
function fakeServer(initialRevision: number) {
  let revision = initialRevision;
  const calls: string[] = [];
  const client = {
    query: async (ref: FunctionReference<"query">) => {
      calls.push(getFunctionName(ref));
      return { entities: [], latestRevision: revision, hasMore: false };
    },
    mutation: async (
      ref: FunctionReference<"mutation">,
      args: { operations?: Array<{ operationId: string }> },
    ) => {
      const name = getFunctionName(ref);
      calls.push(name);
      if (!name.startsWith("syncTyped:push")) return {};
      const acknowledgements = (args.operations ?? []).map((op) => ({
        operationId: op.operationId,
        applied: true,
        revision: ++revision,
      }));
      return { acknowledgements, latestRevision: revision };
    },
  };
  return {
    client: client as unknown as ConvexReactClient,
    calls,
    /** Another device writes, moving the workspace revision. */
    bump: () => ++revision,
    get revision() {
      return revision;
    },
  };
}

type Internals = { remoteRevisionChanged(revision: number): void };

describe("SyncCoordinator round-trips", () => {
  beforeEach(async () => {
    vi.stubGlobal("navigator", { onLine: true });
    db.close();
    await db.delete();
    await initializeLocalDatabase();
  });
  afterAll(() => {
    vi.unstubAllGlobals();
    db.close();
  });

  it("pulls every web type once, then pushes defaults without pulling them back", async () => {
    const server = fakeServer(5);
    const coordinator = new SyncCoordinator(server.client);
    await coordinator.request();

    const pulls = server.calls.filter((name) => name.startsWith("syncTyped:pull"));
    expect(pulls).toHaveLength(6);
    expect(pulls).not.toContain("syncTyped:pullEmailMessages");
    expect(server.calls.filter((name) => name === "syncTyped:ensureWorkspaceProfile")).toHaveLength(1);
    expect(server.calls.filter((name) => name.startsWith("syncTyped:push"))).toHaveLength(2);
    // Acks stamped the server revision, so defaults are not queued again.
    expect((await getStoredRow("paymentMethod", "payment-method-cash"))!.serverRevision).toBeGreaterThan(0);
    expect(await db.outbox.count()).toBe(0);
  });

  it("skips the network entirely when nothing changed", async () => {
    const server = fakeServer(5);
    const coordinator = new SyncCoordinator(server.client);
    await coordinator.request();
    (coordinator as unknown as Internals).remoteRevisionChanged(server.revision);
    server.calls.length = 0;

    await coordinator.request();
    expect(server.calls).toEqual([]);
  });

  it("pushes a local write without re-pulling, and pulls when another device writes", async () => {
    const server = fakeServer(5);
    const coordinator = new SyncCoordinator(server.client);
    await coordinator.request();
    (coordinator as unknown as Internals).remoteRevisionChanged(server.revision);
    server.calls.length = 0;

    await saveEntity("paymentMethod", {
      id: "pm-card",
      name: "Card",
      type: "Card",
      detail: "",
      archived: false,
    });
    await coordinator.request();
    expect(server.calls).toEqual(["syncTyped:pushPaymentMethods"]);

    server.calls.length = 0;
    (coordinator as unknown as Internals).remoteRevisionChanged(server.revision);
    await coordinator.request();
    expect(server.calls).toEqual([]);

    (coordinator as unknown as Internals).remoteRevisionChanged(server.bump());
    await coordinator.request();
    expect(server.calls.filter((name) => name.startsWith("syncTyped:pull"))).toHaveLength(6);
  });
});
