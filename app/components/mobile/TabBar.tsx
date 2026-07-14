"use client";

import {
  useLayoutEffect,
  useRef,
  useState,
  type CSSProperties,
} from "react";
import { cn } from "@/lib/cn";
import { useAppActions, useAppState } from "@/store/app-store";
import { NavIcon } from "@/components/ui/icons";
import { MOBILE_TABS, mobileTabIndex } from "@/components/mobile/tabs";
import { useTabSwipeProgress } from "@/components/mobile/tabSwipeProgress";
import { TAB_SETTLE_MS } from "@/hooks/useTabPagerSwipe";

type PillBox = { left: number; width: number };

function lerp(a: number, b: number, t: number) {
  return a + (b - a) * t;
}

function indicatorForProgress(pills: PillBox[], progress: number): PillBox | null {
  if (pills.length === 0) return null;
  const max = pills.length - 1;
  const clamped = Math.min(max, Math.max(0, progress));
  const from = Math.floor(clamped);
  const to = Math.min(max, from + 1);
  const t = clamped - from;
  return {
    left: lerp(pills[from]!.left, pills[to]!.left, t),
    width: lerp(pills[from]!.width, pills[to]!.width, t),
  };
}

export function TabBar() {
  const { view, accountReturnView, navGlassOpacity } = useAppState();
  const { setView } = useAppActions();
  const { progress, interactive } = useTabSwipeProgress();
  const activeView = view === "account" ? (accountReturnView ?? view) : view;
  const activeIndex = mobileTabIndex(activeView);
  const highlightIndex = Math.round(
    Math.min(MOBILE_TABS.length - 1, Math.max(0, progress)),
  );
  const trackRef = useRef<HTMLDivElement>(null);
  const tabRefs = useRef<(HTMLButtonElement | null)[]>([]);
  const [pills, setPills] = useState<PillBox[]>([]);

  useLayoutEffect(() => {
    const track = trackRef.current;
    if (!track) return;

    function measure() {
      const trackRect = track!.getBoundingClientRect();
      setPills(
        tabRefs.current.map((button) => {
          if (!button) return { left: 0, width: 0 };
          const pill = button.firstElementChild as HTMLElement | null;
          const target = pill ?? button;
          const rect = target.getBoundingClientRect();
          return {
            left: rect.left - trackRect.left,
            width: rect.width,
          };
        }),
      );
    }

    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(track);
    return () => observer.disconnect();
  }, []);

  const indicator = indicatorForProgress(pills, progress);

  return (
    <nav
      aria-label="Primary navigation"
      className="pointer-events-none absolute inset-x-0 bottom-0 z-[15] px-3.5 pb-[max(0.55rem,env(safe-area-inset-bottom,0px))] pt-10"
      style={{ "--nav-glass-opacity": String(navGlassOpacity / 100) } as CSSProperties}
    >
      <div
        aria-hidden
        className="pointer-events-none absolute inset-x-0 bottom-0 h-[7.5rem] bg-gradient-to-t from-canvas from-35% via-canvas/85 to-transparent"
      />
      <div
        ref={trackRef}
        className="liquid-glass pointer-events-auto relative mx-auto grid max-w-md grid-cols-4 items-center gap-0.5 rounded-full px-1.5 py-1.5"
      >
        {indicator ? (
          <span
            aria-hidden
            className={cn(
              "pointer-events-none absolute top-1/2 h-10 -translate-y-1/2 rounded-full bg-green/18 shadow-[inset_0_1px_0_rgba(255,255,255,0.4)] motion-reduce:transition-none",
              !interactive && "transition-[left,width] ease-[cubic-bezier(0.2,0.8,0.2,1)]",
            )}
            style={{
              left: indicator.left,
              width: indicator.width,
              transitionDuration: interactive ? "0ms" : `${TAB_SETTLE_MS}ms`,
            }}
          />
        ) : null}
        {MOBILE_TABS.map((tab, index) => {
          const active = activeIndex === index;
          const highlighted = highlightIndex === index;
          return (
            <button
              type="button"
              key={tab.key}
              ref={(node) => {
                tabRefs.current[index] = node;
              }}
              onClick={() => setView(tab.key)}
              aria-current={active ? "page" : undefined}
              aria-label={tab.label}
              className={cn(
                "relative z-[1] flex items-center justify-center rounded-2xl !px-1 !py-1 transition-colors",
                highlighted ? "!text-green" : "!text-body",
              )}
            >
              <span className="flex h-10 w-full max-w-[3.25rem] items-center justify-center rounded-full">
                <NavIcon
                  name={tab.key}
                  className={highlighted ? "text-green" : "text-body"}
                />
              </span>
            </button>
          );
        })}
      </div>
    </nav>
  );
}
