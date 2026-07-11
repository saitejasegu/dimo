"use client";

import type { ReactNode } from "react";
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
import { PaymentMethodsManager } from "@/components/forms/PaymentMethodsManager";
import { SyncStatusCard } from "@/components/common/SyncStatusCard";
import { AccountSessionActions } from "@/components/common/AccountSessionActions";
import { StatsRangeDropdown } from "@/components/common/StatsRangeDropdown";
import { WebScreen } from "@/components/web/WebScreen";

const VIEW_OPTIONS = DEFAULT_VIEW_OPTIONS.map((v) => ({
  value: v as string,
  label: v,
}));

function PreferenceRow({
  label,
  description,
  control,
}: {
  label: string;
  description: string;
  control: ReactNode;
}) {
  return (
    <div className="flex items-center justify-between">
      <div>
        <div className="text-sm font-medium text-ink">{label}</div>
        <div className="text-xs text-muted">{description}</div>
      </div>
      {control}
    </div>
  );
}

export function AccountScreen() {
  const { profile, currency, weekStart, theme, defaultView, defaultStatsRange } =
    useAppState();
  const actions = useAppActions();

  return (
    <WebScreen>
      <div className="mb-[22px]">
        <div className="font-display text-[28px] font-semibold text-ink">
          Account
        </div>
        <div className="mt-1 text-[13px] text-muted">
          Manage your profile and preferences.
        </div>
      </div>

      <Card className="mb-[18px] flex items-center gap-6 p-6">
        <div className="flex shrink-0 flex-col items-center gap-2">
          <Avatar
            initial={profile.name.charAt(0).toUpperCase()}
            src={profile.photoUrl}
            size={72}
            radius={22}
            textClassName="text-[30px]"
          />
          <div className="text-center text-xs text-muted">Managed by your sign-in provider</div>
        </div>
        <div className="grid flex-1 grid-cols-2 gap-4">
          <TextField
            label="Full name"
            value={profile.name}
            readOnly
          />
          <TextField
            label="Email"
            value={profile.email}
            readOnly
          />
        </div>
      </Card>

      <div className="mb-[18px]">
        <Card className="p-[22px]">
          <h2 className="mb-[18px] font-display text-[17px] font-semibold text-ink">
            Preferences
          </h2>
          <div className="flex flex-col gap-[18px]">
            <div id="stats-defaults">
              <PreferenceRow
                label="Default stats range"
                description="Range selected when you open Stats"
                control={
                  <StatsRangeDropdown
                    value={defaultStatsRange}
                    onChange={actions.setDefaultStatsRange}
                  />
                }
              />
            </div>
            <div className="h-px bg-line-soft" />
            <PreferenceRow
              label="Week starts on"
              description="Affects weekly summaries"
              control={
                <SegmentedControl
                  options={WEEK_START_OPTIONS}
                  value={weekStart}
                  onChange={actions.setWeekStart}
                  fill={false}
                />
              }
            />
            <div className="h-px bg-line-soft" />
            <PreferenceRow
              label="Appearance"
              description="Use your system setting or choose a theme"
              control={
                <SegmentedControl
                  options={THEME_OPTIONS}
                  value={theme}
                  onChange={actions.setTheme}
                  fill={false}
                />
              }
            />
            <div className="h-px bg-line-soft" />
            <PreferenceRow
              label="Currency"
              description="Used across the whole app"
              control={
                <SegmentedControl
                  options={CURRENCY_OPTIONS}
                  value={currency}
                  onChange={actions.setCurrency}
                  fill={false}
                />
              }
            />
            <div className="h-px bg-line-soft" />
            <PreferenceRow
              label="Default view"
              description="Screen shown when you open Dimo"
              control={
                <SegmentedControl
                  options={VIEW_OPTIONS}
                  value={defaultView}
                  onChange={actions.setDefaultView}
                  fill={false}
                />
              }
            />
          </div>
        </Card>
      </div>

      <Card className="mb-[18px] p-[22px]">
        <PaymentMethodsManager />
      </Card>
      <Card className="mb-[18px] p-[22px]"><SyncStatusCard /></Card>
      <Card className="mb-[18px] p-[22px]">
        <AccountSessionActions />
      </Card>
    </WebScreen>
  );
}
