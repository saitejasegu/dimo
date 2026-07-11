"use client";

import { AppStoreProvider, useAppState } from "@/store/app-store";
import { useIsMobile } from "@/hooks/useIsMobile";
import { MobileApp } from "@/components/mobile/MobileApp";
import { WebApp } from "@/components/web/WebApp";

function ResponsiveApp() {
  const isMobile = useIsMobile();
  const { dataReady } = useAppState();

  if (!dataReady || isMobile === null) {
    return <div className="min-h-dvh bg-canvas" />;
  }

  return isMobile ? <MobileApp /> : <WebApp />;
}

export default function Page() {
  return (
    <AppStoreProvider>
      <ResponsiveApp />
    </AppStoreProvider>
  );
}
