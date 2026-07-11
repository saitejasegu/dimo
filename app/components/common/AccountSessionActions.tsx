"use client";

import { useState } from "react";
import { useAuth } from "@workos-inc/authkit-react";
import { useConvex } from "convex/react";
import { deleteAccountAndSignOut, signOutAndClearLocal } from "@/auth/signOut";
import { useAppActions } from "@/store/app-store";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { TransactionDataActions } from "@/components/common/TransactionDataActions";

/** Sign out and delete-account actions for the bottom of Account. */
export function AccountSessionActions() {
  const { signOut } = useAuth();
  const convex = useConvex();
  const { showToast } = useAppActions();
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [busy, setBusy] = useState(false);

  const runDelete = () => {
    if (busy) return;
    setBusy(true);
    void deleteAccountAndSignOut(convex, signOut)
      .catch((error) => {
        setBusy(false);
        setConfirmOpen(false);
        showToast(
          error instanceof Error ? error.message : "Could not delete account data",
        );
      });
  };

  return (
    <>
      <div className="flex flex-col gap-3">
        <Button
          variant="secondary"
          fullWidth
          onClick={() => {
            if (busy) return;
            void signOutAndClearLocal(signOut);
          }}
        >
          Sign out
        </Button>
        <TransactionDataActions />
        <Button
          variant="danger"
          fullWidth
          onClick={() => {
            if (busy) return;
            setConfirmOpen(true);
          }}
        >
          Delete account
        </Button>
        <p className="text-center text-[11px] leading-4 text-faint">
          Delete account permanently removes your data from this device and the cloud.
        </p>
      </div>

      <ConfirmDialog
        open={confirmOpen}
        title="Delete account?"
        message="This permanently deletes all expenses, budgets, and preferences from this device and the cloud. You will be signed out. This cannot be undone."
        confirmLabel={busy ? "Deleting…" : "Delete everything"}
        cancelLabel="Cancel"
        onCancel={() => {
          if (busy) return;
          setConfirmOpen(false);
        }}
        onConfirm={runDelete}
      />
    </>
  );
}
