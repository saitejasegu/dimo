"use client";

import type { ViewKey } from "@/lib/types";
import { money } from "@/lib/format";
import { cn } from "@/lib/cn";
import { useAppActions, useAppState } from "@/store/app-store";
import { useBudgets } from "@/features/budgets/hooks";
import { Button } from "@/components/ui/Button";
import { NavIcon, PlusIcon, ChevronIcon, type NavIconName } from "@/components/ui/icons";
import { Avatar } from "@/components/ui/Avatar";

interface NavDef {
  key: Extract<ViewKey, NavIconName>;
  label: string;
}

const NAV: NavDef[] = [
  { key: "home", label: "Home" },
  { key: "stats", label: "Stats" },
  { key: "budgets", label: "Budgets" },
  { key: "lending", label: "Lending" },
  { key: "settings", label: "Settings" },
];

export function Sidebar() {
  const { view, profile, currency } = useAppState();
  const actions = useAppActions();
  const { totals } = useBudgets();

  return (
    <aside className="flex w-64 shrink-0 flex-col bg-inverse px-[18px] pb-5 pt-[26px]">
      <div className="mb-[30px] flex items-center gap-[11px] px-2">
        <div className="flex h-[38px] w-[38px] items-center justify-center rounded-xl bg-green font-display text-[19px] font-bold text-white">
          D
        </div>
        <div>
          <div className="font-display text-[17px] font-semibold leading-tight text-side-text">
            Dimo
          </div>
          <div className="text-[11px] text-side-dim">Personal spending</div>
        </div>
      </div>

      <div className="mb-2 px-3.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-side-faint">
        Menu
      </div>
      <nav className="flex flex-col gap-[3px]">
        {NAV.map((item) => {
          const active = view === item.key;
          return (
            <button
              type="button"
              key={item.key}
              onClick={() => actions.setView(item.key)}
              className={cn(
                "flex items-center gap-3 rounded-xl px-3.5 py-[11px] transition-colors",
                active ? "bg-green/15" : "hover:bg-green/10",
              )}
            >
              <NavIcon
                name={item.key}
                size={20}
                className={active ? "text-green" : "text-side-dim"}
              />
              <span
                className={cn(
                  "text-sm",
                  active
                    ? "font-semibold text-side-text"
                    : "font-medium text-side-muted",
                )}
              >
                {item.label}
              </span>
            </button>
          );
        })}
      </nav>

      <Button
        variant="accent"
        onClick={() => actions.openOverlay("add")}
        leftIcon={<PlusIcon size={18} />}
        fullWidth
        className="mt-[22px] justify-start"
      >
        Add expense
      </Button>

      <div className="flex-1" />

      <div className="mb-3 rounded-[14px] bg-side-card px-3.5 py-3">
        <div className="mb-1.5 text-[11px] text-side-sub">
          Budget left in {new Date().toLocaleDateString(undefined, { month: "long" })}
        </div>
        <div
          className={`font-display text-[19px] font-semibold ${
            totals.left < 0 ? "text-danger" : "text-green-bright"
          }`}
        >
          {money(totals.left, currency)}
        </div>
      </div>

      <button
        type="button"
        onClick={actions.openAccount}
        className={cn(
          "flex items-center gap-[11px] rounded-xl px-2 py-1.5 text-left transition-colors",
          view === "account" ? "bg-green/15" : "hover:bg-green/10",
        )}
      >
        <Avatar
          initial={profile.name.charAt(0).toUpperCase()}
          src={profile.photoUrl}
          size={36}
          radius={11}
          tone="dark"
          textClassName="text-[15px]"
        />
        <span className="min-w-0 flex-1">
          <span className="block truncate text-[13px] font-medium text-side-text">
            {profile.name}
          </span>
          <span className="block text-[11px] text-side-dim">Account</span>
        </span>
        <ChevronIcon direction="right" className="text-side-dim" />
      </button>
    </aside>
  );
}
