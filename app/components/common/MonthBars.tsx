"use client";

import { useEffect, useRef } from "react";
import type { MonthBar } from "@/features/stats/selectors";
import { cn } from "@/lib/cn";

interface SizeConfig {
  containerHeight: number;
  maxBarHeight: number;
  minBarHeight: number;
  narrowWidth: number;
  wideWidth: number;
  amtClass: (wide: boolean) => string;
  labelClass: (wide: boolean) => string;
  gap: string;
}

const SIZES: Record<"mobile" | "web", SizeConfig> = {
  mobile: {
    containerHeight: 104,
    maxBarHeight: 62,
    minBarHeight: 8,
    narrowWidth: 30,
    wideWidth: 16,
    amtClass: (wide) => (wide ? "text-[8px]" : "text-[10px]"),
    labelClass: (wide) => (wide ? "text-[9px]" : "text-[11px]"),
    gap: "gap-1.5",
  },
  web: {
    containerHeight: 150,
    maxBarHeight: 100,
    minBarHeight: 10,
    narrowWidth: 44,
    wideWidth: 26,
    amtClass: (wide) => (wide ? "text-[9px]" : "text-[11px]"),
    labelClass: (wide) => (wide ? "text-[10px]" : "text-xs"),
    gap: "gap-[7px]",
  },
};

export function MonthBars({
  bars,
  onSelect,
  size = "mobile",
}: {
  bars: MonthBar[];
  onSelect: (label: string) => void;
  size?: "mobile" | "web";
}) {
  const cfg = SIZES[size];
  const scrollerRef = useRef<HTMLDivElement>(null);
  const scrollable = bars.length > 7;
  const lastBarKey = bars.at(-1)?.key;

  useEffect(() => {
    const scroller = scrollerRef.current;
    if (!scroller || !scrollable) return;
    const frame = requestAnimationFrame(() => {
      scroller.scrollLeft = scroller.scrollWidth - scroller.clientWidth;
    });
    return () => cancelAnimationFrame(frame);
  }, [bars.length, lastBarKey, scrollable]);

  return (
    <div
      ref={scrollerRef}
      className={cn(
        "overflow-y-hidden",
        scrollable &&
          "overflow-x-auto overscroll-x-contain [scrollbar-width:none] [&::-webkit-scrollbar]:hidden",
      )}
      data-no-tab-swipe={scrollable ? "" : undefined}
    >
      <div
        className="flex min-w-full items-end gap-0.5"
        style={{ height: cfg.containerHeight }}
      >
        {bars.map((bar) => {
          const barHeight = Math.max(
            cfg.minBarHeight,
            Math.round(bar.heightRatio * cfg.maxBarHeight),
          );
          return (
            <button
              type="button"
              key={bar.key}
              onClick={() => onSelect(bar.key)}
              className={cn(
                "flex h-full flex-col items-center justify-end",
                scrollable ? "w-10 shrink-0" : "flex-1",
                cfg.gap,
              )}
            >
              <span
                className={cn(
                  "h-3.5 leading-none",
                  cfg.amtClass(bar.wide),
                  bar.selected ? "font-semibold text-green" : "text-muted",
                )}
              >
                {bar.display}
              </span>
              <span
                className={cn(
                  "w-full rounded-t-md",
                  bar.selected ? "bg-green" : "bg-bar",
                )}
                style={{
                  maxWidth: bar.wide ? cfg.wideWidth : cfg.narrowWidth,
                  height: barHeight,
                  borderRadius: "6px 6px 3px 3px",
                }}
              />
              <span
                className={cn(
                  cfg.labelClass(bar.wide),
                  bar.selected ? "font-semibold text-green" : "text-faint",
                )}
              >
                {bar.label}
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
}
