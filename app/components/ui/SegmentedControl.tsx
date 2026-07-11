import { cn } from "@/lib/cn";

export interface SegmentOption<T extends string> {
  value: T;
  label: string;
}

interface SegmentedControlProps<T extends string> {
  options: SegmentOption<T>[];
  value: T;
  onChange: (value: T) => void;
  /** Stretch segments to fill the track (mobile) vs hug content (web). */
  fill?: boolean;
  className?: string;
}

/** Pill-shaped segmented toggle used for ranges and preference options. */
export function SegmentedControl<T extends string>({
  options,
  value,
  onChange,
  fill = true,
  className,
}: SegmentedControlProps<T>) {
  return (
    <div
      className={cn(
        "flex gap-0.5 rounded-full bg-canvas-deep p-[3px]",
        className,
      )}
    >
      {options.map((option) => {
        const active = option.value === value;
        return (
          <button
            key={option.value}
            type="button"
            onClick={() => onChange(option.value)}
            className={cn(
              "rounded-full text-center text-xs transition-colors",
              fill ? "flex-1 px-0 py-[7px]" : "px-3.5 py-1.5",
              active
                ? "bg-ink font-semibold text-canvas"
                : "font-medium text-muted",
            )}
          >
            {option.label}
          </button>
        );
      })}
    </div>
  );
}
