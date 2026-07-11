/** True when running inside a Capacitor native shell (iOS/Android). */
export function isNativeApp(): boolean {
  if (typeof window === "undefined") return false;
  const capacitor = (
    window as Window & { Capacitor?: { isNativePlatform?: () => boolean } }
  ).Capacitor;
  return Boolean(capacitor?.isNativePlatform?.());
}
