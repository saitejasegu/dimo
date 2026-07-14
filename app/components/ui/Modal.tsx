import type { ReactNode } from "react";
import { cn } from "@/lib/cn";

interface ModalProps {
  onClose: () => void;
  children: ReactNode;
  /** Panel width in pixels (design uses 420–460). */
  width?: number;
  title?: string;
  headerRight?: ReactNode;
  titleAlignment?: "leading" | "center";
  className?: string;
}

/** Web centered modal: dimmed backdrop + pop-in panel. */
export function Modal({
  onClose,
  children,
  width = 440,
  title,
  headerRight,
  titleAlignment = "leading",
  className,
}: ModalProps) {
  return (
    <div
      role="presentation"
      onClick={onClose}
      className="fixed inset-0 z-40 flex animate-dim-in items-center justify-center bg-ink-deep/65 px-6"
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
          <div
            className={cn(
              "mb-5 flex items-center gap-3",
              titleAlignment === "center" ? "relative justify-center" : "justify-between",
            )}
          >
            {title ? (
              <h2
                className={cn(
                  "font-display text-[19px] font-semibold text-ink",
                  titleAlignment === "center" && "px-12 text-center",
                )}
              >
                {title}
              </h2>
            ) : (
              <span />
            )}
            {headerRight ? (
              <div className={cn(titleAlignment === "center" && "absolute right-0")}>
                {headerRight}
              </div>
            ) : null}
          </div>
        ) : null}
        {children}
      </div>
    </div>
  );
}
