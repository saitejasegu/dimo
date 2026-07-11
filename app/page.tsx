"use client";

import { AppStoreProvider } from "@/store/app-store";
import { useIsMobile } from "@/hooks/useIsMobile";
import { MobileApp } from "@/components/mobile/MobileApp";
import { WebApp } from "@/components/web/WebApp";

export default function Page() {
  const isMobile = useIsMobile();

  return (
    <AppStoreProvider>
      {isMobile === null ? (
        <div className="min-h-dvh bg-canvas" />
      ) : isMobile ? (
        <MobileApp />
      ) : (
        <WebApp />
      )}
    </AppStoreProvider>
  );
}
