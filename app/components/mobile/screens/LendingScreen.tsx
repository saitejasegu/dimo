"use client";

import { useMemo, useState } from "react";
import { cn } from "@/lib/cn";
import { formatTransactionDay } from "@/lib/dates";
import { money } from "@/lib/format";
import { useAppActions, useAppState } from "@/store/app-store";
import { useLendingSharing, type OutgoingLendInvite } from "@/store/lending-sharing";
import {
  groupLendsByDay,
  isIncomingLend,
  lendAttribution,
  lendContactSummaries,
  lendKindLabel,
  lendingTotals,
  signedLendAmount,
  type LendContactSummary,
} from "@/features/lending/selectors";
import type { LendEditorTarget } from "@/components/forms/LendEntryForm";
import { LedgerSharingDialogs, LendEditorDialog } from "@/components/common/LendingDialogs";
import { Avatar } from "@/components/ui/Avatar";
import { Badge } from "@/components/ui/Badge";
import { Card, HeroCard } from "@/components/ui/Card";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { PlusIcon } from "@/components/ui/icons";
import { SegmentedControl } from "@/components/ui/SegmentedControl";
import { MobileScreen, MobileTopBar } from "@/components/mobile/MobileScreen";

type LendingSection = "summary" | "activity";

const SECTIONS = [
  { value: "summary", label: "Summary" },
  { value: "activity", label: "Activity" },
] satisfies Array<{ value: LendingSection; label: string }>;

