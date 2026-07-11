const KEYS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"];

/** Numeric keypad for the mobile add-expense flow. */
export function AmountKeypad({ onPress }: { onPress: (key: string) => void }) {
  return (
    <div className="grid grid-cols-3 gap-2">
      {KEYS.map((key) => (
        <button
          type="button"
          key={key}
          onClick={() => onPress(key)}
          className="rounded-xl bg-canvas py-[13px] text-center font-display text-lg font-semibold text-ink transition-colors hover:bg-green-soft"
        >
          {key}
        </button>
      ))}
    </div>
  );
}
