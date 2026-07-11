import { cn } from "@/lib/cn";

interface CategoryTintProps {
  /** Green accent vs neutral fill. */
  green?: boolean;
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
  size = 38,
  radius = 11,
  className,
}: CategoryTintProps) {
  return (
    <span
      className={cn("shrink-0", green ? "bg-green-soft" : "bg-canvas-deep", className)}
      style={{ width: size, height: size, borderRadius: radius }}
    />
  );
}
