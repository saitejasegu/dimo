"use client";

import { useRef } from "react";
import { useAppActions, useAppState } from "@/store/app-store";
import { useAccountSwipeBack } from "@/hooks/useAccountSwipeBack";
import { Card } from "@/components/ui/Card";
import { Avatar } from "@/components/ui/Avatar";
import { TextField } from "@/components/ui/TextField";
import { ChevronIcon } from "@/components/ui/icons";
import { SyncStatusCard } from "@/components/common/SyncStatusCard";
import { AccountSessionActions } from "@/components/common/AccountSessionActions";

export function AccountScreen() {
  const { profile } = useAppState();
  const actions = useAppActions();
  const panelRef = useRef<HTMLDivElement>(null);
  useAccountSwipeBack(panelRef, actions.closeAccount);

  return (
    <div
      ref={panelRef}
      className="absolute inset-0 z-[18] flex animate-account-in flex-col overflow-hidden bg-canvas shadow-[-12px_0_32px_rgba(0,0,0,0.12)]"
    >
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

        <Card className="mb-3.5 p-5"><SyncStatusCard /></Card>

        <Card className="mb-3.5 p-5">
          <AccountSessionActions />
        </Card>
      </div>
    </div>
  );
}
