"use client";

import { useEffect } from "react";

const EDGE_WIDTH = 28;
const BACK_THRESHOLD = 72;

/**
 * Prevent browser back/forward edge swipes. On the Account screen, a deliberate
 * swipe from the left edge is translated into the app's own back action.
 */
export function useBrowserSwipeGuard({
  accountBackEnabled,
  onAccountBack,
}: {
  accountBackEnabled: boolean;
  onAccountBack: () => void;
}) {
  useEffect(() => {
    let startX: number | null = null;
    let startY = 0;
    let edge: "left" | "right" | null = null;
    let handled = false;

    const reset = () => {
      startX = null;
      edge = null;
      handled = false;
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
      handled = false;
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

      if (
        !handled &&
        accountBackEnabled &&
        edge === "left" &&
        deltaX >= BACK_THRESHOLD
      ) {
        handled = true;
        onAccountBack();
      }
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
  }, [accountBackEnabled, onAccountBack]);
}