export function LendingScreen() {
  const { lends, currency } = useAppState("lends", "currency");
  const { showToast } = useAppActions();
  const sharing = useLendingSharing();
  const [section, setSection] = useState<LendingSection>("summary");
  const [editor, setEditor] = useState<LendEditorTarget | null>(null);
  const [stopSharing, setStopSharing] = useState<LendContactSummary | null>(null);
  const summaries = useMemo(() => lendContactSummaries(lends), [lends]);
  const totals = useMemo(() => lendingTotals(summaries), [summaries]);
  const groups = useMemo(() => groupLendsByDay(lends), [lends]);
  function cancelInvite(invite: OutgoingLendInvite) {
    sharing
      .cancel(invite.inviteId)
      .then(() => showToast("Invite cancelled"))
      .catch(() => showToast("Couldn’t cancel the invite"));
  }
  // Invites whose contact has no outstanding balance to show a row for.
  const invitedOnly = useMemo(
    () =>
      sharing.outgoingInvites.filter(
        (invite) => !summaries.some((summary) => summary.contactId === invite.contactId),
      ),
    [sharing.outgoingInvites, summaries],
  );

  return (
    <MobileScreen
      header={
        <>
          <MobileTopBar
            title="Lending"
            trailing={
              <button
                type="button"
                onClick={() => setEditor({ mode: "new" })}
                aria-label="Add lending entry"
                className="flex h-10 w-10 items-center justify-center rounded-[14px] bg-green text-on-green"
              >
                <PlusIcon size={18} />
              </button>
            }
          />
          <HeroCard className="mt-4 p-5">
            <div className="flex gap-6">
              <div className="min-w-0 flex-1">
                <div className="mb-2 text-[13px] text-side-muted">Owed to me</div>
                <div className="truncate font-display text-3xl font-semibold">
                  {money(totals.owedToMe, currency)}
                </div>
              </div>
              <div className="min-w-0 flex-1">
                <div className="mb-2 text-[13px] text-side-muted">I owe</div>
                <div className="truncate font-display text-3xl font-semibold">
                  {money(totals.iOwe, currency)}
                </div>
              </div>
            </div>
            <div className="mt-1.5 text-xs text-side-sub">
              {summaries.length === 0
                ? "No active balances"
                : `${summaries.length} contact${summaries.length === 1 ? "" : "s"} · ${lends.length} ${lends.length === 1 ? "entry" : "entries"}`}
            </div>
          </HeroCard>
          <SegmentedControl
            options={SECTIONS}
            value={section}
            onChange={setSection}
            className="mt-3"
          />
        </>
      }
    >
      {sharing.incomingInvites.map((invite) => (
        <div
          key={invite.inviteId}
          className="mb-2 rounded-2xl border border-green/50 bg-surface p-3"
        >
          <div className="truncate text-sm font-medium text-ink">
            {invite.inviterName} wants to share a ledger
          </div>
          {invite.inviterEmail ? (
            <div className="mt-0.5 truncate text-xs text-muted">{invite.inviterEmail}</div>
          ) : null}
          <div className="mt-2.5 flex gap-2">
            <button
              type="button"
              onClick={() => {
                sharing
                  .decline(invite.inviteId)
                  .then(() => showToast("Invite declined"))
                  .catch(() => showToast("Couldn’t decline the invite"));
              }}
              className="flex-1 rounded-full border border-line py-1.5 text-[13px] font-medium text-ink"
            >
              Decline
            </button>
            <button
              type="button"
              onClick={() => sharing.setDialog({ kind: "accept", invite })}
              className="flex-1 rounded-full bg-green py-1.5 text-[13px] font-medium text-on-green"
            >
              Accept
            </button>
          </div>
        </div>
      ))}
      {section === "summary"
        ? invitedOnly.map((invite) => (
            <Card key={invite.inviteId} className="mb-2 flex items-center gap-3 p-3">
              <Avatar
                initial={invite.contactName.charAt(0).toUpperCase()}
                size={40}
                radius={12}
                textClassName="text-sm"
              />
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-1.5">
                  <span className="truncate text-sm font-medium text-ink">
                    {invite.contactName}
                  </span>
                  <Badge label="Invited" tone="muted" />
                </div>
                <div className="mt-0.5 truncate text-xs text-muted">
                  {invite.inviteeEmail ?? "Waiting for them to accept"}
                </div>
              </div>
              <button
                type="button"
                onClick={() => cancelInvite(invite)}
                className="shrink-0 rounded-lg px-1.5 py-1 text-xs text-muted"
              >
                Cancel
              </button>
            </Card>
          ))
        : null}
      {section === "summary" ? (
        summaries.length > 0 ? (
          <div className="flex flex-col gap-2">
            {summaries.map((summary) => {
              const pending = !summary.shared && sharing.pendingInvite(summary.contactId);
              const connected = summary.shared && sharing.activeConnection(summary.contactId);
              return (
                <Card key={summary.contactId} className="flex items-center gap-2 p-3">
                  <button
                    type="button"
                    onClick={() =>
                      setEditor({
                        mode: "settle",
                        contactId: summary.contactId,
                        contactName: summary.contactName,
                        direction: summary.direction,
                      })
                    }
                    className="flex min-w-0 flex-1 items-center gap-3 text-left"
                  >
                    <Avatar
                      initial={summary.contactName.charAt(0).toUpperCase()}
                      size={40}
                      radius={12}
                      textClassName="text-sm"
                    />
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-1.5">
                        <span className="truncate text-sm font-medium text-ink">
                          {summary.contactName}
                        </span>
                        {summary.shared ? <Badge label="Shared" tone="green" /> : null}
                        {pending ? <Badge label="Invited" tone="muted" /> : null}
                      </div>
                      <div className="mt-0.5 truncate text-xs text-muted">
                        {summary.entryCount} {summary.entryCount === 1 ? "entry" : "entries"}
                        {" · "}last {formatTransactionDay(summary.lastOccurredAt).toLowerCase()}
                      </div>
                    </div>
                    <div className="text-right">
                      <div
                        className={cn(
                          "font-display text-[15px] font-semibold",
                          summary.direction === "owedToMe" ? "text-ink" : "text-danger",
                        )}
                      >
                        {money(summary.magnitude, summary.currency ?? currency)}
                      </div>
                      <div className="mt-0.5 text-[11px] text-faint">
                        {summary.direction === "owedToMe" ? "owes you" : "you owe"}
                      </div>
                    </div>
                  </button>
                  {summary.shared ? (
                    connected ? (
                      <button
                        type="button"
                        onClick={() => setStopSharing(summary)}
                        aria-label={`Stop sharing with ${summary.contactName}`}
                        className="shrink-0 px-1.5 text-lg leading-none text-faint"
                      >
                        ⋯
                      </button>
                    ) : null
                  ) : pending ? (
                    <button
                      type="button"
                      onClick={() => cancelInvite(pending)}
                      className="shrink-0 rounded-lg px-1.5 py-1 text-xs text-muted"
                    >
                      Cancel
                    </button>
                  ) : null}
                </Card>
              );
            })}
          </div>
        ) : (
          <div className="py-12 text-center">
            <div className="font-display text-base font-semibold text-ink">
              {lends.length === 0 ? "Nothing recorded yet" : "All settled"}
            </div>
            <div className="mx-auto mt-2 max-w-xs text-[13px] leading-5 text-muted">
              {lends.length === 0
                ? "Tap + to record money you lend or borrow. Enter someone’s Dimo email to keep the ledger together."
                : "Nothing outstanding either way. Past entries are available in Activity."}
            </div>
          </div>
        )
      ) : groups.length > 0 ? (
        <div className="flex flex-col gap-[18px]">
          {groups.map((group) => (
            <div key={group.label}>
              <div className="mb-2 flex items-baseline justify-between">
                <span className="text-xs font-medium uppercase tracking-[0.08em] text-muted">
                  {group.label}
                </span>
                <span className="text-xs text-faint">
                  {money(group.netAmount, currency)} net
                </span>
              </div>
              <div className="flex flex-col gap-2">
                {group.items.map((lend) => {
                  const incoming = isIncomingLend(lend.kind);
                  const detail = [
                    lend.comment.trim() || lendKindLabel(lend.kind),
                    lendAttribution(lend),
                    lend.time,
                  ]
                    .filter(Boolean)
                    .join(" · ");
                  return (
                    <button
                      type="button"
                      key={lend.id}
                      onClick={() => setEditor({ mode: "edit", lend })}
                      className="text-left"
                    >
                      <Card className="flex items-center gap-3 p-3">
                        <Avatar
                          initial={lend.contactName.charAt(0).toUpperCase()}
                          size={38}
                          radius={11}
                          textClassName="text-sm"
                        />
                        <div className="min-w-0 flex-1">
                          <div className="truncate text-sm font-medium text-ink">
                            {lend.contactName}
                          </div>
                          <div className="mt-0.5 truncate text-xs text-muted">{detail}</div>
                        </div>
                        <div
                          className={cn(
                            "font-display text-[15px] font-semibold",
                            incoming ? "text-green" : "text-ink",
                          )}
                        >
                          {money(signedLendAmount(lend), lend.currency ?? currency)}
                        </div>
                      </Card>
                    </button>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div className="py-12 text-center text-sm text-faint">
          No lending activity yet.
        </div>
      )}

      {editor ? (
        <LendEditorDialog variant="sheet" target={editor} onClose={() => setEditor(null)} />
      ) : null}
      <LedgerSharingDialogs variant="sheet" />
      <ConfirmDialog
        open={Boolean(stopSharing)}
        title={`Stop sharing with ${stopSharing?.contactName ?? ""}?`}
        message="You both keep the entries so far, but new changes won’t reach each other."
        confirmLabel="Stop sharing"
        onCancel={() => setStopSharing(null)}
        onConfirm={() => {
          const target = stopSharing;
          setStopSharing(null);
          if (target) void sharing.stopSharing(target.contactId);
        }}
      />
    </MobileScreen>
  );
}
