"use client";

import type { ReactNode } from "react";
import { cn } from "@/lib/cn";
import { Button } from "@/components/ui/Button";

interface ConfirmDialogProps {
  open: boolean;
  title: string;
  message: ReactNode;
  confirmLabel?: string;
  cancelLabel?: string;
  /** Defaults to destructive (red) confirm action. */
  tone?: "danger" | "primary";
  onConfirm: () => void;
  onCancel: () => void;
}

/** Centered warning/confirm dialog matching the app modal language. */
export function ConfirmDialog({
  open,
  title,
  message,
  confirmLabel = "Delete",
  cancelLabel = "Cancel",
  tone = "danger",
  onConfirm,
  onCancel,
}: ConfirmDialogProps) {
  if (!open) return null;

  return (
    <div
      role="presentation"
      onClick={onCancel}
      className="fixed inset-0 z-40 flex animate-dim-in items-center justify-center bg-ink-deep/50 px-6"
    >
      <div
        role="alertdialog"
        aria-modal
        aria-labelledby="confirm-dialog-title"
        aria-describedby="confirm-dialog-message"
        onClick={(e) => e.stopPropagation()}
        className="w-full max-w-[360px] animate-pop-in rounded-[22px] bg-surface p-6 shadow-[0_18px_50px_rgba(13,21,18,0.18)]"
      >
        <h2
          id="confirm-dialog-title"
          className="font-display text-[19px] font-semibold text-ink"
        >
          {title}
        </h2>
        <p
          id="confirm-dialog-message"
          className="mt-2 text-[15px] leading-relaxed text-body"
        >
          {message}
        </p>
        <div className="mt-6 flex gap-3">
          <Button
            variant="secondary"
            onClick={onCancel}
            className="flex-1"
          >
            {cancelLabel}
          </Button>
          <Button
            variant={tone === "danger" ? "danger" : "primary"}
            onClick={onConfirm}
            className={cn(
              "flex-1",
              tone === "danger" &&
                "!border-danger !bg-danger !text-white hover:!bg-[#b04a33]",
            )}
          >
            {confirmLabel}
          </Button>
        </div>
      </div>
    </div>
  );
}
