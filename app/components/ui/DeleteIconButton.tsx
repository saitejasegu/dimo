import { cn } from "@/lib/cn";
import { TrashIcon } from "@/components/ui/icons";

interface DeleteIconButtonProps {
  onClick: () => void;
  "aria-label": string;
  className?: string;
}

/** Compact header delete control — quiet by default, danger on hover. */
export function DeleteIconButton({
  onClick,
  "aria-label": ariaLabel,
  className,
}: DeleteIconButtonProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={ariaLabel}
      className={cn(
        "flex h-9 w-9 shrink-0 items-center justify-center rounded-xl border border-danger-line bg-danger-soft text-danger transition-colors",
        "hover:bg-danger-line",
        className,
      )}
    >
      <TrashIcon />
    </button>
  );
}
