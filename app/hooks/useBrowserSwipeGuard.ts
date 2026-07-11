"use client";

import { useEffect } from "react";

const EDGE_WIDTH = 28;

/**
 * Prevent browser back/forward edge swipes so in-app navigation stays in control.
 * Account dismiss is handled separately by useAccountSwipeBack.
 */
export function useBrowserSwipeGuard({ enabled = true }: { enabled?: boolean } = {}) {
  useEffect(() => {
    if (!enabled) return;

    let startX: number | null = null;
    let startY = 0;
    let edge: "left" | "right" | null = null;

    const reset = () => {
      startX = null;
      edge = null;
    };

    const onTouchStart = (event: TouchEvent) => {
      if (event.touches.length !== 1) {
        reset();
        return;
      }

      const touch = event.touches[0];
      const viewportWidth = window.visualViewport?.width ?? window.innerWidth;
      if (touch.clientX <= EDGE_WIDTH) edge = "left";
      else if (touch.clientX >= viewportWidth - EDGE_WIDTH) edge = "right";
      else edge = null;

      startX = edge ? touch.clientX : null;
      startY = touch.clientY;
    };

    const onTouchMove = (event: TouchEvent) => {
      if (startX == null || edge == null || event.touches.length !== 1) return;

      const touch = event.touches[0];
      const deltaX = touch.clientX - startX;
      const deltaY = touch.clientY - startY;
      const movingIntoPage = edge === "left" ? deltaX > 0 : deltaX < 0;
      const horizontalGesture = Math.abs(deltaX) > Math.abs(deltaY);

      if (!movingIntoPage || !horizontalGesture) return;

      // Cancel the browser's own back/forward navigation gesture.
      event.preventDefault();
    };

    document.addEventListener("touchstart", onTouchStart, { passive: true });
    document.addEventListener("touchmove", onTouchMove, { passive: false });
    document.addEventListener("touchend", reset, { passive: true });
    document.addEventListener("touchcancel", reset, { passive: true });

    return () => {
      document.removeEventListener("touchstart", onTouchStart);
      document.removeEventListener("touchmove", onTouchMove);
      document.removeEventListener("touchend", reset);
      document.removeEventListener("touchcancel", reset);
    };
  }, [enabled]);
}
