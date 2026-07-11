import { cn } from "@/lib/cn";

interface AvatarProps {
  initial: string;
  size?: number;
  radius?: number;
  /** Light tint for canvas backgrounds, dark for the sidebar. */
  tone?: "light" | "dark";
  textClassName?: string;
  onClick?: () => void;
  className?: string;
}

/** Square monogram avatar. */
export function Avatar({
  initial,
  size = 40,
  radius = 13,
  tone = "light",
  textClassName = "text-base",
  onClick,
  className,
}: AvatarProps) {
  const content = (
    <span className={cn("font-display font-semibold", textClassName)}>
      {initial}
    </span>
  );
  const classes = cn(
    "flex items-center justify-center",
    tone === "light" ? "bg-green-soft text-green" : "bg-side-avatar text-green-bright",
    className,
  );
  const style = { width: size, height: size, borderRadius: radius };

  if (onClick) {
    return (
      <button type="button" onClick={onClick} className={classes} style={style}>
        {content}
      </button>
    );
  }
  return (
    <span className={classes} style={style}>
      {content}
    </span>
  );
}
