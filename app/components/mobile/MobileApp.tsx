"use client";

import { lazy, Suspense } from "react";
import { useAppState } from "@/store/app-store";
import { usePrefetchOnMount } from "@/hooks/usePrefetchOnMount";
import { TabBar } from "@/components/mobile/TabBar";
import { Fab } from "@/components/mobile/Fab";
import { HomeScreen } from "@/components/mobile/screens/HomeScreen";
import { Toaster } from "@/components/common/Toaster";

const loadActivityScreen = () =>
  import("@/components/mobile/screens/ActivityScreen").then((m) => ({ default: m.ActivityScreen }));
const loadStatsScreen = () =>
  import("@/components/mobile/screens/StatsScreen").then((m) => ({ default: m.StatsScreen }));
const loadRecurringScreen = () =>
  import("@/components/mobile/screens/RecurringScreen").then((m) => ({ default: m.RecurringScreen }));
const loadBudgetsScreen = () =>
  import("@/components/mobile/screens/BudgetsScreen").then((m) => ({ default: m.BudgetsScreen }));
const loadAccountScreen = () =>
  import("@/components/mobile/screens/AccountScreen").then((m) => ({ default: m.AccountScreen }));
const loadTxDetailSheet = () =>
  import("@/components/mobile/sheets/TxDetailSheet").then((m) => ({ default: m.TxDetailSheet }));
const loadAddExpenseSheet = () =>
  import("@/components/mobile/sheets/AddExpenseSheet").then((m) => ({ default: m.AddExpenseSheet }));
const loadAddRecurringSheet = () =>
  import("@/components/mobile/sheets/AddRecurringSheet").then((m) => ({ default: m.AddRecurringSheet }));
const loadNewCategorySheet = () =>
  import("@/components/mobile/sheets/NewCategorySheet").then((m) => ({ default: m.NewCategorySheet }));

const ActivityScreen = lazy(loadActivityScreen);
const StatsScreen = lazy(loadStatsScreen);
const RecurringScreen = lazy(loadRecurringScreen);
const BudgetsScreen = lazy(loadBudgetsScreen);
const AccountScreen = lazy(loadAccountScreen);
const TxDetailSheet = lazy(loadTxDetailSheet);
const AddExpenseSheet = lazy(loadAddExpenseSheet);
const AddRecurringSheet = lazy(loadAddRecurringSheet);
const NewCategorySheet = lazy(loadNewCategorySheet);

const PREFETCH = [
  loadActivityScreen,
  loadStatsScreen,
  loadRecurringScreen,
  loadBudgetsScreen,
  loadAccountScreen,
  loadTxDetailSheet,
  loadAddExpenseSheet,
  loadAddRecurringSheet,
  loadNewCategorySheet,
];

function ScreenFallback() {
  return <div className="h-full bg-canvas" />;
}

function CurrentScreen() {
  const { view } = useAppState();
  switch (view) {
    case "home":
      return <HomeScreen />;
    case "tx":
      return <ActivityScreen />;
    case "stats":
      return <StatsScreen />;
    case "recurring":
      return <RecurringScreen />;
    case "budgets":
      return <BudgetsScreen />;
    default:
      // Account renders as a full-screen overlay above the tab bar.
      return null;
  }
}

export function MobileApp() {
  const { view, overlay, detailId } = useAppState();
  usePrefetchOnMount(PREFETCH);

  return (
    <div className="relative flex h-full flex-col overflow-hidden bg-canvas font-body">
      {/*
        iOS home-screen PWA with black-translucent status bar: paint the
        Dynamic Island / status-bar band so it matches the app canvas.
      */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-x-0 top-0 z-[40] h-[env(safe-area-inset-top,0px)] min-h-[env(safe-area-inset-top,0px)] bg-canvas"
      />
      <div className="relative min-h-0 flex-1">
        <div key={view} className="h-full animate-screen-in">
          <Suspense fallback={<ScreenFallback />}>
            <CurrentScreen />
          </Suspense>
        </div>
        <Fab />
      </div>
      <TabBar />

      <Suspense fallback={null}>
        {view === "account" ? <AccountScreen /> : null}
        {detailId ? <TxDetailSheet /> : null}
        {overlay === "add" ? <AddExpenseSheet /> : null}
        {overlay === "recurring" ? <AddRecurringSheet /> : null}
        {overlay === "category" ? <NewCategorySheet /> : null}
      </Suspense>

      <Toaster variant="mobile" />
    </div>
  );
}
