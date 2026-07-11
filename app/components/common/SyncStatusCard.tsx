"use client";

import { useAppActions, useSyncState } from "@/store/app-store";
import { Button } from "@/components/ui/Button";

export function SyncStatusCard() {
  const sync = useSyncState();
  const actions = useAppActions();
  const offline = sync.error === "Offline";
  const label = !sync.configured
    ? "Local only"
    : sync.syncing
      ? "Syncing"
      : offline
        ? "Offline"
        : sync.error
          ? "Error"
          : sync.pending > 0
            ? "Pending"
            : "Synced";
  const lastSync = sync.lastSyncedAt
    ? new Date(sync.lastSyncedAt).toLocaleString(undefined, {
        dateStyle: "medium",
        timeStyle: "short",
      })
    : "Not synced yet";

  return (
    <div>
      <div className="mb-3 flex items-start justify-between gap-4">
        <div>
          <h2 className="font-display text-base font-semibold text-ink">Cloud sync</h2>
          <p className="mt-1 text-xs text-muted">
            {sync.configured
              ? `${label} · ${sync.pending} pending${sync.blocked ? ` · ${sync.blocked} blocked` : ""}`
              : "Add NEXT_PUBLIC_CONVEX_URL to enable cloud sync."}
          </p>
          <p className="mt-1 text-[11px] text-faint">Last successful sync: {lastSync}</p>
        </div>
        <Button
          size="sm"
          variant="secondary"
          enabled={sync.configured && !sync.syncing}
          onClick={actions.syncNow}
        >
          {sync.syncing ? "Syncing…" : "Sync now"}
        </Button>
      </div>
      {sync.error && !offline ? (
        <p className="rounded-lg bg-danger-soft px-3 py-2 text-xs text-danger">
          {sync.error}
        </p>
      ) : null}
    </div>
  );
}
