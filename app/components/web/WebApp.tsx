"use client";

import { lazy, Suspense } from "react";
import { useAppState } from "@/store/app-store";
import { usePrefetchOnMount } from "@/hooks/usePrefetchOnMount";
import { Sidebar } from "@/components/web/Sidebar";
import { OverviewScreen } from "@/components/web/screens/OverviewScreen";
import { Toaster } from "@/components/common/Toaster";

const loadSettingsScreen = () =>
  import("@/components/web/screens/SettingsScreen").then((m) => ({ default: m.SettingsScreen }));
const loadStatsScreen = () =>
  import("@/components/web/screens/StatsScreen").then((m) => ({ default: m.StatsScreen }));
const loadRecurringScreen = () =>
  import("@/components/web/screens/RecurringScreen").then((m) => ({ default: m.RecurringScreen }));
const loadBudgetsScreen = () =>
  import("@/components/web/screens/BudgetsScreen").then((m) => ({ default: m.BudgetsScreen }));
const loadAccountScreen = () =>
  import("@/components/web/screens/AccountScreen").then((m) => ({ default: m.AccountScreen }));
const loadTxDetailModal = () =>
  import("@/components/web/modals/TxDetailModal").then((m) => ({ default: m.TxDetailModal }));
const loadAddExpenseModal = () =>
  import("@/components/web/modals/AddExpenseModal").then((m) => ({ default: m.AddExpenseModal }));
const loadAddRecurringModal = () =>
  import("@/components/web/modals/AddRecurringModal").then((m) => ({ default: m.AddRecurringModal }));
const loadNewCategoryModal = () =>
  import("@/components/web/modals/NewCategoryModal").then((m) => ({ default: m.NewCategoryModal }));

const SettingsScreen = lazy(loadSettingsScreen);
const StatsScreen = lazy(loadStatsScreen);
const RecurringScreen = lazy(loadRecurringScreen);
const BudgetsScreen = lazy(loadBudgetsScreen);
const AccountScreen = lazy(loadAccountScreen);
const TxDetailModal = lazy(loadTxDetailModal);
const AddExpenseModal = lazy(loadAddExpenseModal);
const AddRecurringModal = lazy(loadAddRecurringModal);
const NewCategoryModal = lazy(loadNewCategoryModal);

const PREFETCH = [
  loadSettingsScreen,
  loadStatsScreen,
  loadRecurringScreen,
  loadBudgetsScreen,
  loadAccountScreen,
  loadTxDetailModal,
  loadAddExpenseModal,
  loadAddRecurringModal,
  loadNewCategoryModal,
];

function ScreenFallback() {
  return <div className="min-h-full bg-canvas" />;
}

function CurrentScreen() {
  const { view } = useAppState();
  switch (view) {
    case "home":
      return <OverviewScreen />;
    case "tx":
      return <OverviewScreen />;
    case "stats":
      return <StatsScreen />;
    case "recurring":
      return <RecurringScreen />;
    case "budgets":
      return <BudgetsScreen />;
    case "settings":
      return <SettingsScreen />;
    case "account":
      return <AccountScreen />;
    default:
      return null;
  }
}

export function WebApp() {
  const { view, overlay, detailId } = useAppState();
  usePrefetchOnMount(PREFETCH);

  return (
    <div className="flex h-full overflow-hidden bg-canvas font-body">
      <Sidebar />
      <main className="bubble-scrollbar min-w-0 flex-1 overflow-y-auto overflow-x-hidden bg-canvas">
        <div key={view} className="min-h-full animate-screen-in">
          <Suspense fallback={<ScreenFallback />}>
            <CurrentScreen />
          </Suspense>
        </div>
      </main>

      <Suspense fallback={null}>
        {detailId ? <TxDetailModal /> : null}
        {overlay === "add" ? <AddExpenseModal /> : null}
        {overlay === "recurring" ? <AddRecurringModal /> : null}
        {overlay === "category" ? <NewCategoryModal /> : null}
      </Suspense>

      <Toaster variant="web" />
    </div>
  );
}
