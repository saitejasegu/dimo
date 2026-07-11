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

export function FilterIcon({ className, size = 18 }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 20 20" fill="none" className={className} aria-hidden>
      <path d="M3 5h14M6 10h8M8.5 15h3" stroke="currentColor" strokeWidth={2} strokeLinecap="round" />
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
 * Outline nav icons — same stroke language as Plus/Search (round caps, currentColor).
 */
export function SparklesIcon({ className, size = 22 }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 22 22" fill="none" className={className} aria-hidden>
      <path
        d="M11 3.5 12.2 8.3 17 9.5l-4.8 1.2L11 15.5l-1.2-4.8L5 9.5l4.8-1.2L11 3.5Z"
        stroke="currentColor"
        strokeWidth={1.8}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <path
        d="M16.5 14.2 17.1 16.4 19.3 17l-2.2.6-.6 2.2-.6-2.2-2.2-.6 2.2-.6.6-2.2ZM5.8 13.5l.4 1.5 1.5.4-1.5.4-.4 1.5-.4-1.5-1.5-.4 1.5-.4.4-1.5Z"
        stroke="currentColor"
        strokeWidth={1.6}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export function HomeIcon({ className, size = 22 }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 22 22" fill="none" className={className} aria-hidden>
      <path
        d="M3.5 9.5 11 3.5l7.5 6M5.5 8.8v8.2a1 1 0 0 0 1 1h2.7v-4.2h3.6v4.2h2.7a1 1 0 0 0 1-1V8.8"
        stroke="currentColor"
        strokeWidth={1.8}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export function StatsIcon({ className, size = 22 }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 22 22" fill="none" className={className} aria-hidden>
      <path
        d="M5 16.5V10M11 16.5V5.5M17 16.5v-8"
        stroke="currentColor"
        strokeWidth={1.8}
        strokeLinecap="round"
      />
    </svg>
  );
}

export function RecurringIcon({ className, size = 22 }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 22 22" fill="none" className={className} aria-hidden>
      <path
        d="M16.8 8.2A6.2 6.2 0 0 0 5.5 9.2M5.2 13.8a6.2 6.2 0 0 0 11.3-1"
        stroke="currentColor"
        strokeWidth={1.8}
        strokeLinecap="round"
      />
      <path
        d="M16.8 4.8v3.6h-3.6M5.2 17.2v-3.6h3.6"
        stroke="currentColor"
        strokeWidth={1.8}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export function BudgetsIcon({ className, size = 22 }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 22 22" fill="none" className={className} aria-hidden>
      <circle cx="11" cy="11" r="7" stroke="currentColor" strokeWidth={1.8} />
      <path
        d="M11 11V5.5A5.5 5.5 0 0 1 16 9.8"
        stroke="currentColor"
        strokeWidth={1.8}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export function SettingsIcon({ className, size = 22 }: IconProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 22 22" fill="none" className={className} aria-hidden>
      <circle cx="11" cy="11" r="2.6" stroke="currentColor" strokeWidth={1.8} />
      <path
        d="M9.6 3.8h2.8l.4 1.6 1.5.6 1.5-1 2 2-1 1.5.6 1.5 1.6.4v2.8l-1.6.4-.6 1.5 1 1.5-2 2-1.5-1-1.5.6-.4 1.6H9.6l-.4-1.6-1.5-.6-1.5 1-2-2 1-1.5-.6-1.5L3.8 12.4V9.6l1.6-.4.6-1.5-1-1.5 2-2 1.5 1 1.5-.6.4-1.6Z"
        stroke="currentColor"
        strokeWidth={1.8}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export type NavIconName = "home" | "stats" | "recurring" | "budgets" | "settings";

export function NavIcon({
  name,
  size = 22,
  className,
}: {
  name: NavIconName;
  size?: number;
  className?: string;
}) {
  switch (name) {
    case "home":
      return <HomeIcon size={size} className={className} />;
    case "stats":
      return <StatsIcon size={size} className={className} />;
    case "recurring":
      return <RecurringIcon size={size} className={className} />;
    case "budgets":
      return <BudgetsIcon size={size} className={className} />;
    case "settings":
      return <SettingsIcon size={size} className={className} />;
  }
}
