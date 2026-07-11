import type { ReactNode } from "react";
import { cn } from "@/lib/cn";

/** Standard padded, animated content area for a web screen. */
export function WebScreen({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("animate-fade-up px-10 pb-12 pt-[34px]", className)}>
      {children}
    </div>
  );
}

/** Page heading with optional eyebrow, subtitle, and right-aligned action. */
export function PageHeader({
  title,
  eyebrow,
  subtitle,
  action,
  align = "end",
}: {
  title: string;
  eyebrow?: string;
  subtitle?: string;
  action?: ReactNode;
  align?: "end" | "center";
}) {
  return (
    <div
      className={cn(
        "mb-[22px] flex justify-between",
        align === "end" ? "items-end" : "items-center",
      )}
    >
      <div>
        {eyebrow ? (
          <div className="mb-1 text-sm text-muted">{eyebrow}</div>
        ) : null}
        <div className="font-display text-[28px] font-semibold text-ink">
          {title}
        </div>
        {subtitle ? (
          <div className="mt-1 text-[13px] text-muted">{subtitle}</div>
        ) : null}
      </div>
      {action}
    </div>
  );
}
