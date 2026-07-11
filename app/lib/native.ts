type NativeWindow = Window & {
  Capacitor?: { isNativePlatform?: () => boolean };
  dimoDesktop?: { isElectron?: boolean; platform?: string };
};

/** True when running inside a Capacitor native shell (iOS/Android). */
export function isNativeApp(): boolean {
  if (typeof window === "undefined") return false;
  const capacitor = (window as NativeWindow).Capacitor;
  return Boolean(capacitor?.isNativePlatform?.());
}

/** True when running inside the Electron desktop shell. */
export function isElectronApp(): boolean {
  if (typeof window === "undefined") return false;
  return Boolean((window as NativeWindow).dimoDesktop?.isElectron);
}
