"use client";

import type { ReactNode } from "react";
import { useAppActions, useAppState } from "@/store/app-store";
import {
  CURRENCY_OPTIONS,
  DEFAULT_VIEW_OPTIONS,
  NOTIFICATION_DEFS,
  WEEK_START_OPTIONS,
} from "@/features/account/constants";
import { Card } from "@/components/ui/Card";
import { Avatar } from "@/components/ui/Avatar";
import { Button } from "@/components/ui/Button";
import { TextField } from "@/components/ui/TextField";
import { Toggle } from "@/components/ui/Toggle";
import { SegmentedControl } from "@/components/ui/SegmentedControl";
import { PaymentMethodsManager } from "@/components/forms/PaymentMethodsManager";
import { SyncStatusCard } from "@/components/common/SyncStatusCard";
import { WebScreen } from "@/components/web/WebScreen";
import { useAuth } from "@workos-inc/authkit-react";

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
  const { profile, currency, weekStart, defaultView, notifications } =
    useAppState();
  const actions = useAppActions();
  const { signOut } = useAuth();

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
          <div />
          <div className="flex items-end justify-end">
            <Button
              size="sm"
              variant="secondary"
              onClick={() => void signOut({ returnTo: window.location.origin })}
            >
              Sign out
            </Button>
          </div>
        </div>
      </Card>

      <div className="mb-[18px] grid grid-cols-2 items-start gap-[18px]">
        <Card className="p-[22px]">
          <h2 className="mb-[18px] font-display text-[17px] font-semibold text-ink">
            Preferences
          </h2>
          <div className="flex flex-col gap-[18px]">
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

        <Card className="p-[22px]">
          <h2 className="mb-[18px] font-display text-[17px] font-semibold text-ink">
            Notifications
          </h2>
          <div className="flex flex-col gap-4">
            {NOTIFICATION_DEFS.map((def) => (
              <div
                key={def.key}
                className="flex items-center justify-between gap-4"
              >
                <div className="min-w-0 flex-1">
                  <div className="text-sm font-medium text-ink">{def.label}</div>
                  <div className="text-xs text-muted">{def.sub}</div>
                </div>
                <Toggle
                  checked={notifications[def.key]}
                  onChange={() => actions.toggleNotification(def.key)}
                  label={def.label}
                />
              </div>
            ))}
          </div>
        </Card>
      </div>

      <Card className="mb-[18px] p-[22px]">
        <PaymentMethodsManager />
      </Card>
      <Card className="mb-[18px] p-[22px]"><SyncStatusCard /></Card>
    </WebScreen>
  );
}
