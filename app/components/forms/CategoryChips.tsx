"use client";

import { useEffect, useRef, useState } from "react";
import type { CategoryName } from "@/lib/types";
import { cn } from "@/lib/cn";
import { useAppActions, useAppState } from "@/store/app-store";
import { SearchIcon } from "@/components/ui/icons";

/** Searchable single-select category dropdown with an add-category action. */
export function CategoryChips({
  categories,
  value,
  onChange,
  surface = "canvas",
  className,
  menuClassName,
}: {
  categories: CategoryName[];
  value: CategoryName;
  onChange: (category: CategoryName) => void;
  surface?: "white" | "canvas";
  selectedFirst?: boolean;
  className?: string;
  menuClassName?: string;
}) {
  const { categories: categoryEntities } = useAppState();
  const { openOverlay } = useAppActions();
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const rootRef = useRef<HTMLDivElement>(null);
  const searchRef = useRef<HTMLInputElement>(null);
  const emojiByName = new Map(categoryEntities.map((category) => [category.name, category.emoji]));
  const selectedEmoji = emojiByName.get(value);
  const filtered = categories.filter((category) =>
    category.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase()),
  );

  useEffect(() => {
    if (!open) return;
    const closeOnOutsidePress = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    };
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false);
    };
    document.addEventListener("pointerdown", closeOnOutsidePress);
    document.addEventListener("keydown", closeOnEscape);
    requestAnimationFrame(() => searchRef.current?.focus());
    return () => {
      document.removeEventListener("pointerdown", closeOnOutsidePress);
      document.removeEventListener("keydown", closeOnEscape);
    };
  }, [open]);

  return (
    <div ref={rootRef} className={cn("relative min-w-0", className)}>
      <button
        type="button"
        aria-haspopup="listbox"
        aria-expanded={open}
        onClick={() => {
          setQuery("");
          setOpen((current) => !current);
        }}
        className={cn(
          "flex w-full items-center justify-between rounded-xl border border-line px-4 py-3 text-left text-sm text-ink transition-colors",
          surface === "white" ? "bg-surface" : "bg-canvas",
          open && "border-green ring-2 ring-green/10",
        )}
      >
        <span className={cn("truncate font-medium", !value && "text-faint")}>
          {value
            ? selectedEmoji
              ? `${selectedEmoji} ${value}`
              : value
            : "Select category"}
        </span>
        <span aria-hidden className={cn("ml-3 text-xs text-muted transition-transform", open && "rotate-180")}>▾</span>
      </button>

      {open ? (
        <div
          className={cn(
            "absolute inset-x-0 top-full z-50 mt-2 overflow-hidden rounded-xl border border-line bg-popup p-2 shadow-[0_16px_40px_rgba(0,0,0,0.24)]",
            menuClassName,
          )}
        >
          <div className="mb-2 flex items-center gap-2 rounded-lg border border-line bg-surface px-3 py-2">
            <SearchIcon className="shrink-0 text-faint" />
            <input
              ref={searchRef}
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Search categories"
              className="min-w-0 flex-1 bg-transparent text-base text-ink outline-none placeholder:text-faint"
            />
          </div>
          <div role="listbox" className="max-h-52 overflow-y-auto">
            {filtered.length === 0 ? (
              <div className="px-3 py-4 text-center text-sm text-faint">No categories found</div>
            ) : filtered.map((category) => {
              const selected = category === value;
              const emoji = emojiByName.get(category);
              return (
                <button
                  key={category}
                  type="button"
                  role="option"
                  aria-selected={selected}
                  onClick={() => {
                    onChange(category);
                    setOpen(false);
                  }}
                  className={cn(
                    "flex w-full items-center justify-between rounded-lg px-3 py-2.5 text-left text-sm",
                    selected ? "bg-green-soft font-semibold text-green-deep" : "text-ink hover:bg-canvas",
                  )}
                >
                  <span>{emoji ? `${emoji} ${category}` : category}</span>
                  {selected ? <span className="text-green">✓</span> : null}
                </button>
              );
            })}
          </div>
          <div className="mt-1 border-t border-line-soft pt-1">
            <button
              type="button"
              onClick={() => {
                setOpen(false);
                openOverlay("category");
              }}
              className="w-full rounded-lg px-3 py-2.5 text-left text-sm font-medium !text-green hover:bg-canvas"
            >
              + Add category
            </button>
          </div>
        </div>
      ) : null}
    </div>
  );
}
