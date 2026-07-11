"use client";

import type { Frequency } from "@/lib/types";
import { cn } from "@/lib/cn";
import { useAppActions, useAppState } from "@/store/app-store";
import { categoryNames } from "@/features/transactions/selectors";
import { TextField } from "@/components/ui/TextField";
import { Chip } from "@/components/ui/Chip";
import { Button } from "@/components/ui/Button";
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
  const { recurringDraft, limits } = useAppState();
  const actions = useAppActions();

  const amount = parseInt(recurringDraft.amount.replace(/[^0-9]/g, ""), 10) || 0;
  const day = parseInt(recurringDraft.day, 10) || 0;
  const valid =
    recurringDraft.name.trim().length > 0 &&
    amount > 0 &&
    day >= 1 &&
    day <= 31;

  return (
    <div>
      <TextField
        label="Name"
        value={recurringDraft.name}
        onChange={actions.setRecurringName}
        placeholder="e.g. iCloud, House help, SIP"
        className="mb-3.5"
      />

      <div className="mb-3.5 grid grid-cols-2 gap-3">
        <TextField
          label="Amount"
          value={recurringDraft.amount}
          onChange={actions.setRecurringAmount}
          placeholder="₹"
          inputMode="numeric"
        />
        <TextField
          label="Day of month"
          value={recurringDraft.day}
          onChange={actions.setRecurringDay}
          placeholder="1–31"
          inputMode="numeric"
        />
      </div>

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
        <Button onClick={actions.saveRecurring} enabled={valid} className="flex-1">
          Add recurring
        </Button>
      </div>
    </div>
  );
}
