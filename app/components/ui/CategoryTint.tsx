"use client";

import { cn } from "@/lib/cn";
import { DEFAULT_CATEGORY_EMOJI } from "@/data/model";

interface CategoryTintProps {
  /** Green accent vs neutral fill. */
  green?: boolean;
  /** Optional category emoji shown inside the swatch. */
  emoji?: string;
  size?: number;
  radius?: number;
  className?: string;
}

/**
 * The small rounded-square colour swatch that stands in for a merchant/category
 * icon throughout the lists.
 */
export function CategoryTint({
  green,
  emoji = DEFAULT_CATEGORY_EMOJI,
  size = 38,
  radius = 11,
  className,
}: CategoryTintProps) {
  return (
    <span
      className={cn(
        "inline-flex shrink-0 items-center justify-center text-[17px] leading-none",
        green ? "bg-green-soft" : "bg-canvas-deep",
        className,
      )}
      style={{ width: size, height: size, borderRadius: radius }}
      aria-hidden
    >
      {emoji}
    </span>
  );
}
