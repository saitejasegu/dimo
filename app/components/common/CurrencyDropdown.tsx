"use client";

import { useEffect, useId, useRef, useState } from "react";
import { CURRENCY_OPTIONS } from "@/features/account/constants";
import type { Currency } from "@/lib/types";
import { cn } from "@/lib/cn";

export function CurrencyDropdown({
  value,
  onChange,
  className,
}: {
  value: Currency;
  onChange: (value: Currency) => void;
  className?: string;
}) {
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const id = useId();
  const selectedLabel =
    CURRENCY_OPTIONS.find((option) => option.value === value)?.label ?? value;

  useEffect(() => {
    if (!open) return;
    const onPointerDown = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      setOpen(false);
      triggerRef.current?.focus();
    };
    document.addEventListener("pointerdown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("pointerdown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [open]);

  return (
    <div ref={rootRef} className={cn("relative", className)}>
      <button
        ref={triggerRef}
        id={`${id}-trigger`}
        type="button"
        aria-label="Currency"
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={open ? `${id}-listbox` : undefined}
        onClick={() => setOpen((current) => !current)}
        className={cn(
          "flex h-9 min-w-28 items-center justify-between gap-3 rounded-full border bg-surface px-3.5 text-xs font-semibold text-ink transition-colors",
          open
            ? "border-green ring-2 ring-green/10"
            : "border-line hover:border-hairline",
        )}
      >
        <span>{selectedLabel}</span>
        <span
          aria-hidden="true"
          className={cn(
            "text-[10px] text-muted transition-transform duration-200",
            open && "rotate-180",
          )}
        >
          ▾
        </span>
      </button>

      {open ? (
        <div
          id={`${id}-listbox`}
          role="listbox"
          aria-labelledby={`${id}-trigger`}
          className="absolute right-0 top-full z-50 mt-2 w-36 rounded-xl border border-line bg-popup p-1.5 shadow-[0_16px_40px_rgba(0,0,0,0.24)]"
        >
          {CURRENCY_OPTIONS.map((option) => {
            const selected = option.value === value;
            return (
              <button
                key={option.value}
                type="button"
                role="option"
                aria-selected={selected}
                onClick={() => {
                  onChange(option.value);
                  setOpen(false);
                  requestAnimationFrame(() => triggerRef.current?.focus());
                }}
                className={cn(
                  "flex w-full items-center justify-between rounded-lg px-3 py-2.5 text-sm transition-colors",
                  selected
                    ? "bg-green-soft font-medium text-green-deep"
                    : "text-ink hover:bg-canvas focus:bg-canvas",
                )}
              >
                <span>{option.label}</span>
                {selected ? <span className="text-green">✓</span> : null}
              </button>
            );
          })}
        </div>
      ) : null}
    </div>
  );
}
