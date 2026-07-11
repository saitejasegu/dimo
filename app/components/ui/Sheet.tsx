"use client";

import { useRef, useState, type PointerEvent, type ReactNode } from "react";
import { cn } from "@/lib/cn";

interface SheetProps {
  onClose: () => void;
  title?: string;
  children: ReactNode;
  className?: string;
}

const DISMISS_OFFSET = 96;
const DISMISS_VELOCITY = 0.45;
const CAPTURE_OFFSET = 10;

/** Mobile bottom sheet: dimmed backdrop + upward-sliding panel with a handle. */
export function Sheet({ onClose, title, children, className }: SheetProps) {
  const [offset, setOffset] = useState(0);
  const [dragging, setDragging] = useState(false);

  const active = useRef(false);
  const startY = useRef(0);
  const lastY = useRef(0);
  const lastTime = useRef(0);
  const velocity = useRef(0);
  const offsetRef = useRef(0);

  function finishDrag() {
    if (!active.current) return;
    active.current = false;
    setDragging(false);

    if (
      offsetRef.current > DISMISS_OFFSET ||
      velocity.current > DISMISS_VELOCITY
    ) {
      onClose();
      return;
    }

    offsetRef.current = 0;
    setOffset(0);
  }

  function onPointerDown(e: PointerEvent<HTMLDivElement>) {
    if (e.button !== 0) return;
    active.current = true;
    startY.current = e.clientY;
    lastY.current = e.clientY;
    lastTime.current = performance.now();
    velocity.current = 0;
    setDragging(true);
  }

  function onPointerMove(e: PointerEvent<HTMLDivElement>) {
    if (!active.current) return;

    const now = performance.now();
    const dt = now - lastTime.current;
    if (dt > 0) {
      velocity.current = (e.clientY - lastY.current) / dt;
    }
    lastY.current = e.clientY;
    lastTime.current = now;

    const next = Math.max(0, e.clientY - startY.current);
    offsetRef.current = next;
    setOffset(next);

    if (next > CAPTURE_OFFSET && !e.currentTarget.hasPointerCapture(e.pointerId)) {
      e.currentTarget.setPointerCapture(e.pointerId);
    }
  }

  const progress = Math.min(1, offset / 280);

  return (
    <>
      <button
        type="button"
        aria-label="Close"
        onClick={onClose}
        className="absolute inset-0 z-30 animate-dim-in bg-ink-deep/45"
        style={{ opacity: 1 - progress * 0.85 }}
      />
      <div
        role="dialog"
        aria-modal
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={finishDrag}
        onPointerCancel={finishDrag}
        className={cn(
          "absolute inset-x-0 bottom-0 z-[31] animate-sheet-up rounded-t-[28px] bg-surface px-6 pb-[max(2.25rem,env(safe-area-inset-bottom))] pt-3.5 touch-none",
          dragging ? "transition-none" : "transition-transform duration-200 ease-out",
          className,
        )}
        style={{ transform: offset ? `translateY(${offset}px)` : undefined }}
      >
        <div className="mx-auto mb-4 h-1 w-10 shrink-0 rounded-full bg-hairline" />
        {title ? (
          <h2 className="mb-4 font-display text-lg font-semibold text-ink">
            {title}
          </h2>
        ) : null}
        {children}
      </div>
    </>
  );
}
