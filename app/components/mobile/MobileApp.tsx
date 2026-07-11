"use client";

import { useAppState } from "@/store/app-store";
import { StatusBar } from "@/components/mobile/StatusBar";
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
    <div className="flex min-h-screen items-center justify-center bg-[#e9efeb] px-6 py-12 font-body">
      <div className="flex flex-col items-center gap-[18px]">
        <div className="w-[392px] rounded-[52px] bg-ink-deep p-3 shadow-[0_40px_80px_-30px_rgba(20,35,28,0.55)]">
          <div className="relative h-[812px] overflow-hidden rounded-[41px] bg-canvas">
            <StatusBar />
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
        </div>

        <p className="max-w-[360px] text-center text-[13px] leading-relaxed text-muted">
          Click demo — switch tabs, search &amp; filter transactions, tap one for
          details, add an expense with the{" "}
          <span className="font-semibold text-green">+</span> button, and tap
          recurring bills to pause them.
        </p>
      </div>
    </div>
  );
}
