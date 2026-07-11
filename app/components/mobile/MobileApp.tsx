"use client";

import { lazy, Suspense } from "react";
import { useAppState } from "@/store/app-store";
import { TabBar } from "@/components/mobile/TabBar";
import { Fab } from "@/components/mobile/Fab";
import { HomeScreen } from "@/components/mobile/screens/HomeScreen";
import { Toaster } from "@/components/common/Toaster";

const ActivityScreen = lazy(() =>
  import("@/components/mobile/screens/ActivityScreen").then((m) => ({ default: m.ActivityScreen })),
);
const StatsScreen = lazy(() =>
  import("@/components/mobile/screens/StatsScreen").then((m) => ({ default: m.StatsScreen })),
);
const RecurringScreen = lazy(() =>
  import("@/components/mobile/screens/RecurringScreen").then((m) => ({ default: m.RecurringScreen })),
);
const BudgetsScreen = lazy(() =>
  import("@/components/mobile/screens/BudgetsScreen").then((m) => ({ default: m.BudgetsScreen })),
);
const AccountScreen = lazy(() =>
  import("@/components/mobile/screens/AccountScreen").then((m) => ({ default: m.AccountScreen })),
);
const TxDetailSheet = lazy(() =>
  import("@/components/mobile/sheets/TxDetailSheet").then((m) => ({ default: m.TxDetailSheet })),
);
const AddExpenseSheet = lazy(() =>
  import("@/components/mobile/sheets/AddExpenseSheet").then((m) => ({ default: m.AddExpenseSheet })),
);
const AddRecurringSheet = lazy(() =>
  import("@/components/mobile/sheets/AddRecurringSheet").then((m) => ({ default: m.AddRecurringSheet })),
);
const NewCategorySheet = lazy(() =>
  import("@/components/mobile/sheets/NewCategorySheet").then((m) => ({ default: m.NewCategorySheet })),
);

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
