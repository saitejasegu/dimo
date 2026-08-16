import { cn } from "@/lib/cn";
import { ArchiveIcon } from "@/components/ui/icons";

interface ArchiveIconButtonProps {
  archived: boolean;
  onClick: () => void;
  className?: string;
}

/** Compact header archive/restore control, paired with delete. */
export function ArchiveIconButton({
  archived,
  onClick,
  className,
}: ArchiveIconButtonProps) {
  const label = archived ? "Restore category" : "Archive category";
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label}
      title={label}
      className={cn(
        "flex h-9 w-9 shrink-0 items-center justify-center rounded-xl border transition-colors",
        archived
          ? "border-green/30 bg-green-soft text-green-deep hover:bg-green/15"
          : "border-line bg-canvas text-muted hover:bg-canvas-deep hover:text-ink",
        className,
      )}
    >
      <ArchiveIcon />
    </button>
  );
}
