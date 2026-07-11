import type { ReactNode } from "react";
import { cn } from "@/lib/cn";

export type ButtonVariant = "primary" | "secondary" | "danger" | "accent";
export type ButtonSize = "md" | "sm";

interface ButtonProps {
  children: ReactNode;
  onClick?: () => void;
  variant?: ButtonVariant;
  size?: ButtonSize;
  /** Primary/save buttons render greyed-out and inert when false. */
  enabled?: boolean;
  fullWidth?: boolean;
  leftIcon?: ReactNode;
  className?: string;
}

const VARIANT_CLASSES: Record<ButtonVariant, string> = {
  primary: "bg-green text-white",
  secondary: "border border-hairline bg-surface text-ink hover:bg-canvas",
  danger: "border border-danger-line bg-danger-soft text-danger",
  accent: "bg-green text-white hover:bg-green-deep",
};

const SIZE_CLASSES: Record<ButtonSize, string> = {
  md: "px-4 py-3.5 text-[15px]",
  sm: "px-[18px] py-[11px] text-sm",
};

export function Button({
  children,
  onClick,
  variant = "primary",
  size = "md",
  enabled = true,
  fullWidth = false,
  leftIcon,
  className,
}: ButtonProps) {
  const disabled = (variant === "primary" || variant === "accent") && !enabled;

  return (
    <button
      type="button"
      onClick={onClick}
      aria-disabled={disabled}
      className={cn(
        "inline-flex items-center justify-center gap-2 rounded-xl text-center font-semibold transition-colors",
        SIZE_CLASSES[size],
        disabled
          ? "pointer-events-none bg-canvas-deep text-faint"
          : VARIANT_CLASSES[variant],
        fullWidth && "w-full",
        className,
      )}
    >
      {leftIcon}
      {children}
    </button>
  );
}
