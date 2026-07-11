import { cn } from "@/lib/cn";
import { SearchIcon } from "@/components/ui/icons";

interface SearchInputProps {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  className?: string;
}

export function SearchInput({
  value,
  onChange,
  placeholder = "Search merchant or category",
  className,
}: SearchInputProps) {
  return (
    <div
      className={cn(
        "flex items-center gap-2.5 rounded-xl border border-line bg-surface px-3.5 py-[9px]",
        className,
      )}
    >
      <SearchIcon className="shrink-0 text-faint" />
      <input
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className="min-w-0 flex-1 bg-transparent text-base text-ink outline-none placeholder:text-faint"
      />
    </div>
  );
}
