"use client";

import { lazy, Suspense, useRef, type ReactNode } from "react";
import { useAppActions } from "@/store/app-store";
import { useTabPagerSwipe } from "@/hooks/useTabPagerSwipe";
import { HomeScreen } from "@/components/mobile/screens/HomeScreen";
import { MOBILE_TABS, mobileTabIndex, type MobileTabKey } from "@/components/mobile/tabs";
import type { ViewKey } from "@/lib/types";

const StatsScreen = lazy(() =>
  import("@/components/mobile/screens/StatsScreen").then((m) => ({
    default: m.StatsScreen,
  })),
);
const RecurringScreen = lazy(() =>
  import("@/components/mobile/screens/RecurringScreen").then((m) => ({
    default: m.RecurringScreen,
  })),
);
const BudgetsScreen = lazy(() =>
  import("@/components/mobile/screens/BudgetsScreen").then((m) => ({
    default: m.BudgetsScreen,
  })),
);
const SettingsScreen = lazy(() =>
  import("@/components/mobile/screens/SettingsScreen").then((m) => ({
    default: m.SettingsScreen,
  })),
);

function ScreenFallback() {
  return <div className="h-full bg-canvas" />;
}

function TabScreen({ tab }: { tab: MobileTabKey }) {
  switch (tab) {
    case "home":
      return <HomeScreen />;
    case "stats":
      return <StatsScreen />;
    case "recurring":
      return <RecurringScreen />;
    case "budgets":
      return <BudgetsScreen />;
    case "settings":
      return <SettingsScreen />;
  }
}

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
      <Suspense fallback={<ScreenFallback />}>{children}</Suspense>
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
            <TabScreen tab={tab.key} />
          </Panel>
        ))}
      </div>
    </div>
  );
}
