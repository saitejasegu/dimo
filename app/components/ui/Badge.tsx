import { cn } from "@/lib/cn";

export type BadgeTone = "green" | "muted" | "danger";

const TONE_CLASSES: Record<BadgeTone, string> = {
  green: "bg-green-soft text-green",
  muted: "bg-canvas-deep text-muted",
  danger: "bg-danger-soft text-danger",
};

/** Small status pill: Active / Paused, budget percentage, etc. */
export function Badge({
  label,
  tone = "muted",
  className,
}: {
  label: string;
  tone?: BadgeTone;
  className?: string;
}) {
  return (
    <span
      className={cn(
        "shrink-0 rounded-full px-2.5 py-[3px] text-[11px] font-medium",
        TONE_CLASSES[tone],
        className,
      )}
    >
      {label}
    </span>
  );
}
