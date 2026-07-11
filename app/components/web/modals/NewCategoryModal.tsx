"use client";

import { useState } from "react";
import { useAppActions, useAppState } from "@/store/app-store";
import { deleteCategoryWarning } from "@/features/budgets/deleteCategoryWarning";
import { Modal } from "@/components/ui/Modal";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { NewCategoryForm } from "@/components/forms/NewCategoryForm";
import { DeleteIconButton } from "@/components/ui/DeleteIconButton";

export function NewCategoryModal() {
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
      <Modal
        onClose={closeOverlay}
        width={440}
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
        <NewCategoryForm onCancel={closeOverlay} />
      </Modal>

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
