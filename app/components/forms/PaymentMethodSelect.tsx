"use client";

import { useEffect, useId, useRef, useState } from "react";
import {
  paymentMethodLabel,
  type PaymentMethod,
  type PaymentMethodOption,
} from "@/lib/types";
import { cn } from "@/lib/cn";

export function PaymentMethodSelect({
  value,
  onChange,
  methods,
  onManage,
  className,
}: {
  value: PaymentMethod;
  onChange: (value: PaymentMethod) => void;
  methods: PaymentMethodOption[];
  onManage?: () => void;
  className?: string;
}) {
  const [open, setOpen] = useState(false);
  const [activeIndex, setActiveIndex] = useState(() =>
    Math.max(0, methods.findIndex((method) => paymentMethodLabel(method) === value)),
  );
  const rootRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const optionRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const id = useId();
  const labelId = `${id}-label`;
  const listboxId = `${id}-listbox`;

  useEffect(() => {
    if (!open) return;

    const handleOutsidePress = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    };

    document.addEventListener("pointerdown", handleOutsidePress);
    return () => document.removeEventListener("pointerdown", handleOutsidePress);
  }, [open]);

  const openMenu = () => {
    const selectedIndex = Math.max(
      0,
      methods.findIndex((method) => paymentMethodLabel(method) === value),
    );
    setActiveIndex(selectedIndex);
    setOpen(true);
    requestAnimationFrame(() => optionRefs.current[selectedIndex]?.focus());
  };

  const closeMenu = () => {
    setOpen(false);
    requestAnimationFrame(() => triggerRef.current?.focus());
  };

  const selectMethod = (method: PaymentMethodOption) => {
    onChange(paymentMethodLabel(method));
    closeMenu();
  };

  const moveTo = (index: number) => {
    const nextIndex = (index + methods.length) % methods.length;
    setActiveIndex(nextIndex);
    optionRefs.current[nextIndex]?.focus();
  };

  return (
    <div ref={rootRef} className={cn("relative", className)}>
      <span id={labelId} className="mb-1.5 block text-xs text-muted">
        Paid with
      </span>
      <button
        ref={triggerRef}
        type="button"
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={open ? listboxId : undefined}
        aria-labelledby={`${labelId} ${id}-value`}
        onClick={() => (open ? closeMenu() : openMenu())}
        onKeyDown={(event) => {
          if (event.key === "ArrowDown" || event.key === "ArrowUp") {
            event.preventDefault();
            openMenu();
          }
        }}
        className={cn(
          "flex w-full items-center justify-between rounded-xl border bg-canvas px-3.5 py-[11px] text-sm text-ink transition-colors",
          open ? "border-green ring-2 ring-green/10" : "border-line hover:border-hairline",
        )}
      >
        <span id={`${id}-value`}>{value}</span>
        <span
          aria-hidden="true"
          className={cn(
            "ml-3 text-xs text-muted transition-transform duration-200",
            open && "rotate-180",
          )}
        >
          ▾
        </span>
      </button>

      {open ? (
        <div
          id={listboxId}
          role="listbox"
          aria-labelledby={labelId}
          className="absolute inset-x-0 top-full z-50 mt-2 overflow-hidden rounded-xl border border-line bg-popup p-1.5 shadow-[0_16px_40px_rgba(0,0,0,0.28)]"
        >
          {methods.map((method, index) => {
            const label = paymentMethodLabel(method);
            const selected = label === value;
            return (
              <button
                key={method.id}
                ref={(element) => {
                  optionRefs.current[index] = element;
                }}
                type="button"
                role="option"
                aria-selected={selected}
                tabIndex={activeIndex === index ? 0 : -1}
                onMouseEnter={() => setActiveIndex(index)}
                onClick={() => selectMethod(method)}
                onKeyDown={(event) => {
                  if (event.key === "ArrowDown") {
                    event.preventDefault();
                    moveTo(index + 1);
                  } else if (event.key === "ArrowUp") {
                    event.preventDefault();
                    moveTo(index - 1);
                  } else if (event.key === "Home") {
                    event.preventDefault();
                    moveTo(0);
                  } else if (event.key === "End") {
                    event.preventDefault();
                    moveTo(methods.length - 1);
                  } else if (event.key === "Enter" || event.key === " ") {
                    event.preventDefault();
                    selectMethod(method);
                  } else if (event.key === "Escape" || event.key === "Tab") {
                    if (event.key === "Escape") event.preventDefault();
                    setOpen(false);
                    if (event.key === "Escape") triggerRef.current?.focus();
                  }
                }}
                className={cn(
                  "flex w-full items-center justify-between rounded-lg px-3 py-2.5 text-sm transition-colors",
                  selected
                    ? "bg-green-soft font-medium text-green-deep"
                    : "text-ink hover:bg-canvas focus:bg-canvas",
                )}
              >
                <span className="min-w-0 text-left">
                  <span className="block truncate">{method.name}</span>
                  <span className="mt-0.5 block truncate text-xs font-normal text-muted">
                    {[method.type, method.detail].filter(Boolean).join(" · ")}
                  </span>
                </span>
                {selected ? (
                  <span aria-hidden="true" className="ml-3 text-green">
                    ✓
                  </span>
                ) : null}
              </button>
            );
          })}
          {onManage ? (
            <button
              type="button"
              onClick={() => {
                setOpen(false);
                onManage();
              }}
              className="mt-1 w-full border-t border-line px-3 pb-2 pt-3 text-sm font-medium text-green"
            >
              Manage payment methods…
            </button>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
