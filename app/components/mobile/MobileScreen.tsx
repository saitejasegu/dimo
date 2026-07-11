import type { ReactNode } from "react";
import { cn } from "@/lib/cn";

/** Fixed-height title row shared by every mobile screen. */
export function MobileTopBar({
  title,
  subtitle,
  trailing,
  className,
}: {
  title: ReactNode;
  subtitle?: ReactNode;
  trailing?: ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("flex min-h-14 items-center justify-between gap-3", className)}>
      <div className="min-w-0 flex-1">
        {subtitle ? (
          <>
            <div className="text-[13px] leading-5 text-muted">{subtitle}</div>
            <div className="overflow-hidden text-ellipsis whitespace-nowrap font-display text-[22px] font-semibold leading-8 text-ink">
              {title}
            </div>
          </>
        ) : (
          <h1 className="overflow-hidden text-ellipsis whitespace-nowrap font-display text-2xl font-semibold leading-9 text-ink">
            {title}
          </h1>
        )}
      </div>
      {trailing ? <div className="flex shrink-0 items-center">{trailing}</div> : null}
    </div>
  );
}

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
        <div className="shrink-0 bg-canvas px-[22px] pb-3.5 pt-[max(1.75rem,calc(env(safe-area-inset-top)+0.75rem))]">
          {header}
        </div>
      ) : (
        <div className="shrink-0 pt-[max(1.75rem,calc(env(safe-area-inset-top)+0.75rem))]" />
      )}
      <div
        className={cn(
          "bubble-scrollbar min-h-0 flex-1 overflow-y-auto overscroll-none px-[22px] pb-[calc(7.25rem+env(safe-area-inset-bottom,0px))] pt-4",
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
          className="text-[13px] font-medium !text-muted"
        >
          {actionLabel}
        </button>
      ) : null}
    </div>
  );
}
