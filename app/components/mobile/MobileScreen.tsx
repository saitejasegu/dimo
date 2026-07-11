import type { ReactNode } from "react";
import { cn } from "@/lib/cn";

/** Standard scrollable screen body for the mobile app. */
export function MobileScreen({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div
      className={cn(
        "h-full animate-fade-up overflow-auto px-[22px] pb-[110px] pt-[max(1.25rem,env(safe-area-inset-top))]",
        className,
      )}
    >
      {children}
    </div>
  );
}

/** Small section heading with an optional "See all" action. */
export function SectionHeader({
  title,
  actionLabel,
  onAction,
}: {
  title: string;
  actionLabel?: string;
  onAction?: () => void;
}) {
  return (
    <div className="mb-2.5 flex items-baseline justify-between">
      <span className="font-display text-base font-semibold text-ink">
        {title}
      </span>
      {actionLabel && onAction ? (
        <button
          type="button"
          onClick={onAction}
          className="text-[13px] font-medium text-green"
        >
          {actionLabel}
        </button>
      ) : null}
    </div>
  );
}
