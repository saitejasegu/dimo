"use client";

import { money } from "@/lib/format";
import { useAppActions, useAppState } from "@/store/app-store";
import { useRecurring } from "@/features/recurring/hooks";
import { HeroCard } from "@/components/ui/Card";
import { PlusIcon } from "@/components/ui/icons";
import { RecurringRow } from "@/components/common/RecurringRow";
import { MobileScreen } from "@/components/mobile/MobileScreen";

export function RecurringScreen() {
  const { currency } = useAppState();
  const actions = useAppActions();
  const { all, total, subtitle } = useRecurring();

  return (
    <MobileScreen>
      <div className="mb-4 flex items-center justify-between">
        <h1 className="font-display text-2xl font-semibold text-ink">
          Recurring
        </h1>
        <button
          type="button"
          onClick={() => actions.openOverlay("recurring")}
          aria-label="Add recurring"
          className="flex h-[34px] w-[34px] items-center justify-center rounded-[10px] bg-green text-white"
        >
          <PlusIcon size={16} />
        </button>
      </div>

      <HeroCard className="mb-4 p-5">
        <div className="mb-2 text-[13px] text-side-muted">
          Monthly recurring total
        </div>
        <div className="mb-1.5 font-display text-3xl font-semibold">
          {money(total, currency)}
        </div>
        <div className="text-xs text-side-sub">{subtitle}</div>
      </HeroCard>

      <p className="mb-3 text-xs text-muted">Tap a bill to pause or resume it.</p>

      <div className="flex flex-col gap-2">
        {all.map((rec) => (
          <RecurringRow
            key={rec.id}
            recurring={rec}
            currency={currency}
            onToggle={() => actions.toggleRecurring(rec.id)}
          />
        ))}
      </div>
    </MobileScreen>
  );
}
