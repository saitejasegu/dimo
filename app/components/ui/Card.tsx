import type { ReactNode } from "react";
import { cn } from "@/lib/cn";

interface CardProps {
  children: ReactNode;
  className?: string;
  /** Renders as a button and applies the hover accent border. */
  onClick?: () => void;
  interactive?: boolean;
}

/**
 * The white surface card used across screens. When `onClick` is provided it
 * becomes a button and gains the green hover border from the design.
 */
export function Card({ children, className, onClick, interactive }: CardProps) {
  const base = cn(
    "rounded-2xl border border-line bg-surface",
    (onClick || interactive) &&
      "cursor-pointer text-left transition-colors hover:border-green",
    className,
  );

  if (onClick) {
    return (
      <button type="button" onClick={onClick} className={cn("block w-full", base)}>
        {children}
      </button>
    );
  }

  return <div className={base}>{children}</div>;
}

/** Dark hero card (spend summaries). */
export function HeroCard({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("rounded-[20px] bg-ink text-side-text", className)}>
      {children}
    </div>
  );
}
