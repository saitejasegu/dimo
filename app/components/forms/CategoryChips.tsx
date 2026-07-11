import type { CategoryName } from "@/lib/types";
import { cn } from "@/lib/cn";
import { useAppActions, useAppState } from "@/store/app-store";
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
  const { categories: categoryEntities } = useAppState();
  const { openOverlay } = useAppActions();
  const emojiByName = new Map(categoryEntities.map((c) => [c.name, c.emoji]));

  return (
    <div className={cn("flex min-w-0 items-center gap-2", className)}>
      <div className="flex min-w-0 flex-1 flex-nowrap gap-2 overflow-x-auto overflow-y-hidden overscroll-x-contain [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
        {categories.map((category) => {
          const emoji = emojiByName.get(category);
          return (
            <Chip
              key={category}
              label={emoji ? `${emoji} ${category}` : category}
              selected={value === category}
              surface={surface}
              onClick={() => onChange(category)}
            />
          );
        })}
      </div>
      <div
        aria-hidden
        className="h-5 w-px shrink-0 bg-hairline"
      />
      <Chip
        label="+ Add"
        surface={surface}
        onClick={() => openOverlay("category")}
      />
    </div>
  );
}
