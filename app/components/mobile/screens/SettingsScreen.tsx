"use client";

import { useAppActions, useAppState } from "@/store/app-store";
import { CURRENCY_OPTIONS, DEFAULT_VIEW_OPTIONS, THEME_OPTIONS } from "@/features/account/constants";
import { Card } from "@/components/ui/Card";
import { SegmentedControl } from "@/components/ui/SegmentedControl";
import { PaymentMethodsManager } from "@/components/forms/PaymentMethodsManager";
import { StatsRangeDropdown } from "@/components/common/StatsRangeDropdown";
import { TransactionDataActions } from "@/components/common/TransactionDataActions";
import { MobileScreen } from "@/components/mobile/MobileScreen";

const VIEW_OPTIONS = DEFAULT_VIEW_OPTIONS.map((value) => ({ value: value as string, label: value }));
export function SettingsScreen() {
  const { currency, theme, defaultView, defaultStatsRange } = useAppState();
  const actions = useAppActions();
  return <MobileScreen header={<><h1 className="font-display text-2xl font-semibold text-ink">Settings</h1><p className="mt-1 text-xs text-muted">Preferences and data management</p></>}>
    <Card className="mb-3.5 p-5"><h2 className="mb-4 font-display text-base font-semibold text-ink">Preferences</h2>
      <div id="stats-defaults" className="mb-4 flex items-center justify-between gap-4"><p className="text-[13px] font-medium text-ink">Default stats range</p><StatsRangeDropdown value={defaultStatsRange} onChange={actions.setDefaultStatsRange} /></div>
      <p className="mb-2 text-[13px] font-medium text-ink">Appearance</p><SegmentedControl options={THEME_OPTIONS} value={theme} onChange={actions.setTheme} className="mb-4" />
      <p className="mb-2 text-[13px] font-medium text-ink">Currency</p><SegmentedControl options={CURRENCY_OPTIONS} value={currency} onChange={actions.setCurrency} className="mb-4" />
      <p className="mb-2 text-[13px] font-medium text-ink">Default view</p><SegmentedControl options={VIEW_OPTIONS} value={defaultView} onChange={actions.setDefaultView} />
    </Card>
    <Card className="mb-3.5 p-5"><PaymentMethodsManager /></Card>
    <Card className="mb-3.5 p-5"><TransactionDataActions /></Card>
  </MobileScreen>;
}
