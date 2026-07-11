"use client";

import { useAppActions } from "@/store/app-store";
import { Modal } from "@/components/ui/Modal";
import { AddRecurringForm } from "@/components/forms/AddRecurringForm";

export function AddRecurringModal() {
  const { closeOverlay } = useAppActions();
  return (
    <Modal onClose={closeOverlay} width={460} title="Add recurring">
      <AddRecurringForm onCancel={closeOverlay} />
    </Modal>
  );
}
