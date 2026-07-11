"use client";

import { useAppState } from "@/store/app-store";
import { Sidebar } from "@/components/web/Sidebar";
import { OverviewScreen } from "@/components/web/screens/OverviewScreen";
import { ActivityScreen } from "@/components/web/screens/ActivityScreen";
import { StatsScreen } from "@/components/web/screens/StatsScreen";
import { RecurringScreen } from "@/components/web/screens/RecurringScreen";
import { BudgetsScreen } from "@/components/web/screens/BudgetsScreen";
import { AccountScreen } from "@/components/web/screens/AccountScreen";
import { TxDetailModal } from "@/components/web/modals/TxDetailModal";
import { AddExpenseModal } from "@/components/web/modals/AddExpenseModal";
import { AddRecurringModal } from "@/components/web/modals/AddRecurringModal";
import { NewCategoryModal } from "@/components/web/modals/NewCategoryModal";
import { Toaster } from "@/components/common/Toaster";

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
  const { overlay, detailId } = useAppState();

  return (
    <div className="relative flex h-dvh overflow-hidden bg-canvas font-body">
      <Sidebar />
      <main className="min-w-0 flex-1 overflow-y-auto overflow-x-hidden bg-canvas">
        <CurrentScreen />
      </main>

      {detailId ? <TxDetailModal /> : null}
      {overlay === "add" ? <AddExpenseModal /> : null}
      {overlay === "recurring" ? <AddRecurringModal /> : null}
      {overlay === "category" ? <NewCategoryModal /> : null}

      <Toaster variant="web" />
    </div>
  );
}
