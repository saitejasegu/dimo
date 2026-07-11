import { cn } from "@/lib/cn";

interface ToggleProps {
  checked: boolean;
  onChange: () => void;
  label?: string;
}

/** iOS-style switch used for notification preferences. */
export function Toggle({ checked, onChange, label }: ToggleProps) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      onClick={onChange}
      className={cn(
        "relative h-[26px] w-[46px] shrink-0 rounded-full transition-colors",
        checked ? "bg-green" : "bg-[#d7ded9]",
      )}
    >
      <span
        className={cn(
          "absolute top-[3px] h-5 w-5 rounded-full bg-white shadow-[0_1px_3px_rgba(13,21,18,0.25)] transition-[left]",
          checked ? "left-[23px]" : "left-[3px]",
        )}
      />
    </button>
  );
}
