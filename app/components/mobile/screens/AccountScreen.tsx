"use client";

import { useAppActions, useAppState } from "@/store/app-store";
import {
  CURRENCY_OPTIONS,
  DEFAULT_VIEW_OPTIONS,
  THEME_OPTIONS,
  WEEK_START_OPTIONS,
} from "@/features/account/constants";
import { Card } from "@/components/ui/Card";
import { Avatar } from "@/components/ui/Avatar";
import { TextField } from "@/components/ui/TextField";
import { SegmentedControl } from "@/components/ui/SegmentedControl";
import { ChevronIcon } from "@/components/ui/icons";
import { PaymentMethodsManager } from "@/components/forms/PaymentMethodsManager";
import { SyncStatusCard } from "@/components/common/SyncStatusCard";
import { AccountSessionActions } from "@/components/common/AccountSessionActions";
import { StatsRangeDropdown } from "@/components/common/StatsRangeDropdown";

const VIEW_OPTIONS = DEFAULT_VIEW_OPTIONS.map((v) => ({
  value: v as string,
  label: v,
}));

export function AccountScreen() {
  const { profile, currency, weekStart, theme, defaultView, defaultStatsRange } =
    useAppState();
  const actions = useAppActions();

  return (
    <div className="absolute inset-0 z-[18] flex animate-screen-in flex-col overflow-hidden bg-canvas">
      <div className="shrink-0 bg-canvas px-[22px] pb-3 pt-[max(1.75rem,calc(env(safe-area-inset-top)+0.75rem))]">
        <div className="flex items-center gap-3.5">
          <button
            type="button"
            onClick={actions.closeAccount}
            aria-label="Back"
            className="flex h-[38px] w-[38px] shrink-0 items-center justify-center rounded-xl border border-line bg-surface text-ink"
          >
            <ChevronIcon direction="left" />
          </button>
          <h1 className="font-display text-2xl font-semibold text-ink">Account</h1>
        </div>
      </div>

      <div className="bubble-scrollbar min-h-0 flex-1 overflow-y-auto overscroll-none px-[22px] pb-[max(2.5rem,env(safe-area-inset-bottom))]">
        <Card className="mb-3.5 p-5">
          <div className="mb-4 flex items-center gap-4">
            <Avatar
              initial={profile.name.charAt(0).toUpperCase()}
              src={profile.photoUrl}
              size={60}
              radius={18}
              textClassName="text-[26px]"
            />
            <div>
              <div className="font-display text-[17px] font-semibold text-ink">
                {profile.name}
              </div>
              <div className="mt-0.5 text-xs text-muted">Managed by your sign-in provider</div>
            </div>
          </div>
          <TextField
            label="Full name"
            value={profile.name}
            readOnly
            className="mb-3"
          />
          <TextField
            label="Email"
            value={profile.email}
            readOnly
          />
        </Card>

        <Card className="mb-3.5 p-5">
          <PaymentMethodsManager />
        </Card>

        <Card className="mb-3.5 p-5">
          <h2 className="mb-4 font-display text-base font-semibold text-ink">
            Preferences
          </h2>
          <div id="stats-defaults" className="mb-4 flex items-center justify-between gap-4">
            <p className="text-[13px] font-medium text-ink">
              Default stats range
            </p>
            <StatsRangeDropdown
              value={defaultStatsRange}
              onChange={actions.setDefaultStatsRange}
            />
          </div>
          <p className="mb-2 text-[13px] font-medium text-ink">Week starts on</p>
          <SegmentedControl
            options={WEEK_START_OPTIONS}
            value={weekStart}
            onChange={actions.setWeekStart}
            className="mb-4"
          />
          <p className="mb-2 text-[13px] font-medium text-ink">Appearance</p>
          <SegmentedControl
            options={THEME_OPTIONS}
            value={theme}
            onChange={actions.setTheme}
            className="mb-4"
          />
          <p className="mb-2 text-[13px] font-medium text-ink">Currency</p>
          <SegmentedControl
            options={CURRENCY_OPTIONS}
            value={currency}
            onChange={actions.setCurrency}
            className="mb-4"
          />
          <p className="mb-2 text-[13px] font-medium text-ink">Default view</p>
          <SegmentedControl
            options={VIEW_OPTIONS}
            value={defaultView}
            onChange={actions.setDefaultView}
          />
        </Card>

        <Card className="mb-3.5 p-5"><SyncStatusCard /></Card>

        <Card className="mb-3.5 p-5">
          <AccountSessionActions />
        </Card>
      </div>
    </div>
  );
}
