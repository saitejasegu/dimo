"use client";

import { cn } from "@/lib/cn";
import { currencySymbol } from "@/lib/format";
import { paymentMethodLabel } from "@/lib/types";
import { useAppActions, useAppState } from "@/store/app-store";
import { categoryNames } from "@/features/transactions/selectors";
import { Sheet } from "@/components/ui/Sheet";
import { Button } from "@/components/ui/Button";
import { CategoryChips } from "@/components/forms/CategoryChips";
import { AmountKeypad } from "@/components/forms/AmountKeypad";
import { MerchantField } from "@/components/forms/MerchantField";
import { PaymentMethodSelect } from "@/components/forms/PaymentMethodSelect";

export function AddExpenseSheet() {
  const { expenseDraft, limits, currency, paymentMethods, transactions } =
    useAppState();
  const actions = useAppActions();

  const amountOk = parseFloat(expenseDraft.amount) > 0;
  const availableMethods = paymentMethods.filter((method) => !method.archived);

  return (
    <Sheet onClose={actions.closeOverlay} title="Add expense">
      <div
        className={cn(
          "mb-3.5 text-center font-display text-[40px] font-semibold",
          amountOk ? "text-ink" : "text-disabled",
        )}
      >
        {currencySymbol(currency)}
        {expenseDraft.amount || "0"}
      </div>

      <MerchantField
        value={expenseDraft.name}
        onChange={actions.setExpenseName}
        transactions={transactions}
        className="mb-3"
        onSelectSuggestion={(suggestion) => {
          actions.setExpenseName(suggestion.name);
          actions.setExpenseCategory(suggestion.category);
          if (
            suggestion.paymentMethod &&
            availableMethods.some(
              (method) =>
                paymentMethodLabel(method) === suggestion.paymentMethod,
            )
          ) {
            actions.setExpensePaymentMethod(suggestion.paymentMethod);
          }
        }}
      />

      <CategoryChips
        selectedFirst
        categories={categoryNames(limits)}
        value={expenseDraft.category}
        onChange={actions.setExpenseCategory}
        className="mb-4"
      />

      <PaymentMethodSelect
        value={expenseDraft.paymentMethod}
        onChange={actions.setExpensePaymentMethod}
        methods={availableMethods}
        onManage={actions.managePaymentMethods}
        className="mb-4"
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
