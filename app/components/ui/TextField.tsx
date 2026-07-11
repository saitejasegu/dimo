import type { ReactNode } from "react";
import { cn } from "@/lib/cn";

interface TextFieldProps {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  label?: ReactNode;
  inputMode?: "text" | "numeric" | "decimal";
  type?: "text" | "email";
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
        autoFocus={autoFocus}
        className="w-full rounded-xl border border-line bg-canvas px-3.5 py-[11px] text-base text-ink outline-none placeholder:text-faint"
      />
    </label>
  );
}
