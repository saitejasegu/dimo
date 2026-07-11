import type { ReactNode } from "react";
import { cn } from "@/lib/cn";

interface ModalProps {
  onClose: () => void;
  children: ReactNode;
  /** Panel width in pixels (design uses 420–460). */
  width?: number;
  title?: string;
  className?: string;
}

/** Web centered modal: dimmed backdrop + pop-in panel. */
export function Modal({ onClose, children, width = 440, title, className }: ModalProps) {
  return (
    <div
      role="presentation"
      onClick={onClose}
      className="absolute inset-0 z-30 flex animate-dim-in items-center justify-center bg-ink-deep/50 px-6"
    >
      <div
        role="dialog"
        aria-modal
        onClick={(e) => e.stopPropagation()}
        style={{ width }}
        className={cn(
          "max-w-full animate-pop-in rounded-[22px] bg-surface p-7",
          className,
        )}
      >
        {title ? (
          <h2 className="mb-5 font-display text-[19px] font-semibold text-ink">
            {title}
          </h2>
        ) : null}
        {children}
      </div>
    </div>
  );
}
