"use client";

import type { CSSProperties } from "react";
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
  const { view, navGlassOpacity } = useAppState();
  const { setView } = useAppActions();

  return (
    <nav
      aria-label="Primary navigation"
      className="pointer-events-none absolute inset-x-0 bottom-0 z-[15] px-3.5 pb-[max(0.55rem,env(safe-area-inset-bottom,0px))] pt-10"
      style={{ "--nav-glass-opacity": String(navGlassOpacity / 100) } as CSSProperties}
    >
      <div
        aria-hidden
        className="pointer-events-none absolute inset-x-0 bottom-0 h-[7.5rem] bg-gradient-to-t from-canvas from-35% via-canvas/85 to-transparent"
      />
      <div className="liquid-glass pointer-events-auto relative mx-auto grid max-w-md grid-cols-5 items-center gap-0.5 rounded-full px-1.5 py-1.5">
        {TABS.map((tab) => {
          const active = view === tab.key;
          return (
            <button
              type="button"
              key={tab.key}
              onClick={() => setView(tab.key)}
              aria-current={active ? "page" : undefined}
              aria-label={tab.label}
              className={cn(
                "flex items-center justify-center rounded-2xl !px-1 !py-1 transition-colors",
                active ? "!text-green" : "!text-body",
              )}
            >
              <span
                className={cn(
                  "flex h-10 w-full max-w-[3.25rem] items-center justify-center rounded-full transition-colors",
                  active && "bg-green/18 shadow-[inset_0_1px_0_rgba(255,255,255,0.4)]",
                )}
              >
                <NavIcon name={tab.key} className={active ? "text-green" : "text-body"} />
              </span>
            </button>
          );
        })}
      </div>
    </nav>
  );
}
