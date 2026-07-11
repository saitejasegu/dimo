"use client";

import { useState } from "react";
import { useAppActions, useAppState } from "@/store/app-store";
import { deleteCategoryWarning } from "@/features/budgets/deleteCategoryWarning";
import { Sheet } from "@/components/ui/Sheet";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { NewCategoryForm } from "@/components/forms/NewCategoryForm";
import { TrashIcon } from "@/components/ui/icons";

export function NewCategorySheet() {
  const { categoryDraft, categories, transactions, recurring } = useAppState();
  const { closeOverlay, deleteCategory } = useAppActions();
  const [confirmOpen, setConfirmOpen] = useState(false);
  const editing = Boolean(categoryDraft.id);

  const category = categories.find((c) => c.id === categoryDraft.id);
  const txCount = categoryDraft.id
    ? transactions.filter((t) => t.categoryId === categoryDraft.id).length
    : 0;
  const recCount = categoryDraft.id
    ? recurring.filter((r) => r.categoryId === categoryDraft.id).length
    : 0;

  function requestDelete() {
    if (txCount > 0) {
      setConfirmOpen(true);
      return;
    }
    deleteCategory();
  }

  return (
    <>
      <Sheet
        onClose={closeOverlay}
        title={editing ? "Edit category" : "New category"}
        headerRight={
          editing ? (
            <button
              type="button"
              onClick={requestDelete}
              aria-label="Delete category"
              className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl border border-danger-line bg-danger-soft text-danger transition-colors hover:bg-[#fbe9e3]"
            >
              <TrashIcon />
            </button>
          ) : undefined
        }
      >
        <NewCategoryForm />
      </Sheet>

      <ConfirmDialog
        open={confirmOpen}
        title={`Delete ${category?.name ?? "category"}?`}
        message={deleteCategoryWarning(
          category?.name ?? "this category",
          txCount,
          recCount,
        )}
        confirmLabel="Delete"
        onCancel={() => setConfirmOpen(false)}
        onConfirm={() => {
          setConfirmOpen(false);
          deleteCategory();
        }}
      />
    </>
  );
}
