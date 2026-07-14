import { cn } from "@/lib/cn";

export function Checkbox({
  checked,
  onChange,
  label,
  disabled = false,
}: {
  checked: boolean;
  onChange: (checked: boolean) => void;
  label: string;
  disabled?: boolean;
}) {
  return (
    <label className={cn("flex items-center gap-3", disabled ? "cursor-default opacity-70" : "cursor-pointer")}>
      <input
        type="checkbox"
        checked={checked}
        disabled={disabled}
        onChange={(event) => onChange(event.target.checked)}
        className="peer sr-only"
      />
      <span className="flex h-5 w-5 items-center justify-center rounded-md border border-line bg-canvas text-xs font-bold text-white peer-checked:border-green peer-checked:bg-green peer-focus-visible:ring-2 peer-focus-visible:ring-green/40">
        {checked ? "✓" : ""}
      </span>
      <span className="text-sm font-medium text-ink">{label}</span>
    </label>
  );
}
