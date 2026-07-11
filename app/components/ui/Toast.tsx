import { cn } from "@/lib/cn";

interface ToastProps {
  message: string;
  /** Vertical offset from the top of the container. */
  top?: number;
  withShadow?: boolean;
}

/** The floating confirmation pill. Positioning is centered horizontally. */
export function Toast({ message, top = 64, withShadow = false }: ToastProps) {
  return (
    <div
      role="status"
      style={{ top }}
      className={cn(
        "absolute left-1/2 z-40 -translate-x-1/2 animate-toast-in whitespace-nowrap rounded-full bg-ink px-[18px] py-[9px] text-[13px] text-side-text",
        withShadow && "shadow-[0_12px_30px_-10px_rgba(13,21,18,0.5)]",
      )}
    >
      {message}
    </div>
  );
}
