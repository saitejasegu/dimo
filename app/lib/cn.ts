export type ClassValue =
  | string
  | number
  | null
  | boolean
  | undefined
  | ClassValue[];

/**
 * Tiny classNames helper. Flattens arrays and drops falsy values so components
 * can compose Tailwind classes conditionally without pulling in a dependency.
 */
export function cn(...inputs: ClassValue[]): string {
  const out: string[] = [];

  for (const input of inputs) {
    if (!input) continue;

    if (Array.isArray(input)) {
      const nested = cn(...input);
      if (nested) out.push(nested);
    } else {
      out.push(String(input));
    }
  }

  return out.join(" ");
}
