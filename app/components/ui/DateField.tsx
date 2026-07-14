"use client";

import {
  useEffect,
  useId,
  useLayoutEffect,
  useRef,
  useState,
  type ReactNode,
  type RefObject,
} from "react";
import { createPortal } from "react-dom";
import { cn } from "@/lib/cn";
import { localDateKey, parseLocalDate } from "@/lib/dates";
import { ChevronIcon } from "@/components/ui/icons";

interface DateFieldProps {
  value: string;
  onChange: (value: string) => void;
  label?: ReactNode;
  /** Earliest selectable day as `YYYY-MM-DD`. */
  min?: string;
  /** Latest selectable day as `YYYY-MM-DD`. */
  max?: string;
  /** 0 = Sunday, 1 = Monday. */
  weekStartsOn?: 0 | 1;
  /**
   * When set, the calendar popover matches this element’s width/left instead of
   * the trigger — useful when date sits beside another field.
   */
  popoverContainerRef?: RefObject<HTMLElement | null>;
  className?: string;
}

function CalendarIcon({ className, size = 18 }: { className?: string; size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 20 20"
      fill="none"
      className={className}
      aria-hidden
    >
      <rect
        x="3"
        y="4.5"
        width="14"
        height="12.5"
        rx="2.5"
        stroke="currentColor"
        strokeWidth="1.7"
      />
      <path
        d="M3 8.5h14M7 2.5v3M13 2.5v3"
        stroke="currentColor"
        strokeWidth="1.7"
        strokeLinecap="round"
      />
    </svg>
  );
}

function formatDisplay(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return "";
  const [year, month, day] = value.split("-");
  return `${day}/${month}/${year}`;
}

function startOfMonth(date: Date) {
  return new Date(date.getFullYear(), date.getMonth(), 1);
}

function addMonths(date: Date, count: number) {
  return new Date(date.getFullYear(), date.getMonth() + count, 1);
}

function monthKey(date: Date) {
  return `${date.getFullYear()}-${date.getMonth()}`;
}

function buildCells(month: Date, weekStartsOn: 0 | 1) {
  const first = startOfMonth(month);
  const firstWeekday = first.getDay();
  const offset = (firstWeekday - weekStartsOn + 7) % 7;
  const gridStart = new Date(first);
  gridStart.setDate(first.getDate() - offset);

  return Array.from({ length: 42 }, (_, index) => {
    const date = new Date(gridStart);
    date.setDate(gridStart.getDate() + index);
    return date;
  });
}

const WEEKDAYS_SUN = ["S", "M", "T", "W", "T", "F", "S"];
const WEEKDAYS_MON = ["M", "T", "W", "T", "F", "S", "S"];
const POPOVER_GAP = 8;
const VIEWPORT_PAD = 12;
/** 6 rows × 36px + 5 × 4px gaps */
const MONTH_PAGE_HEIGHT = 236;
const SCROLL_SETTLE_MS = 90;

function MonthGrid({
  month,
  value,
  todayKey,
  minKey,
  maxKey,
  weekStartsOn,
  onPick,
}: {
  month: Date;
  value: string;
  todayKey: string;
  minKey: string | null;
  maxKey: string | null;
  weekStartsOn: 0 | 1;
  onPick: (date: Date) => void;
}) {
  const cells = buildCells(month, weekStartsOn);

  return (
    <div
      className="grid h-[236px] snap-start snap-always grid-cols-7 content-start gap-1"
      aria-hidden={false}
    >
      {cells.map((date) => {
        const key = localDateKey(date);
        const inMonth = date.getMonth() === month.getMonth();
        const selectedDay = value === key;
        const isToday = key === todayKey;
        const disabled = Boolean(
          (minKey && key < minKey) || (maxKey && key > maxKey),
        );

        return (
          <button
            key={key}
            type="button"
            disabled={disabled}
            onClick={() => onPick(date)}
            className={cn(
              "flex h-9 items-center justify-center rounded-full text-[13px] transition-colors",
              !inMonth && "text-faint",
              inMonth && !selectedDay && "text-ink hover:bg-canvas",
              isToday && !selectedDay && "font-semibold text-green",
              selectedDay && "bg-green font-semibold text-white",
              disabled && "pointer-events-none opacity-35",
            )}
          >
            {date.getDate()}
          </button>
        );
      })}
    </div>
  );
}

