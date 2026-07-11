/** Faux desktop-window title bar with traffic-light buttons. */
export function WindowChrome() {
  return (
    <div className="flex h-11 items-center gap-2 bg-ink-deep px-[18px]">
      <span className="h-3 w-3 rounded-full bg-[#ec6a5e]" />
      <span className="h-3 w-3 rounded-full bg-[#f4bf4f]" />
      <span className="h-3 w-3 rounded-full bg-[#61c554]" />
      <span className="flex-1 text-center font-display text-[13px] tracking-[0.02em] text-side-muted">
        Dimo — Expenses
      </span>
      <span className="w-[52px]" />
    </div>
  );
}
