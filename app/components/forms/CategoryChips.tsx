import type { CategoryName } from "@/lib/types";
import { cn } from "@/lib/cn";
import { Chip } from "@/components/ui/Chip";

/** A horizontally scrollable row of single-select category chips. */
export function CategoryChips({
  categories,
  value,
  onChange,
  surface = "canvas",
  className,
}: {
  categories: CategoryName[];
  value: CategoryName;
  onChange: (category: CategoryName) => void;
  surface?: "white" | "canvas";
  className?: string;
}) {
  return (
    <div
      className={cn(
        "flex flex-nowrap gap-2 overflow-x-auto overflow-y-hidden overscroll-x-contain [scrollbar-width:none] [&::-webkit-scrollbar]:hidden",
        className,
      )}
    >
      {categories.map((category) => (
        <Chip
          key={category}
          label={category}
          selected={value === category}
          surface={surface}
          onClick={() => onChange(category)}
        />
      ))}
    </div>
  );
}
