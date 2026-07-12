import type { ViewKey } from "@/lib/types";
import type { NavIconName } from "@/components/ui/icons";

export interface MobileTabDef {
  key: Extract<ViewKey, NavIconName>;
  label: string;
}

/** Bottom-nav destinations, in left-to-right order. */
export const MOBILE_TABS: MobileTabDef[] = [
  { key: "home", label: "Home" },
  { key: "stats", label: "Stats" },
  { key: "recurring", label: "Recurring" },
  { key: "budgets", label: "Budgets" },
  { key: "lending", label: "Lending" },
];

export type MobileTabKey = (typeof MOBILE_TABS)[number]["key"];

export function mobileTabIndex(view: ViewKey): number {
  const key = view === "tx" ? "home" : view;
  const index = MOBILE_TABS.findIndex((tab) => tab.key === key);
  return index >= 0 ? index : 0;
}
