"use client";

import { useRef } from "react";
import { cn } from "@/lib/cn";
import { lastGrapheme } from "@/lib/emoji";

interface EmojiFieldProps {
  value: string;
  onChange: (emoji: string) => void;
  className?: string;
  /** Accessible label for the control. */
  "aria-label"?: string;
}

/**
 * Square control that uses the platform text field so the OS emoji keyboard /
 * system emoji picker can be used — no custom emoji grid.
 */
export function EmojiField({
  value,
  onChange,
  className,
  "aria-label": ariaLabel = "Category emoji",
}: EmojiFieldProps) {
  const inputRef = useRef<HTMLInputElement>(null);

  return (
    <div className={cn("relative shrink-0", className)}>
      <input
        ref={inputRef}
        type="text"
        value={value}
        aria-label={ariaLabel}
        autoComplete="off"
        autoCorrect="off"
        spellCheck={false}
        enterKeyHint="done"
        onFocus={(e) => e.currentTarget.select()}
        onChange={(e) => {
          const next = lastGrapheme(e.target.value);
          if (next) onChange(next);
        }}
        className="flex h-[46px] w-[46px] cursor-pointer items-center justify-center rounded-xl border border-line bg-canvas text-center text-[22px] leading-none text-ink outline-none caret-transparent selection:bg-transparent"
      />
    </div>
  );
}
