"use client";

import { useAppActions, useAppState } from "@/store/app-store";
import { CURRENCY_OPTIONS } from "@/features/account/constants";
import { Avatar } from "@/components/ui/Avatar";
import { Card } from "@/components/ui/Card";
import { SegmentedControl } from "@/components/ui/SegmentedControl";
import { Slider } from "@/components/ui/Slider";
import { PaymentMethodsManager } from "@/components/forms/PaymentMethodsManager";
import { StatsRangeDropdown } from "@/components/common/StatsRangeDropdown";
import { ThemeDropdown } from "@/components/common/ThemeDropdown";
import { TransactionDataActions } from "@/components/common/TransactionDataActions";
import { MobileScreen, MobileTopBar } from "@/components/mobile/MobileScreen";

export function SettingsScreen() {
  const { profile, currency, theme, navGlassOpacity, defaultStatsRange } = useAppState();
  const actions = useAppActions();
  const initial = profile.name.charAt(0).toUpperCase();
  return <MobileScreen header={
    <MobileTopBar
      title="Settings"
      trailing={<Avatar initial={initial} src={profile.photoUrl} onClick={actions.openAccount} />}
    />
  }>
    <Card className="mb-3.5 p-5"><h2 className="mb-4 font-display text-base font-semibold text-ink">Preferences</h2>
      <div className="mb-4 flex items-center justify-between gap-4"><p className="text-[13px] font-medium text-ink">Appearance</p><ThemeDropdown value={theme} onChange={actions.setTheme} /></div>
      <div id="stats-defaults" className="mb-4 flex items-center justify-between gap-4"><p className="text-[13px] font-medium text-ink">Default stats range</p><StatsRangeDropdown value={defaultStatsRange} onChange={actions.setDefaultStatsRange} /></div>
      <Slider
        label="Nav glass opacity"
        valueLabel={`${navGlassOpacity}%`}
        value={navGlassOpacity}
        min={40}
        max={100}
        onChange={(value) => actions.setNavGlassOpacity(value, { persist: false })}
        onCommit={(value) => actions.setNavGlassOpacity(value)}
        className="mb-4"
      />
      <p className="mb-2 text-[13px] font-medium text-ink">Currency</p><SegmentedControl options={CURRENCY_OPTIONS} value={currency} onChange={actions.setCurrency} />
    </Card>
    <Card className="mb-3.5 p-5"><PaymentMethodsManager /></Card>
    <Card className="mb-3.5 p-5"><TransactionDataActions /></Card>
  </MobileScreen>;
}