/** Labeled date field with an in-app calendar popover. */
export function DateField({
  value,
  onChange,
  label,
  min,
  max,
  weekStartsOn = 0,
  popoverContainerRef,
  className,
}: DateFieldProps) {
  const labelId = useId();
  const rootRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const popoverRef = useRef<HTMLDivElement>(null);
  const scrollerRef = useRef<HTMLDivElement>(null);
  const settleTimer = useRef<number | null>(null);
  const ignoreScroll = useRef(false);
  const [open, setOpen] = useState(false);
  const [placement, setPlacement] = useState<{
    top: number;
    left: number;
    width: number;
  } | null>(null);
  const [visibleMonth, setVisibleMonth] = useState(() =>
    startOfMonth(
      value && /^\d{4}-\d{2}-\d{2}$/.test(value) ? parseLocalDate(value) : new Date(),
    ),
  );

  function jumpToMonth(next: Date) {
    setVisibleMonth((current) =>
      monthKey(current) === monthKey(next) ? current : startOfMonth(next),
    );
  }

  function syncMonthToValue() {
    const next =
      value && /^\d{4}-\d{2}-\d{2}$/.test(value)
        ? parseLocalDate(value)
        : new Date();
    jumpToMonth(next);
  }

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
      const containerRect =
        popoverContainerRef?.current?.getBoundingClientRect() ?? null;
      const popoverHeight = popover?.offsetHeight ?? 360;
      const spaceBelow = window.innerHeight - rect.bottom - VIEWPORT_PAD;
      const spaceAbove = rect.top - VIEWPORT_PAD;
      const openUp = spaceBelow < popoverHeight && spaceAbove > spaceBelow;

      const maxWidth = window.innerWidth - VIEWPORT_PAD * 2;
      const width = Math.min(containerRect?.width ?? rect.width, maxWidth);
      const preferredLeft = containerRect?.left ?? rect.left;
      const left = Math.min(
        Math.max(VIEWPORT_PAD, preferredLeft),
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
  }, [open, popoverContainerRef]);

  useLayoutEffect(() => {
    const scroller = scrollerRef.current;
    if (!open || !scroller) return;
    ignoreScroll.current = true;
    if (settleTimer.current != null) {
      window.clearTimeout(settleTimer.current);
      settleTimer.current = null;
    }
    scroller.scrollTop = MONTH_PAGE_HEIGHT;
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        ignoreScroll.current = false;
      });
    });
  }, [open, visibleMonth]);

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

  useEffect(() => {
    return () => {
      if (settleTimer.current != null) window.clearTimeout(settleTimer.current);
    };
  }, []);

  const todayKey = localDateKey(new Date());
  const minKey = min && /^\d{4}-\d{2}-\d{2}$/.test(min) ? min : null;
  const maxKey = max && /^\d{4}-\d{2}-\d{2}$/.test(max) ? max : null;
  const weekdays = weekStartsOn === 1 ? WEEKDAYS_MON : WEEKDAYS_SUN;
  const monthLabel = visibleMonth.toLocaleDateString(undefined, {
    month: "long",
    year: "numeric",
  });
  const months = [-1, 0, 1].map((offset) => addMonths(visibleMonth, offset));

  function settleFromScroll() {
    const scroller = scrollerRef.current;
    if (!scroller || ignoreScroll.current) return;
    const index = Math.round(scroller.scrollTop / MONTH_PAGE_HEIGHT);
    const delta = index - 1;
    if (delta === 0) return;
    setVisibleMonth((current) => addMonths(current, delta));
  }

  function onScrollerScroll() {
    if (ignoreScroll.current) return;
    if (settleTimer.current != null) window.clearTimeout(settleTimer.current);
    settleTimer.current = window.setTimeout(settleFromScroll, SCROLL_SETTLE_MS);
  }

  function goMonth(delta: -1 | 1) {
    const scroller = scrollerRef.current;
    if (!scroller || ignoreScroll.current) return;
    if (settleTimer.current != null) window.clearTimeout(settleTimer.current);
    scroller.scrollTo({
      top: MONTH_PAGE_HEIGHT * (1 + delta),
      behavior: "smooth",
    });
  }

  function pick(date: Date) {
    const key = localDateKey(date);
    if (minKey && key < minKey) return;
    if (maxKey && key > maxKey) return;
    onChange(key);
    setOpen(false);
  }

  function goToday() {
    const today = new Date();
    const key = localDateKey(today);
    if (minKey && key < minKey) {
      jumpToMonth(parseLocalDate(minKey));
      return;
    }
    if (maxKey && key > maxKey) {
      jumpToMonth(parseLocalDate(maxKey));
      return;
    }
    onChange(key);
    jumpToMonth(today);
    setOpen(false);
  }

  const calendar = open
    ? createPortal(
        <div
          ref={popoverRef}
          role="dialog"
          aria-label={typeof label === "string" ? label : "Choose date"}
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
          <div className="mb-3 flex items-center justify-between gap-2">
            <div
              key={monthKey(visibleMonth)}
              className="font-display text-[15px] font-semibold text-ink animate-[fade-up_0.22s_ease]"
            >
              {monthLabel}
            </div>
            <div className="flex items-center gap-0.5">
              <button
                type="button"
                aria-label="Previous month"
                onClick={() => goMonth(-1)}
                className="flex h-8 w-8 items-center justify-center rounded-lg text-muted transition-colors hover:bg-canvas hover:text-ink"
              >
                <ChevronIcon direction="up" size={14} />
              </button>
              <button
                type="button"
                aria-label="Next month"
                onClick={() => goMonth(1)}
                className="flex h-8 w-8 items-center justify-center rounded-lg text-muted transition-colors hover:bg-canvas hover:text-ink"
              >
                <ChevronIcon direction="down" size={14} />
              </button>
            </div>
          </div>

          <div className="mb-1.5 grid grid-cols-7 gap-1">
            {weekdays.map((day, index) => (
              <div
                key={`${day}-${index}`}
                className="py-1 text-center text-[11px] font-semibold text-muted"
              >
                {day}
              </div>
            ))}
          </div>

          <div
            ref={scrollerRef}
            onScroll={onScrollerScroll}
            onScrollEnd={settleFromScroll}
            className="h-[236px] touch-pan-y overflow-y-auto overscroll-contain snap-y snap-mandatory [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
          >
            {months.map((month) => (
              <MonthGrid
                key={monthKey(month)}
                month={month}
                value={value}
                todayKey={todayKey}
                minKey={minKey}
                maxKey={maxKey}
                weekStartsOn={weekStartsOn}
                onPick={pick}
              />
            ))}
          </div>

          <div className="mt-3 flex items-center justify-between border-t border-line-soft pt-3">
            <button
              type="button"
              onClick={() => {
                onChange("");
                setOpen(false);
              }}
              className="text-[13px] font-medium text-green"
            >
              Clear
            </button>
            <button
              type="button"
              onClick={goToday}
              className="text-[13px] font-medium text-green"
            >
              Today
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
        onClick={() => {
          if (open) {
            setOpen(false);
          } else {
            syncMonthToValue();
            setOpen(true);
          }
        }}
        className="flex w-full items-center justify-between rounded-xl border border-line bg-canvas px-3.5 py-[11px] text-left text-base text-ink outline-none transition-colors hover:border-green focus-visible:outline focus-visible:outline-[3px] focus-visible:outline-offset-2 focus-visible:outline-[rgba(31,157,99,0.28)]"
      >
        <span className={cn(!value && "text-faint")}>
          {formatDisplay(value) || "dd/mm/yyyy"}
        </span>
        <CalendarIcon className="text-muted" />
      </button>

      {calendar}
    </div>
  );
}
