import { cn } from "@/lib/cn";

interface IconProps {
  className?: string;
  size?: number;
}

export function PlusIcon({ className, size = 20 }: IconProps) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 20 20"
      fill="none"
      className={className}
      aria-hidden
    >
      <path
        d="M10 3v14M3 10h14"
        stroke="currentColor"
        strokeWidth={2.4}
        strokeLinecap="round"
      />
    </svg>
  );
}

export function SearchIcon({ className, size = 16 }: IconProps) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 16 16"
      fill="none"
      className={className}
      aria-hidden
    >
      <circle cx="7" cy="7" r="5" stroke="currentColor" strokeWidth={2} />
      <path
        d="M11 11l3.5 3.5"
        stroke="currentColor"
        strokeWidth={2}
        strokeLinecap="round"
      />
    </svg>
  );
}

export function TrashIcon({ className, size = 18 }: IconProps) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 20 20"
      fill="none"
      className={className}
      aria-hidden
    >
      <path
        d="M3.5 5.5h13M8 5.5V4a1 1 0 011-1h2a1 1 0 011 1v1.5M5.5 5.5l.8 10.5a1.5 1.5 0 001.5 1.4h4.4a1.5 1.5 0 001.5-1.4l.8-10.5"
        stroke="currentColor"
        strokeWidth={1.6}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

type ChevronDirection = "left" | "right" | "up" | "down";

const CHEVRON_ROTATION: Record<ChevronDirection, string> = {
  left: "rotate-180",
  right: "rotate-0",
  up: "-rotate-90",
  down: "rotate-90",
};

export function ChevronIcon({
  className,
  size = 14,
  direction = "right",
}: IconProps & { direction?: ChevronDirection }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 14 14"
      fill="none"
      className={cn(CHEVRON_ROTATION[direction], className)}
      aria-hidden
    >
      <path
        d="M5 2l5 5-5 5"
        stroke="currentColor"
        strokeWidth={2}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

/**
 * The abstract nav/tab glyph from the design — a bordered square or circle
 * whose colour communicates the active state.
 */
export function NavGlyph({
  round = false,
  size = 22,
  className,
}: {
  round?: boolean;
  size?: number;
  className?: string;
}) {
  return (
    <span
      className={cn(
        "box-border border-2",
        round ? "rounded-full" : "rounded-md",
        className,
      )}
      style={{ width: size, height: size }}
    />
  );
}
