"use client";

import type { ViewKey } from "@/lib/types";
import { cn } from "@/lib/cn";
import { useAppActions, useAppState } from "@/store/app-store";
import { NavGlyph } from "@/components/ui/icons";

interface TabDef {
  key: ViewKey;
  label: string;
  round?: boolean;
}

const TABS: TabDef[] = [
  { key: "home", label: "Home" },
  { key: "tx", label: "Activity" },
  { key: "stats", label: "Stats" },
  { key: "recurring", label: "Recurring" },
  { key: "budgets", label: "Budgets", round: true },
];

export function TabBar() {
  const { view } = useAppState();
  const { setView } = useAppActions();

  return (
    <nav
      aria-label="Primary navigation"
      className="absolute inset-x-0 bottom-0 z-[15] flex h-[88px] items-start justify-between border-t border-line bg-canvas/90 px-[22px] pb-[max(0.75rem,env(safe-area-inset-bottom))] pt-3 backdrop-blur-md"
    >
      {TABS.map((tab) => {
        const active = view === tab.key;
        return (
          <button
            type="button"
            key={tab.key}
            onClick={() => setView(tab.key)}
            aria-current={active ? "page" : undefined}
            className={cn(
              "flex flex-col items-center gap-1.5 !px-2 !py-0.5",
              active ? "!text-green" : "!text-faint",
            )}
          >
            <NavGlyph round={tab.round} className={active ? "text-green" : "text-faint"} />
            <span
              className={cn("text-[10px]", active ? "font-semibold" : "font-normal")}
            >
              {tab.label}
            </span>
          </button>
        );
      })}
    </nav>
  );
}
