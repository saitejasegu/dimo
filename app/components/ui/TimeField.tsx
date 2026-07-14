"use client";

import {
  useEffect,
  useId,
  useLayoutEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { createPortal } from "react-dom";
import { cn } from "@/lib/cn";
import { localTimeKey } from "@/lib/dates";

interface TimeFieldProps {
  value: string;
  onChange: (value: string) => void;
  label?: ReactNode;
  /** Latest selectable time as `HH:mm` (e.g. now when the day is today). */
  max?: string;
  className?: string;
}

type Period = "AM" | "PM";

interface Parts {
  hour12: number;
  minute: number;
  period: Period;
}

const POPOVER_GAP = 8;
const VIEWPORT_PAD = 12;
const HOURS = Array.from({ length: 12 }, (_, i) => i + 1);
const MINUTES = Array.from({ length: 60 }, (_, i) => i);
const PERIODS: Period[] = ["AM", "PM"];

function ClockIcon({ className, size = 18 }: { className?: string; size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 20 20"
      fill="none"
      className={className}
      aria-hidden
    >
      <circle cx="10" cy="10" r="7.25" stroke="currentColor" strokeWidth="1.7" />
      <path
        d="M10 6.25V10l2.75 1.75"
        stroke="currentColor"
        strokeWidth="1.7"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function parseParts(value: string): Parts | null {
  if (!/^(\d{2}):(\d{2})$/.test(value)) return null;
  const [hours, minutes] = value.split(":").map(Number);
  if (hours > 23 || minutes > 59) return null;
  return {
    hour12: hours % 12 === 0 ? 12 : hours % 12,
    minute: minutes,
    period: hours >= 12 ? "PM" : "AM",
  };
}

function toValue(parts: Parts): string {
  let hours = parts.hour12 % 12;
  if (parts.period === "PM") hours += 12;
  return `${String(hours).padStart(2, "0")}:${String(parts.minute).padStart(2, "0")}`;
}

function formatDisplay(value: string) {
  const parts = parseParts(value);
  if (!parts) return "";
  return `${parts.hour12}:${String(parts.minute).padStart(2, "0")} ${parts.period}`;
}

function isAllowed(candidate: string, max?: string) {
  if (!max || !/^\d{2}:\d{2}$/.test(max)) return true;
  return candidate <= max;
}

function Column({
  ariaLabel,
  items,
  selected,
  format = String,
  disabled,
  onSelect,
}: {
  ariaLabel: string;
  items: number[] | Period[];
  selected: number | Period;
  format?: (item: number | Period) => string;
  disabled?: (item: number | Period) => boolean;
  onSelect: (item: number | Period) => void;
}) {
  const listRef = useRef<HTMLDivElement>(null);

  useLayoutEffect(() => {
    const list = listRef.current;
    if (!list) return;
    const active = list.querySelector<HTMLElement>('[data-selected="true"]');
    if (!active) return;
    list.scrollTop = active.offsetTop - list.clientHeight / 2 + active.clientHeight / 2;
  }, [selected]);

  return (
    <div className="flex min-w-0 flex-1 flex-col">
      <div className="mb-1.5 text-center text-[11px] font-semibold text-muted">
        {ariaLabel}
      </div>
      <div
        ref={listRef}
        role="listbox"
        aria-label={ariaLabel}
        className="h-[196px] overflow-y-auto overscroll-contain rounded-xl bg-canvas p-1 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
      >
        {items.map((item) => {
          const isSelected = item === selected;
          const isDisabled = disabled?.(item) ?? false;
          return (
            <button
              key={String(item)}
              type="button"
              role="option"
              aria-selected={isSelected}
              data-selected={isSelected ? "true" : undefined}
              disabled={isDisabled}
              onClick={() => onSelect(item)}
              className={cn(
                "flex h-9 w-full items-center justify-center rounded-lg text-[14px] transition-colors",
                isSelected && "bg-green font-semibold text-white",
                !isSelected && !isDisabled && "text-ink hover:bg-popup",
                isDisabled && "pointer-events-none opacity-35",
              )}
            >
              {format(item)}
            </button>
          );
        })}
      </div>
    </div>
  );
}

/** Labeled time field with an in-app picker matching DateField chrome. */
export function TimeField({
  value,
  onChange,
  label,
  max,
  className,
}: TimeFieldProps) {
  const labelId = useId();
  const rootRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const popoverRef = useRef<HTMLDivElement>(null);
  const [open, setOpen] = useState(false);
  const [placement, setPlacement] = useState<{
    top: number;
    left: number;
    width: number;
  } | null>(null);

  const parts = parseParts(value) ?? {
    hour12: 12,
    minute: 0,
    period: "AM" as Period,
  };

  useLayoutEffect(() => {
    if (!open) return;

    function updatePlacement(event?: Event) {
      if (
        event?.target instanceof Node &&
        popoverRef.current?.contains(event.target)
      ) {
        return;
      }

      const trigger = triggerRef.current;
      const popover = popoverRef.current;
      if (!trigger) return;

      const rect = trigger.getBoundingClientRect();
      const popoverHeight = popover?.offsetHeight ?? 300;
      const spaceBelow = window.innerHeight - rect.bottom - VIEWPORT_PAD;
      const spaceAbove = rect.top - VIEWPORT_PAD;
      const openUp = spaceBelow < popoverHeight && spaceAbove > spaceBelow;

      const width = Math.min(
        Math.max(rect.width, 280),
        window.innerWidth - VIEWPORT_PAD * 2,
      );
      const left = Math.min(
        Math.max(VIEWPORT_PAD, rect.left + (rect.width - width) / 2),
        window.innerWidth - width - VIEWPORT_PAD,
      );
      const top = openUp
        ? Math.max(VIEWPORT_PAD, rect.top - popoverHeight - POPOVER_GAP)
        : Math.min(
            rect.bottom + POPOVER_GAP,
            window.innerHeight - popoverHeight - VIEWPORT_PAD,
          );

      setPlacement((current) => {
        if (
          current &&
          current.top === top &&
          current.left === left &&
          current.width === width
        ) {
          return current;
        }
        return { top, left, width };
      });
    }

    updatePlacement();
    window.addEventListener("resize", updatePlacement);
    window.addEventListener("scroll", updatePlacement, true);
    return () => {
      window.removeEventListener("resize", updatePlacement);
      window.removeEventListener("scroll", updatePlacement, true);
    };
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const onPointerDown = (event: PointerEvent) => {
      const target = event.target as Node;
      if (rootRef.current?.contains(target)) return;
      if (popoverRef.current?.contains(target)) return;
      setOpen(false);
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false);
    };
    document.addEventListener("pointerdown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("pointerdown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [open]);

  function commit(next: Parts) {
    const candidate = toValue(next);
    if (!isAllowed(candidate, max)) return;
    onChange(candidate);
  }

  function goNow() {
    const now = localTimeKey(new Date());
    const capped = max && now > max ? max : now;
    onChange(capped);
    setOpen(false);
  }

  const picker = open
    ? createPortal(
        <div
          ref={popoverRef}
          role="dialog"
          aria-label={typeof label === "string" ? label : "Choose time"}
          style={
            placement
              ? {
                  top: placement.top,
                  left: placement.left,
                  width: placement.width,
                }
              : { visibility: "hidden", top: 0, left: 0 }
          }
          className="fixed z-[80] rounded-2xl border border-line bg-popup p-3.5 shadow-[0_16px_40px_rgba(0,0,0,0.28)]"
        >
          <div className="mb-3 font-display text-[15px] font-semibold text-ink">
            {formatDisplay(toValue(parts))}
          </div>

          <div className="flex gap-2">
            <Column
              ariaLabel="Hour"
              items={HOURS}
              selected={parts.hour12}
              onSelect={(hour12) =>
                commit({ ...parts, hour12: hour12 as number })
              }
              disabled={(hour12) =>
                !isAllowed(
                  toValue({ ...parts, hour12: hour12 as number }),
                  max,
                )
              }
            />
            <Column
              ariaLabel="Min"
              items={MINUTES}
              selected={parts.minute}
              format={(minute) => String(minute as number).padStart(2, "0")}
              onSelect={(minute) =>
                commit({ ...parts, minute: minute as number })
              }
              disabled={(minute) =>
                !isAllowed(
                  toValue({ ...parts, minute: minute as number }),
                  max,
                )
              }
            />
            <Column
              ariaLabel="Period"
              items={PERIODS}
              selected={parts.period}
              onSelect={(period) =>
                commit({ ...parts, period: period as Period })
              }
              disabled={(period) =>
                !isAllowed(
                  toValue({ ...parts, period: period as Period }),
                  max,
                )
              }
            />
          </div>

          <div className="mt-3 flex items-center justify-end border-t border-line-soft pt-3">
            <button
              type="button"
              onClick={goNow}
              className="text-[13px] font-medium text-green"
            >
              Now
            </button>
          </div>
        </div>,
        document.body,
      )
    : null;

  return (
    <div ref={rootRef} className={cn("relative block", className)}>
      {label ? (
        <span id={labelId} className="mb-1.5 block text-xs text-muted">
          {label}
        </span>
      ) : null}

      <button
        ref={triggerRef}
        type="button"
        aria-labelledby={label ? labelId : undefined}
        aria-haspopup="dialog"
        aria-expanded={open}
        onClick={() => setOpen((current) => !current)}
        className="flex w-full items-center justify-between rounded-xl border border-line bg-canvas px-3.5 py-[11px] text-left text-base text-ink outline-none transition-colors hover:border-green focus-visible:outline focus-visible:outline-[3px] focus-visible:outline-offset-2 focus-visible:outline-[rgba(31,157,99,0.28)]"
      >
        <span className={cn(!value && "text-faint")}>
          {formatDisplay(value) || "hh:mm"}
        </span>
        <ClockIcon className="text-muted" />
      </button>

      {picker}
    </div>
  );
}
