"use client";

import { useMemo, useState } from "react";
import { money } from "@/lib/format";
import { formatTransactionDay } from "@/lib/dates";
import { cn } from "@/lib/cn";
import { useAppState } from "@/store/app-store";
import {
  groupLendsByDay,
  isIncomingLend,
  lendContactSummaries,
  lendKindLabel,
  lendingTotals,
  signedLendAmount,
} from "@/features/lending/selectors";
import { Avatar } from "@/components/ui/Avatar";
import { Badge } from "@/components/ui/Badge";
import { Card, HeroCard } from "@/components/ui/Card";
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
  const { lends, currency } = useAppState();
  const [section, setSection] = useState<LendingSection>("summary");
  const summaries = useMemo(() => lendContactSummaries(lends), [lends]);
  const totals = useMemo(() => lendingTotals(summaries), [summaries]);
  const dayGroups = useMemo(() => groupLendsByDay(lends), [lends]);

  return (
    <WebScreen>
      <PageHeader
        title="Lending"
        subtitle="Money lent and borrowed, synced from your mobile app."
        align="center"
        action={<Badge label="Read only" tone="muted" className="px-3 py-1.5" />}
      />

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
            {summaries.map((summary, index) => (
              <div
                key={summary.contactId}
                className={cn(
                  "flex items-center gap-3.5 px-5 py-4",
                  index > 0 && "border-t border-line-soft",
                )}
              >
                <Avatar
                  initial={summary.contactName.charAt(0).toUpperCase()}
                  size={42}
                  radius={13}
                  textClassName="text-[15px]"
                />
                <div className="min-w-0 flex-1">
                  <div className="truncate text-sm font-semibold text-ink">
                    {summary.contactName}
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
                    {money(summary.magnitude, currency)}
                  </div>
                  <div className="mt-0.5 text-[11px] text-faint">
                    {summary.direction === "owedToMe" ? "owes you" : "you owe"}
                  </div>
                </div>
              </div>
            ))}
          </Card>
        ) : (
          <EmptyState
            title={lends.length === 0 ? "Nothing recorded yet" : "All settled"}
            description={
              lends.length === 0
                ? "Lending records added in the mobile app will appear here after syncing."
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
                const detail = lend.comment.trim() || lendKindLabel(lend.kind);
                return (
                  <div
                    key={lend.id}
                    className={cn(
                      "flex items-center gap-3.5 px-5 py-4",
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
                      <div className="mt-0.5 truncate text-xs text-muted">
                        {detail} · {lend.time}
                      </div>
                    </div>
                    <div
                      className={cn(
                        "font-display text-[15px] font-semibold",
                        incoming ? "text-green" : "text-ink",
                      )}
                    >
                      {money(signedLendAmount(lend), currency)}
                    </div>
                  </div>
                );
              })}
            </Card>
          ))}
        </div>
      ) : (
        <EmptyState
          title="No lending activity"
          description="Lending records added in the mobile app will appear here after syncing."
        />
      )}
    </WebScreen>
  );
}
