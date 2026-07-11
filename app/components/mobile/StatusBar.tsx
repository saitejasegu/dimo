/** Decorative iOS status bar shown at the top of the phone frame. */
export function StatusBar() {
  return (
    <div className="pointer-events-none absolute inset-x-0 top-0 z-20 flex h-[52px] items-center justify-between pl-[34px] pr-[30px] font-display text-[15px] font-semibold text-ink">
      <span>9:41</span>
      <span className="absolute left-1/2 top-[9px] h-[34px] w-[132px] -translate-x-1/2 rounded-full bg-ink-deep" />
      <span className="flex items-center gap-1.5">
        <span className="text-xs">5G</span>
        <span className="relative inline-block h-3 w-6 rounded-[3px] border-[1.5px] border-ink">
          <span className="absolute inset-[1.5px] right-1.5 rounded-[1px] bg-ink" />
        </span>
      </span>
    </div>
  );
}
