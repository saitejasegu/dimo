"use client";

import { useEffect, useId, useRef, useState } from "react";
import type { PaymentMethod } from "@/lib/types";
import { cn } from "@/lib/cn";

const ALL_METHODS = "All";

export function PaymentMethodFilter({
  value,
  options,
  onChange,
  className,
  inputStyle = false,
}: {
  value: PaymentMethod | "All";
  options: PaymentMethod[];
  onChange: (value: PaymentMethod | "All") => void;
  className?: string;
  inputStyle?: boolean;
}) {
  const items = [ALL_METHODS, ...options];
  const [open, setOpen] = useState(false);
  const [activeIndex, setActiveIndex] = useState(() =>
    Math.max(0, items.indexOf(value)),
  );
  const rootRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const optionRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const id = useId();
  const listboxId = `${id}-listbox`;

  useEffect(() => {
    if (!open) return;

    const handleOutsidePress = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    };
    const handleEscape = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      setOpen(false);
      triggerRef.current?.focus();
    };

    document.addEventListener("pointerdown", handleOutsidePress);
    document.addEventListener("keydown", handleEscape);
    return () => {
      document.removeEventListener("pointerdown", handleOutsidePress);
      document.removeEventListener("keydown", handleEscape);
    };
  }, [open]);

  const displayLabel = value === ALL_METHODS ? "All payment methods" : value;

  const openMenu = (preferredIndex?: number) => {
    const selectedIndex = Math.max(0, items.indexOf(value));
    const nextIndex = preferredIndex ?? selectedIndex;
    setActiveIndex(nextIndex);
    setOpen(true);
    requestAnimationFrame(() => optionRefs.current[nextIndex]?.focus());
  };

  const closeMenu = (restoreFocus = true) => {
    setOpen(false);
    if (restoreFocus) requestAnimationFrame(() => triggerRef.current?.focus());
  };

  const selectItem = (item: string) => {
    onChange(item);
    closeMenu();
  };

  const moveTo = (index: number) => {
    const nextIndex = (index + items.length) % items.length;
    setActiveIndex(nextIndex);
    optionRefs.current[nextIndex]?.focus();
  };

  return (
    <div ref={rootRef} className={cn("relative min-w-0", className)}>
      <button
        ref={triggerRef}
        id={`${id}-trigger`}
        type="button"
        aria-label="Filter by payment method"
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={open ? listboxId : undefined}
        onClick={() => (open ? closeMenu() : openMenu())}
        onKeyDown={(event) => {
          if (event.key === "ArrowDown" || event.key === "ArrowUp") {
            event.preventDefault();
            openMenu(event.key === "ArrowDown" ? 0 : items.length - 1);
          }
        }}
        className={cn(
          inputStyle
            ? "flex w-full items-center justify-between rounded-xl border bg-surface px-3.5 py-[11px] text-sm text-ink outline-none transition-colors"
            : "flex h-9 w-full items-center justify-between rounded-full border bg-surface py-1.5 pl-3.5 pr-3 text-xs font-medium text-ink outline-none transition-colors",
          open
            ? "border-green ring-2 ring-green/10"
            : "border-line hover:border-hairline",
        )}
      >
        <span className="truncate">{displayLabel}</span>
        <span
          aria-hidden="true"
          className={cn(
            "ml-2 shrink-0 text-[10px] text-muted transition-transform duration-200",
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
          aria-labelledby={`${id}-trigger`}
          className={cn(
            "absolute inset-x-0 z-50 max-h-64 overflow-y-auto rounded-xl border border-line bg-popup p-1.5 shadow-[0_16px_40px_rgba(0,0,0,0.24)]",
            inputStyle ? "bottom-full mb-2" : "top-full mt-2",
          )}
        >
          {items.map((item, index) => {
            const selected = item === value;
            const label = item === ALL_METHODS ? "All payment methods" : item;
            return (
              <button
                key={item}
                ref={(element) => {
                  optionRefs.current[index] = element;
                }}
                type="button"
                role="option"
                aria-selected={selected}
                tabIndex={activeIndex === index ? 0 : -1}
                onMouseEnter={() => setActiveIndex(index)}
                onClick={() => selectItem(item)}
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
                    moveTo(items.length - 1);
                  } else if (event.key === "Enter" || event.key === " ") {
                    event.preventDefault();
                    selectItem(item);
                  } else if (event.key === "Tab") {
                    closeMenu(false);
                  }
                }}
                className={cn(
                  "flex w-full items-center justify-between gap-3 rounded-lg px-3 py-2.5 text-left text-sm outline-none transition-colors",
                  selected
                    ? "bg-green-soft font-medium text-green-deep"
                    : "text-ink hover:bg-canvas focus:bg-canvas",
                )}
              >
                <span className="min-w-0 truncate">{label}</span>
                {selected ? (
                  <span aria-hidden="true" className="shrink-0 text-green">
                    ✓
                  </span>
                ) : null}
              </button>
            );
          })}
        </div>
      ) : null}
    </div>
  );
}
