"use client";

import { useEffect, useRef, useState } from "react";
import { cn } from "@/lib/cn";
import { SearchIcon } from "@/components/ui/icons";

/** Keystroke-to-dispatch delay; filtering runs once typing pauses. */
const QUERY_DEBOUNCE_MS = 150;

interface SearchInputProps {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  className?: string;
}

/**
 * Locally controlled so typing repaints only this input. The committed value is
 * debounced before it reaches global state, which is what re-filters the transaction
 * list and re-renders every row.
 */
export function SearchInput({
  value,
  onChange,
  placeholder = "Search merchant or category",
  className,
}: SearchInputProps) {
  const [draft, setDraft] = useState(value);
  // Last value pushed upward, so an external reset ("Clear") is distinguishable from
  // our own echo and cannot clobber in-flight typing.
  const emittedRef = useRef(value);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (value === emittedRef.current) return;
    emittedRef.current = value;
    setDraft(value);
  }, [value]);

  useEffect(
    () => () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    },
    [],
  );

  const handleChange = (next: string) => {
    setDraft(next);
    if (timerRef.current) clearTimeout(timerRef.current);
    timerRef.current = setTimeout(() => {
      timerRef.current = null;
      emittedRef.current = next;
      onChange(next);
    }, QUERY_DEBOUNCE_MS);
  };

  return (
    <div
      className={cn(
        "flex items-center gap-2.5 rounded-xl border border-line bg-surface px-3.5 py-[9px]",
        className,
      )}
    >
      <SearchIcon className="shrink-0 text-faint" />
      <input
        value={draft}
        onChange={(e) => handleChange(e.target.value)}
        placeholder={placeholder}
        className="min-w-0 flex-1 bg-transparent text-base text-ink outline-none placeholder:text-faint"
      />
    </div>
  );
}
