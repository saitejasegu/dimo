"use client";

import type { ReactNode } from "react";
import { useAppActions, useAppState } from "@/store/app-store";
import { CURRENCY_OPTIONS, DEFAULT_VIEW_OPTIONS, THEME_OPTIONS } from "@/features/account/constants";
import { Card } from "@/components/ui/Card";
import { SegmentedControl } from "@/components/ui/SegmentedControl";
import { PaymentMethodsManager } from "@/components/forms/PaymentMethodsManager";
import { StatsRangeDropdown } from "@/components/common/StatsRangeDropdown";
import { TransactionDataActions } from "@/components/common/TransactionDataActions";
import { WebScreen } from "@/components/web/WebScreen";

const VIEW_OPTIONS = DEFAULT_VIEW_OPTIONS.map((value) => ({ value: value as string, label: value }));
function Row({ label, description, control }: { label: string; description: string; control: ReactNode }) {
  return <div className="flex items-center justify-between gap-6"><div><div className="text-sm font-medium text-ink">{label}</div><div className="text-xs text-muted">{description}</div></div>{control}</div>;
}

export function SettingsScreen() {
  const { currency, theme, defaultView, defaultStatsRange } = useAppState();
  const actions = useAppActions();
  return <WebScreen>
    <div className="mb-[22px]"><h1 className="font-display text-[28px] font-semibold text-ink">Settings</h1><p className="mt-1 text-[13px] text-muted">Manage preferences, payment methods, and transaction data.</p></div>
    <Card className="mb-[18px] p-[22px]"><h2 className="mb-[18px] font-display text-[17px] font-semibold text-ink">Preferences</h2><div className="flex flex-col gap-[18px]">
      <div id="stats-defaults"><Row label="Default stats range" description="Range selected when you open Stats" control={<StatsRangeDropdown value={defaultStatsRange} onChange={actions.setDefaultStatsRange} />} /></div><div className="h-px bg-line-soft" />
      <Row label="Appearance" description="Use your system setting or choose a theme" control={<SegmentedControl options={THEME_OPTIONS} value={theme} onChange={actions.setTheme} fill={false} />} /><div className="h-px bg-line-soft" />
      <Row label="Currency" description="Used across the whole app" control={<SegmentedControl options={CURRENCY_OPTIONS} value={currency} onChange={actions.setCurrency} fill={false} />} /><div className="h-px bg-line-soft" />
      <Row label="Default view" description="Screen shown when you open Dimo" control={<SegmentedControl options={VIEW_OPTIONS} value={defaultView} onChange={actions.setDefaultView} fill={false} />} />
    </div></Card>
    <Card className="mb-[18px] p-[22px]"><PaymentMethodsManager /></Card>
    <Card className="mb-[18px] p-[22px]"><TransactionDataActions /></Card>
  </WebScreen>;
}
