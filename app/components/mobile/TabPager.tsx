"use client";

import { memo, useRef, useState, type ReactNode } from "react";
import { useAppActions } from "@/store/app-store";
import { useTabPagerSwipe } from "@/hooks/useTabPagerSwipe";
import { HomeScreen } from "@/components/mobile/screens/HomeScreen";
import { StatsScreen } from "@/components/mobile/screens/StatsScreen";
import { BudgetsScreen } from "@/components/mobile/screens/BudgetsScreen";
import { LendingScreen } from "@/components/mobile/screens/LendingScreen";
import { MOBILE_TABS, mobileTabIndex, type MobileTabKey } from "@/components/mobile/tabs";
import type { ViewKey } from "@/lib/types";

function TabScreenImpl({ tab }: { tab: MobileTabKey }) {
  switch (tab) {
    case "home":
      return <HomeScreen />;
    case "stats":
      return <StatsScreen />;
    case "budgets":
      return <BudgetsScreen />;
    case "lending":
      return <LendingScreen />;
  }
}

/** Memoised so a pager re-render (swipe settle, view change) alone cannot re-render
 * a screen; screens still update through their own store subscriptions. */
const TabScreen = memo(TabScreenImpl);

function Panel({
  active,
  children,
}: {
  active: boolean;
  children: ReactNode;
}) {
  return (
    <div
      className="h-full shrink-0"
      style={{ width: `${100 / MOBILE_TABS.length}%` }}
      aria-hidden={!active}
      inert={!active}
    >
      {children}
    </div>
  );
}

/** Horizontally sliding stack of primary mobile screens, synced to the tab bar. */
export function TabPager({
  activeView,
  swipeEnabled = true,
}: {
  activeView: ViewKey;
  /** Disable while a full-screen overlay (e.g. Account) owns gestures. */
  swipeEnabled?: boolean;
}) {
  const { setView } = useAppActions();
  const index = mobileTabIndex(activeView);
  const containerRef = useRef<HTMLDivElement>(null);
  const trackRef = useRef<HTMLDivElement>(null);
  // Mirrors iOS's `visitedTabs`: a tab the user has never approached costs nothing, so
  // first paint and every later hydrate skip its selectors and row trees entirely.
  // Immediate neighbours count as approached — a swipe reveals them under the finger
  // before `setView` commits, so they must already be painted.
  const [visited, setVisited] = useState<Set<MobileTabKey>>(() => new Set());
  const reachable = new Set(
    [index - 1, index, index + 1]
      .map((position) => MOBILE_TABS[position]?.key)
      .filter((key): key is MobileTabKey => Boolean(key)),
  );
  const unseen = [...reachable].filter((key) => !visited.has(key));
  if (unseen.length > 0) {
    setVisited((previous) => {
      const next = new Set(previous);
      for (const key of unseen) next.add(key);
      return next;
    });
  }
  const mounted = new Set([...visited, ...reachable]);

  useTabPagerSwipe({
    containerRef,
    trackRef,
    index,
    enabled: swipeEnabled,
    onIndexChange: (nextIndex) => {
      const tab = MOBILE_TABS[nextIndex];
      if (tab) setView(tab.key);
    },
  });

  return (
    <div ref={containerRef} className="h-full overflow-hidden touch-pan-y">
      <div
        ref={trackRef}
        className="flex h-full will-change-transform motion-reduce:transition-none"
        style={{ width: `${MOBILE_TABS.length * 100}%` }}
      >
        {MOBILE_TABS.map((tab, tabIndex) => (
          <Panel key={tab.key} active={tabIndex === index}>
            {mounted.has(tab.key) ? <TabScreen tab={tab.key} /> : null}
          </Panel>
        ))}
      </div>
    </div>
  );
}
