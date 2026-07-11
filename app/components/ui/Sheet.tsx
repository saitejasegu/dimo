"use client";

import { useRef, type PointerEvent, type ReactNode } from "react";
import { cn } from "@/lib/cn";

interface SheetProps {
  onClose: () => void;
  title?: string;
  headerRight?: ReactNode;
  children: ReactNode;
  className?: string;
}

const DISMISS_OFFSET = 56;
const DISMISS_VELOCITY = 0.28;
const CAPTURE_OFFSET = 4;
const DISMISS_MS = 160;

function isInteractiveTarget(target: EventTarget | null) {
  if (!(target instanceof Element)) return false;
  return Boolean(
    target.closest(
      "input, textarea, select, button, a, label, [role='button'], [contenteditable='true']",
    ),
  );
}

/** Mobile bottom sheet: dimmed backdrop + upward-sliding panel with a handle. */
export function Sheet({
  onClose,
  title,
  headerRight,
  children,
  className,
}: SheetProps) {
  const panelRef = useRef<HTMLDivElement>(null);
  const backdropRef = useRef<HTMLButtonElement>(null);

  const active = useRef(false);
  const closing = useRef(false);
  const startY = useRef(0);
  const lastY = useRef(0);
  const lastTime = useRef(0);
  const velocity = useRef(0);
  const offsetRef = useRef(0);

  function applyOffset(next: number) {
    offsetRef.current = next;
    const panel = panelRef.current;
    const backdrop = backdropRef.current;
    if (panel) {
      panel.style.transform = `translateY(${next}px)`;
    }
    if (backdrop) {
      const progress = Math.min(1, next / 240);
      backdrop.style.opacity = String(1 - progress * 0.85);
    }
  }

  function setDragging(on: boolean) {
    const panel = panelRef.current;
    if (!panel) return;
    panel.classList.toggle("touch-none", on);
    panel.classList.toggle("transition-none", on);
    if (on) {
      panel.style.transition = "none";
    }
  }

  function finishDrag(e: PointerEvent<HTMLDivElement>) {
    if (!active.current || closing.current) return;
    active.current = false;
    setDragging(false);

    if (e.currentTarget.hasPointerCapture(e.pointerId)) {
      e.currentTarget.releasePointerCapture(e.pointerId);
    }

    const shouldDismiss =
      offsetRef.current > DISMISS_OFFSET || velocity.current > DISMISS_VELOCITY;

    const panel = panelRef.current;
    if (shouldDismiss && panel) {
      closing.current = true;
      panel.style.transition = `transform ${DISMISS_MS}ms cubic-bezier(0.2, 0, 0.2, 1)`;
      panel.style.transform = "translateY(100%)";
      if (backdropRef.current) {
        backdropRef.current.style.transition = `opacity ${DISMISS_MS}ms ease-out`;
        backdropRef.current.style.opacity = "0";
      }
      window.setTimeout(onClose, DISMISS_MS);
      return;
    }

    if (panel) {
      panel.style.transition = "transform 160ms cubic-bezier(0.2, 0.9, 0.3, 1)";
    }
    applyOffset(0);
  }

  function onPointerDown(e: PointerEvent<HTMLDivElement>) {
    if (closing.current || e.button !== 0 || isInteractiveTarget(e.target)) return;
    active.current = true;
    startY.current = e.clientY;
    lastY.current = e.clientY;
    lastTime.current = performance.now();
    velocity.current = 0;
    setDragging(true);
  }

  function onPointerMove(e: PointerEvent<HTMLDivElement>) {
    if (!active.current || closing.current) return;

    const now = performance.now();
    const dt = Math.max(1, now - lastTime.current);
    velocity.current = (e.clientY - lastY.current) / dt;
    lastY.current = e.clientY;
    lastTime.current = now;

    const next = Math.max(0, e.clientY - startY.current);
    applyOffset(next);

    if (next > CAPTURE_OFFSET && !e.currentTarget.hasPointerCapture(e.pointerId)) {
      e.currentTarget.setPointerCapture(e.pointerId);
    }
  }

  return (
    <>
      <button
        ref={backdropRef}
        type="button"
        aria-label="Close"
        onClick={onClose}
        className="absolute inset-0 z-30 animate-dim-in bg-ink-deep/45"
      />
      <div
        ref={panelRef}
        role="dialog"
        aria-modal
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={finishDrag}
        onPointerCancel={finishDrag}
        className={cn(
          "absolute inset-x-0 bottom-0 z-[31] animate-sheet-up rounded-t-[28px] bg-surface px-6 pb-[max(2.25rem,env(safe-area-inset-bottom))] pt-3.5 touch-pan-y",
          className,
        )}
      >
        <div
          aria-hidden
          className="-mx-2 -mt-1 mb-3 flex touch-none justify-center py-3"
        >
          <div className="h-1 w-10 shrink-0 rounded-full bg-hairline" />
        </div>
        {title || headerRight ? (
          <div className="mb-4 flex items-center justify-between gap-3">
            {title ? (
              <h2 className="font-display text-lg font-semibold text-ink">
                {title}
              </h2>
            ) : (
              <span />
            )}
            {headerRight}
          </div>
        ) : null}
        {children}
      </div>
    </>
  );
}
