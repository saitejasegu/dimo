"use client";

import type { ViewKey } from "@/lib/types";
import { cn } from "@/lib/cn";
import { useAppActions, useAppState } from "@/store/app-store";
import { NavIcon, type NavIconName } from "@/components/ui/icons";

interface TabDef {
  key: Extract<ViewKey, NavIconName>;
  label: string;
}

const TABS: TabDef[] = [
  { key: "home", label: "Home" },
  { key: "stats", label: "Stats" },
  { key: "recurring", label: "Recurring" },
  { key: "budgets", label: "Budgets" },
  { key: "settings", label: "Settings" },
];

export function TabBar() {
  const { view } = useAppState();
  const { setView } = useAppActions();

  return (
    <nav
      aria-label="Primary navigation"
      className="relative z-[15] grid shrink-0 grid-cols-5 items-start border-t border-line bg-canvas/90 px-3 pb-[max(0.5rem,env(safe-area-inset-bottom,0px))] pt-2.5 backdrop-blur-md"
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
            <NavIcon name={tab.key} className={active ? "text-green" : "text-faint"} />
            <span className={cn("text-[10px]", active ? "font-semibold" : "font-normal")}>
              {tab.label}
            </span>
          </button>
        );
      })}
    </nav>
  );
}
