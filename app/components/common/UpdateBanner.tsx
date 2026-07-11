"use client";

import { useAppUpdate } from "@/hooks/useAppUpdate";

/** Persistent prompt when a newer deploy is available. Click reloads the page. */
export function UpdateBanner() {
  const { updateAvailable, refresh } = useAppUpdate();
  if (!updateAvailable) return null;

  return (
    <button
      type="button"
      onClick={refresh}
      className="fixed bottom-[calc(4.25rem+env(safe-area-inset-bottom,0px))] left-1/2 z-[90] w-[min(calc(100%-2rem),22rem)] -translate-x-1/2 animate-toast-in rounded-full bg-inverse px-5 py-3 text-center text-[13px] font-medium text-side-text shadow-[0_12px_30px_-10px_rgba(13,21,18,0.45)] md:bottom-6"
    >
      New version available · Tap to refresh
    </button>
  );
}
