import { cn } from "@/lib/cn";

interface ToastProps {
  message: string;
  /** Vertical offset from the bottom of the viewport in px. Omit for tab-bar clearance. */
  bottom?: number;
  withShadow?: boolean;
}

/** The floating confirmation pill, centered near the bottom of the viewport. */
export function Toast({ message, bottom, withShadow = false }: ToastProps) {
  return (
    <div
      role="status"
      style={bottom != null ? { bottom } : undefined}
      className={cn(
        "fixed left-1/2 z-40 max-w-[calc(100vw-2rem)] -translate-x-1/2 animate-toast-in rounded-full bg-inverse px-[18px] py-[9px] text-center text-[13px] text-side-text",
        bottom == null &&
          "bottom-[calc(4.25rem+env(safe-area-inset-bottom,0px))]",
        withShadow && "shadow-[0_12px_30px_-10px_rgba(13,21,18,0.5)]",
      )}
    >
      {message}
    </div>
  );
}
