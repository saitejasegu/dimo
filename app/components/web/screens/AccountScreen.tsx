"use client";

import { useAppState } from "@/store/app-store";
import { Card } from "@/components/ui/Card";
import { Avatar } from "@/components/ui/Avatar";
import { TextField } from "@/components/ui/TextField";
import { SyncStatusCard } from "@/components/common/SyncStatusCard";
import { AccountSessionActions } from "@/components/common/AccountSessionActions";
import { WebScreen } from "@/components/web/WebScreen";

export function AccountScreen() {
  const { profile } = useAppState();

  return (
    <WebScreen>
      <div className="mb-[22px]">
        <div className="font-display text-[28px] font-semibold text-ink">
          Account
        </div>
        <div className="mt-1 text-[13px] text-muted">
          Manage your profile and account access.
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

      <Card className="mb-[18px] p-[22px]"><SyncStatusCard /></Card>
      <Card className="mb-[18px] p-[22px]">
        <AccountSessionActions />
      </Card>
    </WebScreen>
  );
}
