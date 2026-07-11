import type { ReactNode } from "react";
import { cn } from "@/lib/cn";

interface SheetProps {
  onClose: () => void;
  title?: string;
  children: ReactNode;
  className?: string;
}

/** Mobile bottom sheet: dimmed backdrop + upward-sliding panel with a handle. */
export function Sheet({ onClose, title, children, className }: SheetProps) {
  return (
    <>
      <button
        type="button"
        aria-label="Close"
        onClick={onClose}
        className="absolute inset-0 z-30 animate-dim-in bg-ink-deep/45"
      />
      <div
        role="dialog"
        aria-modal
        className={cn(
          "absolute inset-x-0 bottom-0 z-[31] animate-sheet-up rounded-t-[28px] bg-surface px-6 pb-9 pt-3.5",
          className,
        )}
      >
        <div className="mx-auto mb-4 h-1 w-10 rounded-full bg-hairline" />
        {title ? (
          <h2 className="mb-4 font-display text-lg font-semibold text-ink">
            {title}
          </h2>
        ) : null}
        {children}
      </div>
    </>
  );
}
