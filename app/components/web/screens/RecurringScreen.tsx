"use client";

import { money } from "@/lib/format";
import { useAppActions, useAppState } from "@/store/app-store";
import { useRecurring } from "@/features/recurring/hooks";
import { HeroCard } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { PlusIcon } from "@/components/ui/icons";
import { RecurringCard } from "@/components/common/RecurringCard";
import { WebScreen } from "@/components/web/WebScreen";

export function RecurringScreen() {
  const { currency } = useAppState();
  const actions = useAppActions();
  const { all, total, subtitle } = useRecurring();

  return (
    <WebScreen>
      <div className="mb-[22px] flex items-center justify-between">
        <div>
          <div className="font-display text-[28px] font-semibold text-ink">
            Recurring
          </div>
          <div className="mt-1 text-[13px] text-muted">
            Click a bill to pause or resume it.
          </div>
        </div>
        <Button
          variant="accent"
          size="sm"
          onClick={() => actions.openOverlay("recurring")}
          leftIcon={<PlusIcon size={15} />}
        >
          Add recurring
        </Button>
      </div>

      <HeroCard className="mb-[22px] flex items-center justify-between p-6">
        <div>
          <div className="mb-2 text-[13px] text-side-muted">
            Monthly recurring total
          </div>
          <div className="font-display text-4xl font-semibold">
            {money(total, currency)}
          </div>
        </div>
        <div className="text-[13px] text-side-sub">{subtitle}</div>
      </HeroCard>

      <div className="grid grid-cols-3 gap-4">
        {all.map((rec) => (
          <RecurringCard
            key={rec.id}
            recurring={rec}
            currency={currency}
            onToggle={() => actions.toggleRecurring(rec.id)}
          />
        ))}
      </div>
    </WebScreen>
  );
}
