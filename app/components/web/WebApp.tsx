"use client";

import { lazy, Suspense } from "react";
import { useAppState } from "@/store/app-store";
import { Sidebar } from "@/components/web/Sidebar";
import { OverviewScreen } from "@/components/web/screens/OverviewScreen";
import { Toaster } from "@/components/common/Toaster";

const ActivityScreen = lazy(() =>
  import("@/components/web/screens/ActivityScreen").then((m) => ({ default: m.ActivityScreen })),
);
const StatsScreen = lazy(() =>
  import("@/components/web/screens/StatsScreen").then((m) => ({ default: m.StatsScreen })),
);
const RecurringScreen = lazy(() =>
  import("@/components/web/screens/RecurringScreen").then((m) => ({ default: m.RecurringScreen })),
);
const BudgetsScreen = lazy(() =>
  import("@/components/web/screens/BudgetsScreen").then((m) => ({ default: m.BudgetsScreen })),
);
const AccountScreen = lazy(() =>
  import("@/components/web/screens/AccountScreen").then((m) => ({ default: m.AccountScreen })),
);
const TxDetailModal = lazy(() =>
  import("@/components/web/modals/TxDetailModal").then((m) => ({ default: m.TxDetailModal })),
);
const AddExpenseModal = lazy(() =>
  import("@/components/web/modals/AddExpenseModal").then((m) => ({ default: m.AddExpenseModal })),
);
const AddRecurringModal = lazy(() =>
  import("@/components/web/modals/AddRecurringModal").then((m) => ({ default: m.AddRecurringModal })),
);
const NewCategoryModal = lazy(() =>
  import("@/components/web/modals/NewCategoryModal").then((m) => ({ default: m.NewCategoryModal })),
);

function ScreenFallback() {
  return <div className="min-h-full bg-canvas" />;
}

function CurrentScreen() {
  const { view } = useAppState();
  switch (view) {
    case "home":
      return <OverviewScreen />;
    case "tx":
      return <ActivityScreen />;
    case "stats":
      return <StatsScreen />;
    case "recurring":
      return <RecurringScreen />;
    case "budgets":
      return <BudgetsScreen />;
    case "account":
      return <AccountScreen />;
    default:
      return null;
  }
}

export function WebApp() {
  const { view, overlay, detailId } = useAppState();

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
