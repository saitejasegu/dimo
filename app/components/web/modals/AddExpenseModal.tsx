"use client";

import { currencySymbol } from "@/lib/format";
import { paymentMethodLabel } from "@/lib/types";
import { useAppActions, useAppState } from "@/store/app-store";
import { categoryNames } from "@/features/transactions/selectors";
import { Modal } from "@/components/ui/Modal";
import { Button } from "@/components/ui/Button";
import { CategoryChips } from "@/components/forms/CategoryChips";
import { MerchantField } from "@/components/forms/MerchantField";
import { PaymentMethodSelect } from "@/components/forms/PaymentMethodSelect";

export function AddExpenseModal() {
  const { expenseDraft, limits, currency, paymentMethods, transactions } =
    useAppState();
  const actions = useAppActions();

  const amountOk = parseFloat(expenseDraft.amount) > 0;
  const availableMethods = paymentMethods.filter((method) => !method.archived);

  return (
    <Modal onClose={actions.closeOverlay} width={440} title="Add expense">
      <div className="mb-3.5 flex items-center gap-2.5 rounded-[14px] border border-line bg-canvas px-[18px] py-3.5">
        <span className="font-display text-[26px] font-semibold text-faint">
          {currencySymbol(currency)}
        </span>
        <input
          value={expenseDraft.amount}
          onChange={(e) => actions.setExpenseAmount(e.target.value)}
          placeholder="0"
          inputMode="decimal"
          autoComplete="off"
          autoFocus
          className="w-full flex-1 bg-transparent font-display text-[32px] font-semibold text-ink outline-none placeholder:text-faint"
        />
      </div>

      <MerchantField
        value={expenseDraft.name}
        onChange={actions.setExpenseName}
        transactions={transactions}
        className="mb-4"
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

      <p className="mb-2 text-xs text-muted">Category</p>
      <CategoryChips
        selectedFirst
        categories={categoryNames(limits)}
        value={expenseDraft.category}
        onChange={actions.setExpenseCategory}
        className="mb-4 gap-2.5"
      />

      <PaymentMethodSelect
        value={expenseDraft.paymentMethod}
        onChange={actions.setExpensePaymentMethod}
        methods={availableMethods}
        onManage={actions.managePaymentMethods}
        className="mb-[22px]"
      />

      <div className="flex gap-3">
        <Button variant="secondary" onClick={actions.closeOverlay} className="shrink-0">
          Cancel
        </Button>
        <Button onClick={actions.saveExpense} enabled={amountOk} className="flex-1">
          Save expense
        </Button>
      </div>
    </Modal>
  );
}
