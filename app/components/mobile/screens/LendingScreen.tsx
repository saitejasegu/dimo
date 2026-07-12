"use client";

import { useMemo, useState } from "react";
import { cn } from "@/lib/cn";
import { formatTransactionDay } from "@/lib/dates";
import { money } from "@/lib/format";
import { useAppState } from "@/store/app-store";
import {
  groupLendsByDay,
  lendContactSummaries,
  lendingTotals,
  signedLendAmount,
} from "@/features/lending/selectors";
import { Avatar } from "@/components/ui/Avatar";
import { Badge } from "@/components/ui/Badge";
import { Card, HeroCard } from "@/components/ui/Card";
import { SegmentedControl } from "@/components/ui/SegmentedControl";
import { MobileScreen, MobileTopBar } from "@/components/mobile/MobileScreen";

type LendingSection = "summary" | "activity";

const SECTIONS = [
  { value: "summary", label: "Summary" },
  { value: "activity", label: "Activity" },
] satisfies Array<{ value: LendingSection; label: string }>;

export function LendingScreen() {
  const { lends, currency } = useAppState();
  const [section, setSection] = useState<LendingSection>("summary");
  const totals = useMemo(() => lendingTotals(lends), [lends]);
  const summaries = useMemo(() => lendContactSummaries(lends), [lends]);
  const groups = useMemo(() => groupLendsByDay(lends), [lends]);

  return (
    <MobileScreen
      header={
        <>
          <MobileTopBar
            title="Lending"
            trailing={<Badge label="Read only" tone="muted" />}
          />
          <HeroCard className="mt-4 p-5">
            <div className="mb-2 text-[13px] text-side-muted">Outstanding</div>
            <div className="font-display text-3xl font-semibold">
              {money(totals.outstanding, currency)}
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
            className="mt-3.5"
          />
        </>
      }
    >
      {section === "summary" ? (
        summaries.length > 0 ? (
          <div className="flex flex-col gap-2">
            {summaries.map((summary) => (
              <Card key={summary.contactId} className="flex items-center gap-3 p-3">
                <Avatar
                  initial={summary.contactName.charAt(0).toUpperCase()}
                  size={40}
                  radius={12}
                  textClassName="text-sm"
                />
                <div className="min-w-0 flex-1">
                  <div className="truncate text-sm font-medium text-ink">
                    {summary.contactName}
                  </div>
                  <div className="mt-0.5 truncate text-xs text-muted">
                    {summary.entryCount} {summary.entryCount === 1 ? "entry" : "entries"}
                    {" · "}last {formatTransactionDay(summary.lastOccurredAt).toLowerCase()}
                  </div>
                </div>
                <div className="font-display text-[15px] font-semibold text-ink">
                  {money(summary.outstanding, currency)}
                </div>
              </Card>
            ))}
          </div>
        ) : (
          <div className="py-12 text-center">
            <div className="font-display text-base font-semibold text-ink">
              {lends.length === 0 ? "Nothing lent yet" : "All settled"}
            </div>
            <div className="mx-auto mt-2 max-w-xs text-[13px] leading-5 text-muted">
              {lends.length === 0
                ? "Lending records added in the native app will appear here after syncing."
                : "Everyone has paid you back. Past entries are available in Activity."}
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
                  const repaid = lend.kind === "repaid";
                  const detail =
                    lend.comment.trim() || (repaid ? "Got back" : "Money lent");
                  return (
                    <Card key={lend.id} className="flex items-center gap-3 p-3">
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
                          repaid ? "text-green" : "text-ink",
                        )}
                      >
                        {money(signedLendAmount(lend), currency)}
                      </div>
                    </Card>
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
    </MobileScreen>
  );
}
