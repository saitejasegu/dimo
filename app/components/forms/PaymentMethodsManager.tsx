"use client";

import { useState } from "react";
import type {
  PaymentMethodInput,
  PaymentMethodOption,
  PaymentMethodType,
} from "@/lib/types";
import { useAppActions, useAppState } from "@/store/app-store";
import { cn } from "@/lib/cn";
import { Button } from "@/components/ui/Button";
import { Chip } from "@/components/ui/Chip";
import { TextField } from "@/components/ui/TextField";

const TYPES: PaymentMethodType[] = ["UPI", "Card", "Wallet", "Cash", "Bank"];
const EMPTY_INPUT: PaymentMethodInput = { name: "", type: "UPI", detail: "" };

function MethodRow({
  method,
  onEdit,
}: {
  method: PaymentMethodOption;
  onEdit: () => void;
}) {
  const actions = useAppActions();
  const subline = [method.type, method.detail].filter(Boolean).join(" · ");

  return (
    <div className="flex items-center gap-3 py-3 first:pt-0 last:pb-0">
      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-canvas font-display text-sm font-semibold text-ink">
        {method.type === "Cash" ? "₹" : method.name.charAt(0).toUpperCase()}
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="truncate text-sm font-medium text-ink">{method.name}</span>
          {method.isDefault && !method.archived ? (
            <span className="rounded-full bg-green-soft px-2 py-0.5 text-[10px] font-semibold text-green-deep">
              Default
            </span>
          ) : null}
          {method.archived ? (
            <span className="rounded-full bg-canvas-deep px-2 py-0.5 text-[10px] font-medium text-muted">
              Archived
            </span>
          ) : null}
        </div>
        <div className="mt-0.5 truncate text-xs text-muted">{subline}</div>
      </div>
      <div className="flex shrink-0 flex-col items-end gap-1 text-xs font-medium sm:flex-row sm:items-center sm:gap-2">
        {method.archived ? (
          <button
            type="button"
            onClick={() => actions.setPaymentMethodArchived(method.id, false)}
            className="text-green"
          >
            Restore
          </button>
        ) : (
          <>
            {!method.isDefault ? (
              <button
                type="button"
                onClick={() => actions.setDefaultPaymentMethod(method.id)}
                className="text-green"
              >
                Set default
              </button>
            ) : null}
            <button type="button" onClick={onEdit} className="text-body">
              Edit
            </button>
            <button
              type="button"
              onClick={() => actions.setPaymentMethodArchived(method.id, true)}
              className="text-danger"
            >
              Archive
            </button>
          </>
        )}
      </div>
    </div>
  );
}

export function PaymentMethodsManager({ className }: { className?: string }) {
  const { paymentMethods } = useAppState();
  const actions = useAppActions();
  const [editingId, setEditingId] = useState<string | "new" | null>(null);
  const [draft, setDraft] = useState<PaymentMethodInput>(EMPTY_INPUT);
  const [error, setError] = useState("");

  const active = paymentMethods.filter((method) => !method.archived);
  const archived = paymentMethods.filter((method) => method.archived);

  const startAdd = () => {
    setDraft(EMPTY_INPUT);
    setError("");
    setEditingId("new");
  };

  const startEdit = (method: PaymentMethodOption) => {
    setDraft({ name: method.name, type: method.type, detail: method.detail });
    setError("");
    setEditingId(method.id);
  };

  const save = () => {
    const name = draft.name.trim();
    if (!name) {
      setError("Enter a name for this payment method.");
      return;
    }
    const duplicate = paymentMethods.some(
      (method) =>
        method.id !== editingId && method.name.toLowerCase() === name.toLowerCase(),
    );
    if (duplicate) {
      setError("That payment method already exists.");
      return;
    }
    if (editingId === "new") actions.addPaymentMethod(draft);
    else if (editingId) actions.editPaymentMethod(editingId, draft);
    setEditingId(null);
  };

  return (
    <section id="payment-methods" className={className}>
      <div className="mb-4 flex items-center justify-between gap-4">
        <div>
          <h2 className="font-display text-[17px] font-semibold text-ink">
            Payment methods
          </h2>
          <p className="mt-0.5 text-xs text-muted">
            Choose how new expenses are paid.
          </p>
        </div>
        {editingId ? null : (
          <Button size="sm" onClick={startAdd}>
            Add
          </Button>
        )}
      </div>

      {editingId ? (
        <div className="mb-4 rounded-2xl border border-line bg-canvas p-4">
          <div className="mb-3 font-display text-sm font-semibold text-ink">
            {editingId === "new" ? "New payment method" : "Edit payment method"}
          </div>
          <TextField
            label="Display name"
            value={draft.name}
            onChange={(name) => setDraft((current) => ({ ...current, name }))}
            placeholder="e.g. HDFC Debit"
            className="mb-3"
          />
          <div className="mb-1.5 text-xs text-muted">Type</div>
          <div className="mb-3 flex flex-wrap gap-2">
            {TYPES.map((type) => (
              <Chip
                key={type}
                label={type}
                selected={draft.type === type}
                surface="white"
                onClick={() =>
                  setDraft((current) => ({
                    ...current,
                    type,
                    detail: type === "Cash" ? "" : current.detail,
                  }))
                }
              />
            ))}
          </div>
          {draft.type !== "Cash" ? (
            <TextField
              label="Identifier"
              value={draft.detail}
              onChange={(detail) => setDraft((current) => ({ ...current, detail }))}
              placeholder={draft.type === "UPI" ? "e.g. aarav@upi or ••42" : "e.g. ••08"}
              className="mb-3"
            />
          ) : null}
          {error ? <p className="mb-3 text-xs text-danger">{error}</p> : null}
          <div className="flex gap-2.5">
            <Button
              variant="secondary"
              size="sm"
              onClick={() => setEditingId(null)}
              className="flex-1"
            >
              Cancel
            </Button>
            <Button size="sm" onClick={save} className="flex-1">
              Save method
            </Button>
          </div>
        </div>
      ) : null}

      <div className="divide-y divide-line-soft">
        {active.map((method) => (
          <MethodRow key={method.id} method={method} onEdit={() => startEdit(method)} />
        ))}
      </div>

      {archived.length ? (
        <div className="mt-4 border-t border-line pt-4">
          <div className="mb-3 text-xs font-medium uppercase tracking-[0.08em] text-muted">
            Archived
          </div>
          <div className="divide-y divide-line-soft">
            {archived.map((method) => (
              <MethodRow key={method.id} method={method} onEdit={() => startEdit(method)} />
            ))}
          </div>
        </div>
      ) : null}

      <p className={cn("mt-4 text-[11px] leading-4 text-muted", archived.length && "mt-3")}>
        Archived methods stay attached to past transactions.
      </p>
    </section>
  );
}
