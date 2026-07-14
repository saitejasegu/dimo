"use client";

import { useEffect, useId, useMemo, useRef, useState } from "react";
import type { Transaction } from "@/lib/types";
import { cn } from "@/lib/cn";
import {
  merchantSuggestions,
  type MerchantSuggestion,
} from "@/features/transactions/selectors";

interface MerchantFieldProps {
  value: string;
  onChange: (value: string) => void;
  onSelectSuggestion?: (suggestion: MerchantSuggestion) => void;
  transactions: Transaction[];
  placeholder?: string;
  className?: string;
}

/** Merchant text field with typeahead from past transactions. */
export function MerchantField({
  value,
  onChange,
  onSelectSuggestion,
  transactions,
  placeholder = "Merchant (e.g. Chai Point)",
  className,
}: MerchantFieldProps) {
  const [open, setOpen] = useState(false);
  const [activeIndex, setActiveIndex] = useState(0);
  const rootRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const id = useId();
  const listboxId = `${id}-listbox`;

  const suggestions = useMemo(
    () => merchantSuggestions(transactions, value),
    [transactions, value],
  );

  const showList = open && suggestions.length > 0;

  useEffect(() => {
    if (!showList) return;

    const handleOutsidePress = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    };

    document.addEventListener("pointerdown", handleOutsidePress);
    return () => document.removeEventListener("pointerdown", handleOutsidePress);
  }, [showList]);

  const pick = (suggestion: MerchantSuggestion) => {
    onChange(suggestion.name);
    onSelectSuggestion?.(suggestion);
    setOpen(false);
    inputRef.current?.blur();
  };

  const moveTo = (index: number) => {
    if (suggestions.length === 0) return;
    setActiveIndex((index + suggestions.length) % suggestions.length);
  };

  return (
    <div ref={rootRef} className={cn("relative", className)}>
      <input
        ref={inputRef}
        type="text"
        role="combobox"
        aria-expanded={showList}
        aria-controls={showList ? listboxId : undefined}
        aria-activedescendant={
          showList && suggestions[activeIndex]
            ? `${id}-option-${activeIndex}`
            : undefined
        }
        aria-autocomplete="list"
        autoComplete="off"
        value={value}
        placeholder={placeholder}
        onChange={(e) => {
          onChange(e.target.value);
          setActiveIndex(0);
          setOpen(true);
        }}
        onFocus={() => setOpen(true)}
        onBlur={() => setOpen(false)}
        onKeyDown={(event) => {
          if (!showList) {
            if (event.key === "ArrowDown" && suggestions.length > 0) {
              event.preventDefault();
              setOpen(true);
            }
            return;
          }

          if (event.key === "ArrowDown") {
            event.preventDefault();
            moveTo(activeIndex + 1);
          } else if (event.key === "ArrowUp") {
            event.preventDefault();
            moveTo(activeIndex - 1);
          } else if (event.key === "Enter" && suggestions[activeIndex]) {
            event.preventDefault();
            pick(suggestions[activeIndex]);
          } else if (event.key === "Escape") {
            event.preventDefault();
            setOpen(false);
          }
        }}
        className={cn(
          "w-full rounded-xl border bg-canvas px-3.5 py-[11px] text-base text-ink outline-none placeholder:text-faint",
          showList
            ? "border-green ring-2 ring-green/10"
            : "border-line",
        )}
      />

      {showList ? (
        <div
          id={listboxId}
          role="listbox"
          className="absolute inset-x-0 top-full z-50 mt-2 overflow-hidden rounded-xl border border-line bg-popup p-1.5 shadow-[0_16px_40px_rgba(0,0,0,0.28)]"
        >
          {suggestions.map((suggestion, index) => (
            <button
              key={suggestion.name}
              id={`${id}-option-${index}`}
              type="button"
              role="option"
              aria-selected={index === activeIndex}
              tabIndex={-1}
              onMouseEnter={() => setActiveIndex(index)}
              onMouseDown={(event) => event.preventDefault()}
              onClick={() => pick(suggestion)}
              className={cn(
                "flex w-full items-center justify-between rounded-lg px-3 py-2.5 text-left text-sm transition-colors",
                index === activeIndex
                  ? "bg-green-soft font-medium text-green-deep"
                  : "text-ink hover:bg-canvas",
              )}
            >
              <span className="min-w-0 flex-1">
                <span className="block truncate">{suggestion.name}</span>
                <span className="mt-0.5 block truncate text-xs font-normal text-muted">
                  {suggestion.category}
                  {suggestion.count > 1 ? ` · ${suggestion.count} times` : ""}
                </span>
              </span>
            </button>
          ))}
        </div>
      ) : null}
    </div>
  );
}
