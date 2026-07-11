import type { ReactNode } from "react";
import { cn } from "@/lib/cn";

interface TextFieldProps {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  label?: ReactNode;
  inputMode?: "text" | "numeric" | "decimal";
  type?: "text" | "date" | "email";
  min?: string;
  autoFocus?: boolean;
  className?: string;
}

/** Labeled text input with the design's soft-canvas fill. */
export function TextField({
  value,
  onChange,
  placeholder,
  label,
  inputMode = "text",
  type = "text",
  min,
  autoFocus,
  className,
}: TextFieldProps) {
  return (
    <label className={cn("block", className)}>
      {label ? (
        <span className="mb-1.5 block text-xs text-muted">{label}</span>
      ) : null}
      <input
        type={type}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        inputMode={inputMode}
        min={min}
        autoFocus={autoFocus}
        className="w-full rounded-xl border border-line bg-canvas px-3.5 py-[11px] text-base text-ink outline-none placeholder:text-faint"
      />
    </label>
  );
}
