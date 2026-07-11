"use client";

import { useEffect, useId, useRef, useState } from "react";
import { RANGE_LABEL, STATS_RANGES } from "@/features/stats/constants";
import type { StatsRange } from "@/lib/types";
import { cn } from "@/lib/cn";

export function StatsRangeDropdown({
  value,
  onChange,
  onChangeDefaults,
  className,
}: {
  value: StatsRange;
  onChange: (value: StatsRange) => void;
  onChangeDefaults?: () => void;
  className?: string;
}) {
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const id = useId();

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
        aria-label="Statistics range"
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
        <span>{RANGE_LABEL[value]}</span>
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
          {STATS_RANGES.map((range) => {
            const selected = range === value;
            return (
              <button
                key={range}
                type="button"
                role="option"
                aria-selected={selected}
                onClick={() => {
                  onChange(range);
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
                <span>{RANGE_LABEL[range]}</span>
                {selected ? <span className="text-green">✓</span> : null}
              </button>
            );
          })}
          {onChangeDefaults ? (
            <button
              type="button"
              onClick={() => {
                setOpen(false);
                onChangeDefaults();
              }}
              className="mt-1 w-full border-t border-line px-3 pb-2 pt-3 text-sm font-medium text-green"
            >
              Configure
            </button>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
