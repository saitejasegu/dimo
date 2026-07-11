"use client";

import { cn } from "@/lib/cn";

interface SliderProps {
  value: number;
  min?: number;
  max?: number;
  step?: number;
  onChange: (value: number) => void;
  onCommit?: (value: number) => void;
  label?: string;
  valueLabel?: string;
  className?: string;
}

/** Labeled range control used for continuous preferences like opacity. */
export function Slider({
  value,
  min = 0,
  max = 100,
  step = 1,
  onChange,
  onCommit,
  label,
  valueLabel,
  className,
}: SliderProps) {
  return (
    <label className={cn("block", className)}>
      {label || valueLabel ? (
        <span className="mb-2 flex items-baseline justify-between gap-3">
          {label ? <span className="text-[13px] font-medium text-ink">{label}</span> : <span />}
          {valueLabel ? <span className="text-xs tabular-nums text-muted">{valueLabel}</span> : null}
        </span>
      ) : null}
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        aria-valuemin={min}
        aria-valuemax={max}
        aria-valuenow={value}
        onChange={(event) => onChange(Number(event.target.value))}
        onMouseUp={(event) => onCommit?.(Number((event.target as HTMLInputElement).value))}
        onTouchEnd={(event) => onCommit?.(Number((event.target as HTMLInputElement).value))}
        onKeyUp={(event) => {
          if (event.key === "ArrowLeft" || event.key === "ArrowRight" || event.key === "Home" || event.key === "End") {
            onCommit?.(Number((event.target as HTMLInputElement).value));
          }
        }}
        className="nav-opacity-slider w-full"
      />
    </label>
  );
}
