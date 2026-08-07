"use client";

import { ChevronIcon } from "@/components/ui/icons";
import { cn } from "@/lib/cn";

interface StatsPeriodNavProps {
  /** 0 is the current period; negative values step back. */
  offset: number;
  label: string;
  /** False at the start of history, so "previous" stops rather than paging into empty periods. */
  canGoBack: boolean;
  onChange: (offset: number) => void;
  className?: string;
}

const STEP_CLASSES =
  "flex h-8 w-8 items-center justify-center rounded-lg text-muted transition-colors hover:bg-canvas hover:text-ink disabled:pointer-events-none disabled:opacity-35";

export function StatsPeriodNav({
  offset,
  label,
  canGoBack,
  onChange,
  className,
}: StatsPeriodNavProps) {
  const isCurrent = offset === 0;

  return (
    <div
      className={cn(
        "flex items-center justify-between gap-2 rounded-xl border border-line bg-surface px-3 py-2",
        className,
      )}
    >
      <button
        type="button"
        aria-label="Previous period"
        disabled={!canGoBack}
        onClick={() => onChange(offset - 1)}
        className={STEP_CLASSES}
      >
        <ChevronIcon direction="left" size={14} />
      </button>

      <button
        type="button"
        // Doubles as the "back to current" affordance once you've paged away.
        disabled={isCurrent}
        aria-label={isCurrent ? undefined : "Back to the current period"}
        onClick={() => onChange(0)}
        className={cn(
          "font-display text-[15px] font-semibold text-ink transition-colors",
          isCurrent ? "cursor-default" : "hover:text-green",
        )}
      >
        {label}
      </button>

      <button
        type="button"
        aria-label="Next period"
        disabled={isCurrent}
        onClick={() => onChange(offset + 1)}
        className={STEP_CLASSES}
      >
        <ChevronIcon direction="right" size={14} />
      </button>
    </div>
  );
}
