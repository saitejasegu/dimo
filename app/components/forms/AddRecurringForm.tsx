"use client";

import { useState } from "react";
import type { Frequency } from "@/lib/types";
import { cn } from "@/lib/cn";
import { localDateKey, nextOccurrence, occurrencesThrough } from "@/lib/dates";
import { useAppActions, useAppState } from "@/store/app-store";
import { categoryNames } from "@/features/transactions/selectors";
import { TextField } from "@/components/ui/TextField";
import { Chip } from "@/components/ui/Chip";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { CategoryChips } from "@/components/forms/CategoryChips";

const FREQUENCIES: Frequency[] = ["Monthly", "Yearly"];

interface AddRecurringFormProps {
  /** When provided, renders a Cancel button beside Save (web modal). */
  onCancel?: () => void;
  /** Stretch the frequency chips to fill the row (mobile). */
  fillFrequency?: boolean;
}

export function AddRecurringForm({
  onCancel,
  fillFrequency = false,
}: AddRecurringFormProps) {
  const { recurringDraft, recurring, limits } = useAppState();
  const actions = useAppActions();
  const [backfillCount, setBackfillCount] = useState<number | null>(null);

  const editing = Boolean(recurringDraft.id);
  const today = localDateKey(new Date());
  const original = editing
    ? recurring.find((item) => item.id === recurringDraft.id)
    : undefined;
  const originalFrequency: Frequency =
    original?.frequency === "yearly" ? "Yearly" : "Monthly";
  const originalDueDate = original?.anchorDate
    ? localDateKey(
        nextOccurrence({
          anchorDate: original.anchorDate,
          frequency: original.frequency ?? "monthly",
        }),
      )
    : "";
  const dirty =
    !editing ||
    !original ||
    recurringDraft.name.trim() !== original.name ||
    recurringDraft.amount !== String(Math.round(original.amount)) ||
    recurringDraft.anchorDate !== originalDueDate ||
    recurringDraft.frequency !== originalFrequency ||
    recurringDraft.category !== original.category;

  const amount = parseInt(recurringDraft.amount.replace(/[^0-9]/g, ""), 10) || 0;
  const valid =
    recurringDraft.name.trim().length > 0 &&
    amount > 0 &&
    /^\d{4}-\d{2}-\d{2}$/.test(recurringDraft.anchorDate) &&
    (!editing || recurringDraft.anchorDate >= today);

  const primaryLabel = !editing
    ? "Add recurring"
    : dirty
      ? "Save"
      : original?.paused
        ? "Resume"
        : "Pause";

  function onPrimary() {
    if (editing && !dirty && recurringDraft.id) {
      actions.toggleRecurring(recurringDraft.id);
      return;
    }
    if (editing) {
      actions.saveRecurring();
      return;
    }

    const count = occurrencesThrough({
      anchorDate: recurringDraft.anchorDate,
      frequency: recurringDraft.frequency.toLowerCase() as "monthly" | "yearly",
    }).length;

    if (count > 0) {
      setBackfillCount(count);
      return;
    }

    actions.saveRecurring();
  }

  return (
    <div>
      <TextField
        label="Name"
        value={recurringDraft.name}
        onChange={actions.setRecurringName}
        placeholder="e.g. iCloud, House help, SIP"
        className="mb-3.5"
      />

      <TextField
        label="Amount"
        value={recurringDraft.amount}
        onChange={actions.setRecurringAmount}
        placeholder="₹"
        inputMode="numeric"
        className="mb-3.5"
      />
      <TextField
        label={editing ? "Next due date" : "Start date"}
        value={recurringDraft.anchorDate}
        onChange={actions.setRecurringAnchorDate}
        type="date"
        min={editing ? today : undefined}
        className="mb-3.5"
      />

      <p className="mb-1.5 text-xs text-muted">Category</p>
      <CategoryChips
        categories={categoryNames(limits)}
        value={recurringDraft.category}
        onChange={actions.setRecurringCategory}
        className="mb-3.5"
      />

      <p className="mb-1.5 text-xs text-muted">Repeats</p>
      <div className="mb-5 flex gap-2">
        {FREQUENCIES.map((frequency) => (
          <Chip
            key={frequency}
            label={frequency}
            surface="canvas"
            selected={recurringDraft.frequency === frequency}
            onClick={() => actions.setRecurringFrequency(frequency)}
            className={cn(fillFrequency && "flex-1 text-center")}
          />
        ))}
      </div>

      <div className="flex gap-3">
        {onCancel ? (
          <Button variant="secondary" onClick={onCancel} className="shrink-0">
            Cancel
          </Button>
        ) : null}
        <Button
          onClick={onPrimary}
          enabled={!editing || dirty ? valid : true}
          className="flex-1"
        >
          {primaryLabel}
        </Button>
      </div>

      <ConfirmDialog
        open={backfillCount != null}
        title="Add past transactions?"
        message={
          backfillCount === 1
            ? "This will add 1 transaction from the start date through today."
            : `This will add ${backfillCount} transactions from the start date through today.`
        }
        confirmLabel="Add"
        tone="primary"
        onCancel={() => setBackfillCount(null)}
        onConfirm={() => {
          setBackfillCount(null);
          actions.saveRecurring();
        }}
      />
    </div>
  );
}
