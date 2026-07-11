import type { CategoryName } from "@/lib/types";
import { Chip } from "@/components/ui/Chip";

/** A wrapping row of single-select category chips. */
export function CategoryChips({
  categories,
  value,
  onChange,
  surface = "canvas",
  className = "flex flex-wrap gap-2",
}: {
  categories: CategoryName[];
  value: CategoryName;
  onChange: (category: CategoryName) => void;
  surface?: "white" | "canvas";
  className?: string;
}) {
  return (
    <div className={className}>
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
