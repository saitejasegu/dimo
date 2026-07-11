"use client";

import { useAppState } from "@/store/app-store";
import { WindowChrome } from "@/components/web/WindowChrome";
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
    <div className="flex min-h-screen items-center justify-center bg-[#dbe4de] px-6 py-10 font-body">
      <div className="w-[1360px] max-w-full overflow-hidden rounded-[18px] border border-[#c7d3cb] shadow-[0_50px_100px_-40px_rgba(20,35,28,0.5)]">
        <WindowChrome />
        <div className="relative flex h-[812px] bg-canvas-deep">
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
      </div>
    </div>
  );
}
