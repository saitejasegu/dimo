import type { ReactNode } from "react";
import { cn } from "@/lib/cn";

/** Fixed header + independently scrollable body for the mobile app. */
export function MobileScreen({
  header,
  children,
  className,
}: {
  header?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className="flex h-full flex-col overflow-hidden">
      {header ? (
        <div className="shrink-0 bg-canvas px-[22px] pb-3.5 pt-[max(1.25rem,env(safe-area-inset-top))]">
          {header}
        </div>
      ) : (
        <div className="shrink-0 pt-[max(1.25rem,env(safe-area-inset-top))]" />
      )}
      <div
        className={cn(
          "bubble-scrollbar min-h-0 flex-1 animate-fade-up overflow-y-auto overscroll-none px-[22px] pb-[110px] pt-4",
          className,
        )}
      >
        {children}
      </div>
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
          className="text-[13px] font-medium !text-green"
        >
          {actionLabel}
        </button>
      ) : null}
    </div>
  );
}
