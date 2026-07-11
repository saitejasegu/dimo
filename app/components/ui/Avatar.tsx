import { cn } from "@/lib/cn";

interface AvatarProps {
  initial: string;
  src?: string | null;
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
  src,
  size = 40,
  radius = 13,
  tone = "light",
  textClassName = "text-base",
  onClick,
  className,
}: AvatarProps) {
  const content = src ? (
    // WorkOS normalizes and supplies the provider-hosted profile photo URL.
    // eslint-disable-next-line @next/next/no-img-element
    <img src={src} alt="" className="h-full w-full object-cover" />
  ) : (
    <span className={cn("font-display font-semibold", textClassName)}>
      {initial}
    </span>
  );
  const classes = cn(
    "flex items-center justify-center overflow-hidden",
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
