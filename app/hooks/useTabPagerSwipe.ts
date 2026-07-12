"use client";

import {
  useEffect,
  useEffectEvent,
  useLayoutEffect,
  useRef,
  type RefObject,
} from "react";
import { MOBILE_TABS } from "@/components/mobile/tabs";
import { setTabSwipeProgress } from "@/components/mobile/tabSwipeProgress";

const AXIS_LOCK_PX = 8;
const COMMIT_RATIO = 0.28;
const COMMIT_VELOCITY = 0.45;
export const TAB_SETTLE_MS = 280;
const EDGE_RESISTANCE = 0.35;
const EASING = "cubic-bezier(0.2, 0.8, 0.2, 1)";

function prefersReducedMotion() {
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

function isSwipeBlocked(target: EventTarget | null) {
  if (!(target instanceof Element)) return false;
  return Boolean(
    target.closest(
      "[data-no-tab-swipe], .overflow-x-auto, .overflow-x-scroll, input, textarea, select",
    ),
  );
}

function progressFromOffset(index: number, dragOffset: number, width: number) {
  if (width <= 0) return index;
  return index - dragOffset / width;
}

/**
 * Interactive horizontal swipe between primary mobile tabs. Owns the track
 * transform imperatively so finger-follow and tab-bar taps share one path.
 */
export function useTabPagerSwipe({
  containerRef,
  trackRef,
  index,
  onIndexChange,
  enabled = true,
}: {
  containerRef: RefObject<HTMLElement | null>;
  trackRef: RefObject<HTMLElement | null>;
  index: number;
  onIndexChange: (nextIndex: number) => void;
  enabled?: boolean;
}) {
  const indexRef = useRef(index);
  const draggingRef = useRef(false);
  const settlingRef = useRef(false);
  const skipAnimateRef = useRef(true);
  const handleIndexChange = useEffectEvent(onIndexChange);

  const widthOf = () =>
    containerRef.current?.getBoundingClientRect().width ||
    window.visualViewport?.width ||
    window.innerWidth;

  const apply = (offsetPx: number, transition: string) => {
    const el = trackRef.current;
    if (!el) return;
    el.style.transition = transition;
    el.style.transform = `translate3d(${offsetPx}px,0,0)`;
  };

  const snapToIndex = (forIndex: number, animated: boolean) => {
    const duration = animated && !prefersReducedMotion() ? TAB_SETTLE_MS : 0;
    apply(
      -forIndex * widthOf(),
      duration > 0 ? `transform ${duration}ms ${EASING}` : "none",
    );
    return duration;
  };

  // Keep the track aligned when the active tab changes (tab bar or swipe commit).
  useLayoutEffect(() => {
    indexRef.current = index;
    setTabSwipeProgress(index, false);
    if (draggingRef.current || settlingRef.current) return;
    const animated = !skipAnimateRef.current;
    skipAnimateRef.current = false;
    snapToIndex(index, animated);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- width helpers close over latest refs
  }, [index]);

  useEffect(() => {
    const onResize = () => {
      if (draggingRef.current || settlingRef.current) return;
      snapToIndex(indexRef.current, false);
    };
    window.addEventListener("resize", onResize);
    return () => window.removeEventListener("resize", onResize);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (!enabled) return;

    let startX = 0;
    let startY = 0;
    let tracking = false;
    let lastX = 0;
    let lastTime = 0;
    let velocity = 0;
    let dragOffset = 0;

    const rubberBand = (delta: number) => {
      const atStart = indexRef.current <= 0 && delta > 0;
      const atEnd = indexRef.current >= MOBILE_TABS.length - 1 && delta < 0;
      if (!atStart && !atEnd) return delta;
      return delta * EDGE_RESISTANCE;
    };

    const resetTouch = () => {
      tracking = false;
      draggingRef.current = false;
      dragOffset = 0;
    };

    const onTouchStart = (event: TouchEvent) => {
      if (
        settlingRef.current ||
        event.touches.length !== 1 ||
        isSwipeBlocked(event.target)
      ) {
        resetTouch();
        return;
      }
      const touch = event.touches[0];
      startX = touch.clientX;
      startY = touch.clientY;
      lastX = touch.clientX;
      lastTime = performance.now();
      velocity = 0;
      dragOffset = 0;
      tracking = true;
      draggingRef.current = false;
    };

    const onTouchMove = (event: TouchEvent) => {
      if (!tracking || settlingRef.current || event.touches.length !== 1) return;

      const touch = event.touches[0];
      const deltaX = touch.clientX - startX;
      const deltaY = touch.clientY - startY;

      if (!draggingRef.current) {
        if (Math.abs(deltaX) < AXIS_LOCK_PX && Math.abs(deltaY) < AXIS_LOCK_PX) {
          return;
        }
        if (Math.abs(deltaY) >= Math.abs(deltaX)) {
          resetTouch();
          return;
        }
        draggingRef.current = true;
        const el = trackRef.current;
        if (el) el.style.willChange = "transform";
        apply(-indexRef.current * widthOf(), "none");
      }

      event.preventDefault();

      const now = performance.now();
      const dt = Math.max(1, now - lastTime);
      velocity = (touch.clientX - lastX) / dt;
      lastX = touch.clientX;
      lastTime = now;

      const width = widthOf();
      dragOffset = rubberBand(deltaX);
      apply(-indexRef.current * width + dragOffset, "none");
      setTabSwipeProgress(
        progressFromOffset(indexRef.current, dragOffset, width),
        true,
      );
    };

    const settleTo = (nextIndex: number) => {
      settlingRef.current = true;
      setTabSwipeProgress(nextIndex, false);
      const duration = snapToIndex(nextIndex, true);

      window.setTimeout(() => {
        const el = trackRef.current;
        if (el) el.style.willChange = "";
        settlingRef.current = false;
        resetTouch();
        if (nextIndex !== indexRef.current) {
          // Swipe already animated to the target; don't re-animate on setView.
          skipAnimateRef.current = true;
          handleIndexChange(nextIndex);
        }
      }, duration);
    };

    const finish = () => {
      if (!draggingRef.current || settlingRef.current) {
        resetTouch();
        return;
      }

      const width = widthOf();
      const current = indexRef.current;
      let next = current;

      if (
        Math.abs(dragOffset) > width * COMMIT_RATIO ||
        Math.abs(velocity) > COMMIT_VELOCITY
      ) {
        if (dragOffset < 0 && current < MOBILE_TABS.length - 1) next = current + 1;
        else if (dragOffset > 0 && current > 0) next = current - 1;
      }

      settleTo(next);
    };

    const node = containerRef.current;
    if (!node) return;

    node.addEventListener("touchstart", onTouchStart, { passive: true });
    node.addEventListener("touchmove", onTouchMove, { passive: false });
    node.addEventListener("touchend", finish, { passive: true });
    node.addEventListener("touchcancel", finish, { passive: true });

    return () => {
      node.removeEventListener("touchstart", onTouchStart);
      node.removeEventListener("touchmove", onTouchMove);
      node.removeEventListener("touchend", finish);
      node.removeEventListener("touchcancel", finish);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [containerRef, trackRef, enabled]);
}
