"use client";

import { useState } from "react";
import { useAppActions, useAppState } from "@/store/app-store";
import { deleteCategoryWarning } from "@/features/budgets/deleteCategoryWarning";
import { Sheet } from "@/components/ui/Sheet";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { NewCategoryForm } from "@/components/forms/NewCategoryForm";
import { DeleteIconButton } from "@/components/ui/DeleteIconButton";

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
            <DeleteIconButton
              onClick={requestDelete}
              aria-label="Delete category"
            />
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
