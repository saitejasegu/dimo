type NativeWindow = Window & {
  dimoDesktop?: { isElectron?: boolean; platform?: string };
};

/** True when running inside the Electron desktop shell. */
export function isElectronApp(): boolean {
  if (typeof window === "undefined") return false;
  return Boolean((window as NativeWindow).dimoDesktop?.isElectron);
}
