import type { ReactNode } from "react";
import { cn } from "@/lib/cn";

interface ModalProps {
  onClose: () => void;
  children: ReactNode;
  /** Panel width in pixels (design uses 420–460). */
  width?: number;
  title?: string;
  headerRight?: ReactNode;
  className?: string;
}

/** Web centered modal: dimmed backdrop + pop-in panel. */
export function Modal({
  onClose,
  children,
  width = 440,
  title,
  headerRight,
  className,
}: ModalProps) {
  return (
    <div
      role="presentation"
      onClick={onClose}
      className="absolute inset-0 z-30 flex animate-dim-in items-center justify-center bg-ink-deep/65 px-6"
    >
      <div
        role="dialog"
        aria-modal
        onClick={(e) => e.stopPropagation()}
        style={{ width }}
        className={cn(
          "max-w-full animate-pop-in rounded-[22px] border border-line bg-popup p-7 shadow-[0_24px_60px_rgba(0,0,0,0.35)]",
          className,
        )}
      >
        {title || headerRight ? (
          <div className="mb-5 flex items-center justify-between gap-3">
            {title ? (
              <h2 className="font-display text-[19px] font-semibold text-ink">
                {title}
              </h2>
            ) : (
              <span />
            )}
            {headerRight}
          </div>
        ) : null}
        {children}
      </div>
    </div>
  );
}
