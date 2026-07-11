"use client";

import { useEffect, useRef, type RefObject } from "react";

const EDGE_WIDTH = 32;
const DISMISS_OFFSET = 96;
const DISMISS_VELOCITY = 0.4;
const DISMISS_MS = 220;
const SNAP_MS = 200;

/**
 * Interactive iOS-style edge swipe to dismiss Account. Follows the finger with
 * translate3d, then finishes or snaps back. Caller should keep the previous
 * screen mounted underneath.
 */
export function useAccountSwipeBack(
  panelRef: RefObject<HTMLElement | null>,
  onBack: () => void,
) {
  const onBackRef = useRef(onBack);
  onBackRef.current = onBack;

  useEffect(() => {
    let startX: number | null = null;
    let startY = 0;
    let tracking = false;
    let dragging = false;
    let closing = false;
    let lastX = 0;
    let lastTime = 0;
    let velocity = 0;
    let offset = 0;

    const panel = () => panelRef.current;

    const setOffset = (next: number, withTransition?: string) => {
      offset = next;
      const el = panel();
      if (!el) return;
      if (withTransition !== undefined) {
        el.style.transition = withTransition;
      }
      el.style.transform = `translate3d(${next}px,0,0)`;
    };

    const resetTouch = () => {
      startX = null;
      tracking = false;
      dragging = false;
    };

    const onTouchStart = (event: TouchEvent) => {
      if (closing || event.touches.length !== 1) {
        resetTouch();
        return;
      }
      const touch = event.touches[0];
      if (touch.clientX > EDGE_WIDTH) {
        resetTouch();
        return;
      }
      startX = touch.clientX;
      startY = touch.clientY;
      lastX = touch.clientX;
      lastTime = performance.now();
      velocity = 0;
      tracking = true;
      dragging = false;
    };

    const onTouchMove = (event: TouchEvent) => {
      if (!tracking || startX == null || closing || event.touches.length !== 1) return;

      const touch = event.touches[0];
      const deltaX = touch.clientX - startX;
      const deltaY = touch.clientY - startY;

      if (!dragging) {
        if (Math.abs(deltaX) < 6 && Math.abs(deltaY) < 6) return;
        if (deltaX <= 0 || Math.abs(deltaY) > Math.abs(deltaX)) {
          resetTouch();
          return;
        }
        dragging = true;
        const el = panel();
        if (el) {
          el.style.animation = "none";
          el.style.transition = "none";
          el.style.willChange = "transform";
        }
      }

      // Block Safari's native back gesture once we own the swipe.
      event.preventDefault();

      const now = performance.now();
      const dt = Math.max(1, now - lastTime);
      velocity = (touch.clientX - lastX) / dt;
      lastX = touch.clientX;
      lastTime = now;

      setOffset(Math.max(0, deltaX));
    };

    const finish = () => {
      if (!dragging || closing) {
        resetTouch();
        return;
      }

      const shouldDismiss =
        offset > DISMISS_OFFSET || velocity > DISMISS_VELOCITY;
      const el = panel();
      const width = window.visualViewport?.width ?? window.innerWidth;

      if (shouldDismiss && el) {
        closing = true;
        setOffset(width, `transform ${DISMISS_MS}ms cubic-bezier(0.2, 0, 0.2, 1)`);
        window.setTimeout(() => {
          const node = panel();
          if (node) {
            node.style.willChange = "";
            node.style.transition = "";
          }
          onBackRef.current();
        }, DISMISS_MS);
        resetTouch();
        return;
      }

      setOffset(0, `transform ${SNAP_MS}ms cubic-bezier(0.2, 0.9, 0.3, 1)`);
      window.setTimeout(() => {
        const node = panel();
        if (node) {
          node.style.willChange = "";
          node.style.transition = "";
        }
      }, SNAP_MS);
      resetTouch();
    };

    document.addEventListener("touchstart", onTouchStart, { passive: true });
    document.addEventListener("touchmove", onTouchMove, { passive: false });
    document.addEventListener("touchend", finish, { passive: true });
    document.addEventListener("touchcancel", finish, { passive: true });

    return () => {
      document.removeEventListener("touchstart", onTouchStart);
      document.removeEventListener("touchmove", onTouchMove);
      document.removeEventListener("touchend", finish);
      document.removeEventListener("touchcancel", finish);
    };
  }, [panelRef]);
}
