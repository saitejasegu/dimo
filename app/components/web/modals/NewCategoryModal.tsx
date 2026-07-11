"use client";

import { useAppActions } from "@/store/app-store";
import { Modal } from "@/components/ui/Modal";
import { NewCategoryForm } from "@/components/forms/NewCategoryForm";

export function NewCategoryModal() {
  const { closeOverlay } = useAppActions();
  return (
    <Modal onClose={closeOverlay} width={440} title="New category">
      <NewCategoryForm onCancel={closeOverlay} />
    </Modal>
  );
}
