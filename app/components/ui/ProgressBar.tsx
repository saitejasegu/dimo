import { cn } from "@/lib/cn";

export type ProgressTone = "green" | "soft" | "danger";

const FILL_TONE: Record<ProgressTone, string> = {
  green: "bg-green",
  soft: "bg-bar-soft",
  danger: "bg-warn",
};

interface ProgressBarProps {
  /** Fill width as a percentage (0–100). */
  value: number;
  tone?: ProgressTone;
  /** Track height in pixels. */
  height?: number;
  /** Use a translucent track for placement on dark hero cards. */
  onDark?: boolean;
  className?: string;
}

export function ProgressBar({
  value,
  tone = "green",
  height = 6,
  onDark = false,
  className,
}: ProgressBarProps) {
  return (
    <div
      className={cn(
        "overflow-hidden rounded-full",
        onDark ? "bg-side-text/15" : "bg-canvas-deep",
        className,
      )}
      style={{ height }}
    >
      <div
        className={cn("h-full rounded-full", FILL_TONE[tone])}
        style={{ width: `${Math.max(0, Math.min(100, value))}%` }}
      />
    </div>
  );
}
