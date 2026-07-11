import { cn } from "@/lib/cn";

interface ChipProps {
  label: string;
  selected?: boolean;
  onClick?: () => void;
  /** Background of the unselected state (matches differing design contexts). */
  surface?: "white" | "canvas";
  className?: string;
}

/** Rounded pill used for category filters and pickers. */
export function Chip({
  label,
  selected,
  onClick,
  surface = "white",
  className,
}: ChipProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "shrink-0 whitespace-nowrap rounded-full px-3.5 py-[7px] text-[13px] transition-colors",
        selected
          ? "bg-ink font-medium text-white"
          : cn(
              "border border-line text-body",
              surface === "white" ? "bg-surface" : "bg-canvas",
            ),
        className,
      )}
    >
      {label}
    </button>
  );
}
