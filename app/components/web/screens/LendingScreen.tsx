"use client";

import { useMemo, useState } from "react";
import { money } from "@/lib/format";
import { formatTransactionDay } from "@/lib/dates";
import { cn } from "@/lib/cn";
import { useAppState } from "@/store/app-store";
import { useLendingSharing } from "@/store/lending-sharing";
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
import { Button } from "@/components/ui/Button";
import { Card, HeroCard } from "@/components/ui/Card";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { SegmentedControl } from "@/components/ui/SegmentedControl";
import { PageHeader, WebScreen } from "@/components/web/WebScreen";

type LendingSection = "summary" | "activity";

const SECTION_OPTIONS = [
  { value: "summary", label: "Summary" },
  { value: "activity", label: "Activity" },
] satisfies Array<{ value: LendingSection; label: string }>;

function EmptyState({
  title,
  description,
}: {
  title: string;
  description: string;
}) {
  return (
    <Card className="flex min-h-52 flex-col items-center justify-center px-6 text-center">
      <div className="mb-2 font-display text-lg font-semibold text-ink">{title}</div>
      <div className="max-w-sm text-[13px] leading-5 text-muted">{description}</div>
    </Card>
  );
}

export function LendingScreen() {
  const { lends, currency } = useAppState("lends", "currency");
  const sharing = useLendingSharing();
  const [section, setSection] = useState<LendingSection>("summary");
  const [editor, setEditor] = useState<LendEditorTarget | null>(null);
  const [stopSharing, setStopSharing] = useState<LendContactSummary | null>(null);
  const summaries = useMemo(() => lendContactSummaries(lends), [lends]);
  const totals = useMemo(() => lendingTotals(summaries), [summaries]);
  const dayGroups = useMemo(() => groupLendsByDay(lends), [lends]);

  return (
    <WebScreen>
      <PageHeader
        title="Lending"
        subtitle="Money lent and borrowed, shared with the people involved."
        align="center"
        action={
          <div className="flex items-center gap-2">
            <Button
              variant="secondary"
              size="sm"
              onClick={() => sharing.setDialog({ kind: "join", code: "" })}
            >
              Join ledger
            </Button>
            <Button
              variant="secondary"
              size="sm"
              onClick={() => sharing.setDialog({ kind: "invite", contactName: "" })}
            >
              Share a ledger
            </Button>
            <Button size="sm" onClick={() => setEditor({ mode: "new" })}>
              Add entry
            </Button>
          </div>
        }
      />

      {sharing.incomingInvites.map((invite) => (
        <Card
          key={invite.code}
          className="mb-4 flex items-center justify-between gap-4 border-green/50 px-5 py-4"
        >
          <div>
            <div className="text-sm font-semibold text-ink">
              {invite.inviterName} wants to share a lending ledger
            </div>
            <div className="mt-0.5 text-xs text-muted">
              You’ll both see and edit the same entries.
            </div>
          </div>
          <Button size="sm" onClick={() => sharing.setDialog({ kind: "join", code: invite.code })}>
            Review
          </Button>
        </Card>
      ))}

      <HeroCard className="mb-[22px] p-6">
        <div className="flex gap-10">
          <div>
            <div className="mb-2.5 text-[13px] text-side-muted">Owed to me</div>
            <div className="font-display text-4xl font-semibold">
              {money(totals.owedToMe, currency)}
            </div>
          </div>
          <div>
            <div className="mb-2.5 text-[13px] text-side-muted">I owe</div>
            <div className="font-display text-4xl font-semibold">
              {money(totals.iOwe, currency)}
            </div>
          </div>
        </div>
        <div className="mt-2 text-xs text-side-sub">
          {summaries.length === 0
            ? "No active balances"
            : `${summaries.length} active contact${summaries.length === 1 ? "" : "s"}`}
        </div>
      </HeroCard>

      <div className="mb-4 flex items-center justify-between">
        <SegmentedControl
          options={SECTION_OPTIONS}
          value={section}
          onChange={setSection}
          fill={false}
        />
        <div className="text-xs text-faint">
          {lends.length} {lends.length === 1 ? "entry" : "entries"}
        </div>
      </div>

      {section === "summary" ? (
        summaries.length > 0 ? (
          <Card className="overflow-hidden">
            {summaries.map((summary, index) => {
              const pending = !summary.shared && sharing.pendingInvite(summary.contactId);
              const connected = summary.shared && sharing.activeConnection(summary.contactId);
              return (
                <div
                  key={summary.contactId}
                  className={cn(
                    "flex items-center gap-3.5 px-5 py-4",
                    index > 0 && "border-t border-line-soft",
                  )}
                >
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
                    aria-label={
                      summary.direction === "owedToMe"
                        ? `Record amount got back from ${summary.contactName}`
                        : `Record amount paid back to ${summary.contactName}`
                    }
                    className="flex min-w-0 flex-1 items-center gap-3.5 text-left"
                  >
                    <Avatar
                      initial={summary.contactName.charAt(0).toUpperCase()}
                      size={42}
                      radius={13}
                      textClassName="text-[15px]"
                    />
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2">
                        <span className="truncate text-sm font-semibold text-ink">
                          {summary.contactName}
                        </span>
                        {summary.shared ? <Badge label="Shared" tone="green" /> : null}
                        {pending ? <Badge label="Invite sent" tone="muted" /> : null}
                      </div>
                      <div className="mt-0.5 truncate text-xs text-muted">
                        {summary.entryCount} {summary.entryCount === 1 ? "entry" : "entries"}
                        {" · "}last {formatTransactionDay(summary.lastOccurredAt).toLowerCase()}
                      </div>
                    </div>
                    <div className="text-right">
                      <div
                        className={cn(
                          "font-display text-base font-semibold",
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
                        className="shrink-0 rounded-lg px-2 py-1 text-xs text-muted hover:text-danger"
                      >
                        Stop sharing
                      </button>
                    ) : null
                  ) : (
                    <button
                      type="button"
                      onClick={() =>
                        sharing.setDialog({
                          kind: "invite",
                          contactId: summary.contactId,
                          contactName: summary.contactName,
                        })
                      }
                      className="shrink-0 rounded-lg px-2 py-1 text-xs font-medium text-green hover:bg-green-soft"
                    >
                      {pending ? "View invite" : "Share"}
                    </button>
                  )}
                </div>
              );
            })}
          </Card>
        ) : (
          <EmptyState
            title={lends.length === 0 ? "Nothing recorded yet" : "All settled"}
            description={
              lends.length === 0
                ? "Record money you lend or borrow, or share a ledger with someone so you both keep it up to date."
                : "Nothing outstanding either way. Past entries are still available in Activity."
            }
          />
        )
      ) : dayGroups.length > 0 ? (
        <div className="flex flex-col gap-4">
          {dayGroups.map((group) => (
            <Card key={group.label} className="overflow-hidden">
              <div className="flex items-center justify-between bg-canvas-deep/60 px-5 py-3">
                <div className="text-[11px] font-semibold uppercase tracking-[0.1em] text-muted">
                  {group.label}
                </div>
                <div className="text-xs text-faint">{money(group.netAmount, currency)} net</div>
              </div>
              {group.items.map((lend, index) => {
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
                    className={cn(
                      "flex w-full items-center gap-3.5 px-5 py-4 text-left hover:bg-canvas/60",
                      index > 0 && "border-t border-line-soft",
                    )}
                  >
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
                  </button>
                );
              })}
            </Card>
          ))}
        </div>
      ) : (
        <EmptyState
          title="No lending activity"
          description="Entries you or the people you share a ledger with record will appear here."
        />
      )}

      {editor ? (
        <LendEditorDialog variant="modal" target={editor} onClose={() => setEditor(null)} />
      ) : null}
      <LedgerSharingDialogs variant="modal" />
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
    </WebScreen>
  );
}
