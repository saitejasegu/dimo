"use client";

import { useMemo, useState } from "react";
import { money } from "@/lib/format";
import { useAppState } from "@/store/app-store";
import { lendContactSummaries, lendingTotals } from "@/features/lending/selectors";
import type { LendEditorTarget } from "@/components/forms/LendEntryForm";
import { LendEditorDialog } from "@/components/common/LendingDialogs";
import { LendingPeopleList } from "@/components/common/LendingPeople";
import { HeroCard } from "@/components/ui/Card";
import { PlusIcon } from "@/components/ui/icons";
import { MobileScreen, MobileTopBar } from "@/components/mobile/MobileScreen";

export function LendingScreen() {
  const { lends, currency } = useAppState("lends", "currency");
  const [editor, setEditor] = useState<LendEditorTarget | null>(null);
  const totals = useMemo(() => lendingTotals(lendContactSummaries(lends)), [lends]);

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
                aria-label="Add entry"
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
          </HeroCard>
        </>
      }
    >
      <LendingPeopleList variant="sheet" onEdit={setEditor} />
      {editor ? (
        <LendEditorDialog variant="sheet" target={editor} onClose={() => setEditor(null)} />
      ) : null}
    </MobileScreen>
  );
}
