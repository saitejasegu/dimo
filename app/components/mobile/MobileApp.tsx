"use client";

import { useAppState } from "@/store/app-store";
import { TabBar } from "@/components/mobile/TabBar";
import { Fab } from "@/components/mobile/Fab";
import { HomeScreen } from "@/components/mobile/screens/HomeScreen";
import { ActivityScreen } from "@/components/mobile/screens/ActivityScreen";
import { StatsScreen } from "@/components/mobile/screens/StatsScreen";
import { RecurringScreen } from "@/components/mobile/screens/RecurringScreen";
import { BudgetsScreen } from "@/components/mobile/screens/BudgetsScreen";
import { AccountScreen } from "@/components/mobile/screens/AccountScreen";
import { TxDetailSheet } from "@/components/mobile/sheets/TxDetailSheet";
import { AddExpenseSheet } from "@/components/mobile/sheets/AddExpenseSheet";
import { AddRecurringSheet } from "@/components/mobile/sheets/AddRecurringSheet";
import { NewCategorySheet } from "@/components/mobile/sheets/NewCategorySheet";
import { Toaster } from "@/components/common/Toaster";

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
  const showFab = view === "home" || view === "tx";

  return (
    <div className="relative h-dvh overflow-hidden bg-canvas font-body">
      <CurrentScreen />
      {showFab ? <Fab /> : null}
      <TabBar />

      {view === "account" ? <AccountScreen /> : null}

      {detailId ? <TxDetailSheet /> : null}
      {overlay === "add" ? <AddExpenseSheet /> : null}
      {overlay === "recurring" ? <AddRecurringSheet /> : null}
      {overlay === "category" ? <NewCategorySheet /> : null}

      <Toaster variant="mobile" />
    </div>
  );
}
