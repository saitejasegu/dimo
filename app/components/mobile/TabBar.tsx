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

const LEFT_TABS: TabDef[] = [
  { key: "home", label: "Home" },
  { key: "stats", label: "Stats" },
  { key: "recurring", label: "Recurring" },
];

const RIGHT_TABS: TabDef[] = [
  { key: "budgets", label: "Budgets", round: true },
  { key: "settings", label: "Settings" },
];

export function TabBar() {
  const { view } = useAppState();
  const { setView } = useAppActions();

  const renderTab = (tab: TabDef) => {
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
        <span className={cn("text-[10px]", active ? "font-semibold" : "font-normal")}>
          {tab.label}
        </span>
      </button>
    );
  };

  return (
    <nav
      aria-label="Primary navigation"
      className="relative z-[15] grid shrink-0 grid-cols-5 items-start border-t border-line bg-canvas/90 px-3 pb-[max(0.5rem,env(safe-area-inset-bottom,0px))] pt-2.5 backdrop-blur-md"
    >
      {LEFT_TABS.map(renderTab)}
      {RIGHT_TABS.map(renderTab)}
    </nav>
  );
}
