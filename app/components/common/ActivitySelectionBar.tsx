"use client";

import { useState } from "react";
import { useAppActions } from "@/store/app-store";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { DeleteIconButton } from "@/components/ui/DeleteIconButton";
import { cn } from "@/lib/cn";
import type { ID } from "@/lib/types";

interface ActivitySelectionBarProps {
  selecting: boolean;
  selectedCount: number;
  allSelected: boolean;
  visibleCount: number;
  selectedIds: ID[];
  onEnter: () => void;
  onExit: () => void;
  onSelectAll: () => void;
  onDeselectAll: () => void;
  className?: string;
}

/** Select / Done controls plus select-all and bulk delete for Activity. */
export function ActivitySelectionBar({
  selecting,
  selectedCount,
  allSelected,
  visibleCount,
  selectedIds,
  onEnter,
  onExit,
  onSelectAll,
  onDeselectAll,
  className,
}: ActivitySelectionBarProps) {
  const { deleteTransactions } = useAppActions();
  const [confirmOpen, setConfirmOpen] = useState(false);

  if (!selecting) {
    return (
      <div className={className}>
        <Button
          variant="secondary"
          size="sm"
          onClick={onEnter}
          className={cn(
            "!px-3.5 !py-2 text-[13px]",
            visibleCount === 0 && "pointer-events-none opacity-40",
          )}
        >
          Select
        </Button>
      </div>
    );
  }

  return (
    <div className={className}>
      <div className="flex flex-wrap items-center gap-2">
        <Button
          variant="secondary"
          size="sm"
          onClick={onExit}
          className="!px-3.5 !py-2 text-[13px]"
        >
          Done
        </Button>
        <Button
          variant="secondary"
          size="sm"
          onClick={allSelected ? onDeselectAll : onSelectAll}
          className={cn(
            "!px-3.5 !py-2 text-[13px]",
            visibleCount === 0 && "pointer-events-none opacity-40",
          )}
        >
          {allSelected ? "Deselect all" : "Select all"}
        </Button>
        {selectedCount > 0 ? (
          <span className="text-[13px] text-muted">
            {selectedCount} selected
          </span>
        ) : null}
        <DeleteIconButton
          aria-label={
            selectedCount === 0
              ? "Delete selected"
              : `Delete ${selectedCount} selected`
          }
          onClick={() => {
            if (selectedCount === 0) return;
            setConfirmOpen(true);
          }}
          className={
            selectedCount === 0
              ? "pointer-events-none opacity-40"
              : undefined
          }
        />
      </div>

      <ConfirmDialog
        open={confirmOpen}
        title={
          selectedCount === 1
            ? "Delete transaction?"
            : `Delete ${selectedCount} transactions?`
        }
        message={
          selectedCount === 1
            ? "This permanently removes the selected transaction."
            : "This permanently removes the selected transactions."
        }
        confirmLabel="Delete"
        cancelLabel="Cancel"
        onCancel={() => setConfirmOpen(false)}
        onConfirm={() => {
          deleteTransactions(selectedIds);
          setConfirmOpen(false);
          onExit();
        }}
      />
    </div>
  );
}
