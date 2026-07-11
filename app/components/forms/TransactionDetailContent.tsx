"use client";

import type { Currency, Transaction } from "@/lib/types";
import { spent } from "@/lib/format";
import { cn } from "@/lib/cn";
import { useAppActions } from "@/store/app-store";
import { CategoryTint } from "@/components/ui/CategoryTint";
import { Button } from "@/components/ui/Button";

interface DetailRowProps {
  label: string;
  value: string;
  muted?: boolean;
  divider?: boolean;
}

function DetailRow({ label, value, muted, divider }: DetailRowProps) {
  return (
    <div
      className={cn(
        "flex justify-between py-3 text-[13px]",
        divider && "border-b border-line",
      )}
    >
      <span className="text-muted">{label}</span>
      <span className={muted ? "text-faint" : "font-medium text-ink"}>
        {value}
      </span>
    </div>
  );
}

/** Shared transaction detail body used by the mobile sheet and web modal. */
export function TransactionDetailContent({
  transaction,
  currency,
  size = "mobile",
}: {
  transaction: Transaction;
  currency: Currency;
  size?: "mobile" | "web";
}) {
  const actions = useAppActions();
  const web = size === "web";

  return (
    <div>
      <div className="mb-5 flex items-center gap-3.5">
        <CategoryTint
          green={transaction.green}
          size={web ? 52 : 48}
          radius={web ? 15 : 14}
        />
        <div className="flex-1">
          <div
            className={cn(
              "font-display font-semibold text-ink",
              web ? "text-[19px]" : "text-lg",
            )}
          >
            {transaction.name}
          </div>
          <div className="text-[13px] text-muted">
            {transaction.day} · {transaction.time}
          </div>
        </div>
        <div
          className={cn(
            "font-display font-semibold text-ink",
            web ? "text-2xl" : "text-[22px]",
          )}
        >
          {spent(transaction.amount, currency)}
        </div>
      </div>

      <div className="mb-5 rounded-2xl bg-canvas px-4">
        <DetailRow label="Category" value={transaction.category} divider />
        <DetailRow label="Paid with" value="UPI · HDFC ••42" divider />
        <DetailRow label="Note" value="Add a note…" muted />
      </div>

      <div className="flex gap-3">
        <Button variant="secondary" onClick={actions.closeDetail} className="flex-1">
          Close
        </Button>
        <Button variant="danger" onClick={actions.deleteDetail} className="flex-1">
          Delete
        </Button>
      </div>
    </div>
  );
}
