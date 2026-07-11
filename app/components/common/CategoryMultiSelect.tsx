"use client";

import { useEffect, useRef, useState } from "react";
import type { CategoryName } from "@/lib/types";
import { cn } from "@/lib/cn";
import { SearchIcon } from "@/components/ui/icons";

export function CategoryMultiSelect({
  options,
  value,
  emojiByName,
  onToggle,
  onClear,
}: {
  options: CategoryName[];
  value: CategoryName[];
  emojiByName: Map<string, string>;
  onToggle: (category: CategoryName) => void;
  onClear: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const rootRef = useRef<HTMLDivElement>(null);
  const searchRef = useRef<HTMLInputElement>(null);
  const filtered = options.filter((option) => option.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase()));

  useEffect(() => {
    if (!open) return;
    const outside = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    };
    document.addEventListener("pointerdown", outside);
    requestAnimationFrame(() => searchRef.current?.focus());
    return () => document.removeEventListener("pointerdown", outside);
  }, [open]);

  const label = value.length === 0 ? "All categories" : value.length === 1 ? value[0] : `${value.length} categories selected`;
  return <div ref={rootRef} className="relative min-w-0">
    <button type="button" aria-haspopup="listbox" aria-expanded={open} onClick={() => { setQuery(""); setOpen((current) => !current); }} className={cn("flex w-full items-center justify-between rounded-xl border bg-surface px-3.5 py-[11px] text-sm text-ink", open ? "border-green ring-2 ring-green/10" : "border-line")}>
      <span className="truncate">{label}</span><span aria-hidden className={cn("ml-2 text-xs text-muted transition-transform", open && "rotate-180")}>▾</span>
    </button>
    {open ? <div className="absolute inset-x-0 bottom-full z-[60] mb-2 rounded-xl border border-line bg-popup p-2 shadow-[0_16px_40px_rgba(0,0,0,0.24)]">
      <div className="mb-2 flex items-center gap-2 rounded-lg border border-line bg-surface px-3 py-2"><SearchIcon className="text-faint" /><input ref={searchRef} value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search categories" className="min-w-0 flex-1 bg-transparent text-sm text-ink outline-none placeholder:text-faint" /></div>
      <div role="listbox" aria-multiselectable className="max-h-40 overflow-y-auto">
        <button type="button" role="option" aria-selected={value.length === 0} onClick={onClear} className={cn("flex w-full items-center justify-between rounded-lg px-3 py-2.5 text-left text-sm", value.length === 0 ? "bg-green-soft font-medium text-green-deep" : "text-ink hover:bg-canvas")}><span>All categories</span>{value.length === 0 ? <span className="text-green">✓</span> : null}</button>
        {filtered.map((option) => { const selected = value.includes(option); const emoji = emojiByName.get(option); return <button key={option} type="button" role="option" aria-selected={selected} onClick={() => onToggle(option)} className={cn("flex w-full items-center justify-between rounded-lg px-3 py-2.5 text-left text-sm", selected ? "bg-green-soft font-medium text-green-deep" : "text-ink hover:bg-canvas")}><span>{emoji ? `${emoji} ${option}` : option}</span>{selected ? <span className="text-green">✓</span> : null}</button>; })}
        {filtered.length === 0 ? <div className="px-3 py-4 text-center text-sm text-faint">No categories found</div> : null}
      </div>
    </div> : null}
  </div>;
}
