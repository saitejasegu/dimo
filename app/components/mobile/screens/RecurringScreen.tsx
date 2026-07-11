"use client";

import { money } from "@/lib/format";
import { useAppActions, useAppState } from "@/store/app-store";
import { useRecurring } from "@/features/recurring/hooks";
import { HeroCard } from "@/components/ui/Card";
import { RecurringRow } from "@/components/common/RecurringRow";
import { MobileScreen } from "@/components/mobile/MobileScreen";

export function RecurringScreen() {
  const { currency } = useAppState();
  const actions = useAppActions();
  const { all, total, subtitle } = useRecurring();

  return (
    <MobileScreen
      header={
        <>
          <div className="mb-4">
            <h1 className="font-display text-2xl font-semibold text-ink">
              Recurring
            </h1>
          </div>
          <HeroCard className="p-5">
            <div className="mb-2 text-[13px] text-side-muted">
              Monthly recurring total
            </div>
            <div className="mb-1.5 font-display text-3xl font-semibold">
              {money(total, currency)}
            </div>
            <div className="text-xs text-side-sub">{subtitle}</div>
          </HeroCard>
        </>
      }
    >
      <div className="flex flex-col gap-2">
        {all.map((rec) => (
          <RecurringRow
            key={rec.id}
            recurring={rec}
            currency={currency}
            onClick={() => actions.openEditRecurring(rec.id)}
          />
        ))}
      </div>
    </MobileScreen>
  );
}
