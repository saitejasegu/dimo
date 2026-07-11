"use client";

import { useAppState } from "@/store/app-store";
import { Toast } from "@/components/ui/Toast";

/** Connects the store's transient toast to the presentational pill. */
export function Toaster({ variant }: { variant: "mobile" | "web" }) {
  const { toast } = useAppState();
  if (!toast) return null;

  return (
    <Toast
      message={toast}
      bottom={variant === "mobile" ? undefined : 24}
      withShadow={variant === "web"}
    />
  );
}
