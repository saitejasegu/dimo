"use client";

import { cn } from "@/lib/cn";
import { currencySymbol } from "@/lib/format";
import { useAppActions, useAppState } from "@/store/app-store";
import { categoryNames } from "@/features/transactions/selectors";
import { Sheet } from "@/components/ui/Sheet";
import { Button } from "@/components/ui/Button";
import { TextField } from "@/components/ui/TextField";
import { CategoryChips } from "@/components/forms/CategoryChips";
import { AmountKeypad } from "@/components/forms/AmountKeypad";

export function AddExpenseSheet() {
  const { expenseDraft, limits, currency } = useAppState();
  const actions = useAppActions();

  const amountOk = parseFloat(expenseDraft.amount) > 0;

  return (
    <Sheet onClose={actions.closeOverlay} title="Add expense">
      <div
        className={cn(
          "mb-3.5 text-center font-display text-[40px] font-semibold",
          amountOk ? "text-ink" : "text-[#c3cdc7]",
        )}
      >
        {currencySymbol(currency)}
        {expenseDraft.amount || "0"}
      </div>

      <TextField
        value={expenseDraft.name}
        onChange={actions.setExpenseName}
        placeholder="Merchant (e.g. Chai Point)"
        className="mb-3"
      />

      <CategoryChips
        categories={categoryNames(limits)}
        value={expenseDraft.category}
        onChange={actions.setExpenseCategory}
        className="mb-4 flex flex-wrap gap-2"
      />

      <div className="mb-4">
        <AmountKeypad onPress={actions.pressAmountKey} />
      </div>

      <Button onClick={actions.saveExpense} enabled={amountOk} fullWidth>
        Save expense
      </Button>
    </Sheet>
  );
}
