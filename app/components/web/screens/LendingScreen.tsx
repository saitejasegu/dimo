"use client";

import { useMemo, useState } from "react";
import { money } from "@/lib/format";
import { useAppState } from "@/store/app-store";
import { lendContactSummaries, lendingTotals } from "@/features/lending/selectors";
import type { LendEditorTarget } from "@/components/forms/LendEntryForm";
import { LendEditorDialog } from "@/components/common/LendingDialogs";
import { LendingPeopleList } from "@/components/common/LendingPeople";
import { Button } from "@/components/ui/Button";
import { HeroCard } from "@/components/ui/Card";
import { PageHeader, WebScreen } from "@/components/web/WebScreen";

export function LendingScreen() {
  const { lends, currency } = useAppState("lends", "currency");
  const [editor, setEditor] = useState<LendEditorTarget | null>(null);
  const totals = useMemo(() => lendingTotals(lendContactSummaries(lends)), [lends]);

  return (
    <WebScreen>
      <PageHeader
        title="Lending"
        subtitle="Money you gave and got, kept in step with the people involved."
        align="center"
        action={
          <Button size="sm" onClick={() => setEditor({ mode: "new" })}>
            Add entry
          </Button>
        }
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
      </HeroCard>

      <LendingPeopleList variant="modal" onEdit={setEditor} />
      {editor ? (
        <LendEditorDialog variant="modal" target={editor} onClose={() => setEditor(null)} />
      ) : null}
    </WebScreen>
  );
}
