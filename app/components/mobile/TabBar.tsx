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

export function TabBar() {
  const { view, accountReturnView, navGlassOpacity } = useAppState();
  const { setView } = useAppActions();
  const activeView = view === "account" ? (accountReturnView ?? view) : view;
  const trackRef = useRef<HTMLDivElement>(null);
  const tabRefs = useRef<(HTMLButtonElement | null)[]>([]);
  const [indicator, setIndicator] = useState<{ left: number; width: number } | null>(
    null,
  );

  useLayoutEffect(() => {
    const track = trackRef.current;
    if (!track) return;

    function syncIndicator() {
      const activeIndex = mobileTabIndex(activeView);
      const button = tabRefs.current[activeIndex];
      if (!button) return;

      const pill = button.firstElementChild as HTMLElement | null;
      const target = pill ?? button;
      const trackRect = track!.getBoundingClientRect();
      const targetRect = target.getBoundingClientRect();

      setIndicator({
        left: targetRect.left - trackRect.left,
        width: targetRect.width,
      });
    }

    syncIndicator();

    const observer = new ResizeObserver(syncIndicator);
    observer.observe(track);
    return () => observer.disconnect();
  }, [activeView]);

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
        className="liquid-glass pointer-events-auto relative mx-auto grid max-w-md grid-cols-5 items-center gap-0.5 rounded-full px-1.5 py-1.5"
      >
        {indicator ? (
          <span
            aria-hidden
            className="pointer-events-none absolute top-1/2 h-10 -translate-y-1/2 rounded-full bg-green/18 shadow-[inset_0_1px_0_rgba(255,255,255,0.4)] transition-[left,width] duration-300 ease-[cubic-bezier(0.2,0.8,0.2,1)] motion-reduce:transition-none"
            style={{ left: indicator.left, width: indicator.width }}
          />
        ) : null}
        {MOBILE_TABS.map((tab, index) => {
          const active = mobileTabIndex(activeView) === index;
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
                active ? "!text-green" : "!text-body",
              )}
            >
              <span className="flex h-10 w-full max-w-[3.25rem] items-center justify-center rounded-full">
                <NavIcon name={tab.key} className={active ? "text-green" : "text-body"} />
              </span>
            </button>
          );
        })}
      </div>
    </nav>
  );
}
