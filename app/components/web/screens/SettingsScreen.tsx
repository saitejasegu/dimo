"use client";

import type { ReactNode } from "react";
import { useAppActions, useAppState } from "@/store/app-store";
import { CURRENCY_OPTIONS } from "@/features/account/constants";
import { Avatar } from "@/components/ui/Avatar";
import { Card } from "@/components/ui/Card";
import { SegmentedControl } from "@/components/ui/SegmentedControl";
import { PaymentMethodsManager } from "@/components/forms/PaymentMethodsManager";
import { StatsRangeDropdown } from "@/components/common/StatsRangeDropdown";
import { ThemeDropdown } from "@/components/common/ThemeDropdown";
import { TransactionDataActions } from "@/components/common/TransactionDataActions";
import { WebScreen } from "@/components/web/WebScreen";

function Row({ label, description, control }: { label: string; description: string; control: ReactNode }) {
  return <div className="flex items-center justify-between gap-6"><div><div className="text-sm font-medium text-ink">{label}</div><div className="text-xs text-muted">{description}</div></div>{control}</div>;
}

export function SettingsScreen() {
  const { profile, currency, theme, defaultStatsRange } = useAppState();
  const actions = useAppActions();
  const initial = profile.name.charAt(0).toUpperCase();
  return <WebScreen>
    <div className="mb-[22px] flex items-center justify-between gap-4">
      <div>
        <h1 className="font-display text-[28px] font-semibold text-ink">Settings</h1>
        <p className="mt-1 text-[13px] text-muted">Manage preferences, payment methods, and transaction data.</p>
      </div>
      <Avatar initial={initial} src={profile.photoUrl} onClick={actions.openAccount} />
    </div>
    <Card className="mb-[18px] p-[22px]"><h2 className="mb-[18px] font-display text-[17px] font-semibold text-ink">Preferences</h2><div className="flex flex-col gap-[18px]">
      <Row label="Appearance" description="Defaults to Light" control={<ThemeDropdown value={theme} onChange={actions.setTheme} />} /><div className="h-px bg-line-soft" />
      <div id="stats-defaults"><Row label="Default stats range" description="Range selected when you open Stats" control={<StatsRangeDropdown value={defaultStatsRange} onChange={actions.setDefaultStatsRange} />} /></div><div className="h-px bg-line-soft" />
      <Row label="Currency" description="Used across the whole app" control={<SegmentedControl options={CURRENCY_OPTIONS} value={currency} onChange={actions.setCurrency} fill={false} />} />
    </div></Card>
    <Card className="mb-[18px] p-[22px]"><PaymentMethodsManager /></Card>
    <Card className="mb-[18px] p-[22px]"><TransactionDataActions /></Card>
  </WebScreen>;
}
