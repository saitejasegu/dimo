"use client";

import { useAppActions, useAppState } from "@/store/app-store";
import { CURRENCY_OPTIONS } from "@/features/account/constants";
import { Avatar } from "@/components/ui/Avatar";
import { Card } from "@/components/ui/Card";
import { SegmentedControl } from "@/components/ui/SegmentedControl";
import { Slider } from "@/components/ui/Slider";
import { ChevronIcon } from "@/components/ui/icons";
import { PaymentMethodsManager } from "@/components/forms/PaymentMethodsManager";
import { StatsRangeDropdown } from "@/components/common/StatsRangeDropdown";
import { ThemeDropdown } from "@/components/common/ThemeDropdown";
import { TransactionDataActions } from "@/components/common/TransactionDataActions";
import { MobileScreen, MobileTopBar } from "@/components/mobile/MobileScreen";

export function SettingsScreen() {
  const { profile, currency, theme, navGlassOpacity, defaultStatsRange } = useAppState();
  const actions = useAppActions();
  const initial = profile.name.charAt(0).toUpperCase();
  return (
    <div className="absolute inset-0 z-[17] animate-account-in overflow-hidden bg-canvas shadow-[-12px_0_32px_rgba(0,0,0,0.12)]">
      <MobileScreen
        header={
          <MobileTopBar
            title="Settings"
            className="gap-3.5 pl-12"
            trailing={null}
          />
        }
        className="pb-[max(2.5rem,env(safe-area-inset-bottom,0px))]"
      >
        <button
          type="button"
          onClick={actions.closeSettings}
          aria-label="Back"
          className="absolute left-[22px] top-[max(1.75rem,calc(env(safe-area-inset-top)+0.75rem))] z-10 flex h-14 items-center"
        >
          <span className="flex h-[38px] w-[38px] items-center justify-center rounded-xl border border-line bg-surface text-ink">
            <ChevronIcon direction="left" />
          </span>
        </button>

        <Card
          className="mb-3.5 flex items-center gap-3.5 p-4"
          onClick={actions.openAccount}
        >
          <Avatar
            initial={initial}
            src={profile.photoUrl}
            size={48}
            radius={14}
            textClassName="text-lg"
          />
          <span className="min-w-0 flex-1">
            <span className="block truncate font-display text-base font-semibold text-ink">
              {profile.name}
            </span>
            <span className="mt-0.5 block truncate text-xs text-muted">
              {profile.email}
            </span>
          </span>
          <ChevronIcon direction="right" className="text-faint" />
        </Card>

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
      </MobileScreen>
    </div>
  );
}
