import { cn } from "@/lib/cn";
import { ProgressBar, type ProgressTone } from "@/components/ui/ProgressBar";

interface CategoryBarProps {
  label: string;
  caption?: string;
  value: number;
  tone?: ProgressTone;
  height?: number;
  onClick?: () => void;
  className?: string;
}

/** Label + caption header above a progress bar (overview, stats, budgets). */
export function CategoryBar({
  label,
  caption,
  value,
  tone = "green",
  height = 6,
  onClick,
  className,
}: CategoryBarProps) {
  const content = (
    <>
      <div className="mb-1.5 flex items-baseline justify-between">
        <span className="text-[13px] font-medium text-ink">{label}</span>
        {caption ? (
          <span className={cn("text-xs text-muted")}>{caption}</span>
        ) : null}
      </div>
      <ProgressBar value={value} tone={tone} height={height} />
    </>
  );

  return onClick ? (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "block w-full rounded-lg text-left outline-none focus-visible:ring-2 focus-visible:ring-green/20",
        className,
      )}
    >
      {content}
    </button>
  ) : (
    <div className={className}>{content}</div>
  );
}
