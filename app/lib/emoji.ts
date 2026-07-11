/** Take the last Unicode grapheme from a string (handles ZWJ emoji sequences). */
export function lastGrapheme(value: string): string {
  const trimmed = value.trim();
  if (!trimmed) return "";
  if (typeof Intl !== "undefined" && "Segmenter" in Intl) {
    const segments = [
      ...new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(
        trimmed,
      ),
    ];
    return segments.at(-1)?.segment ?? "";
  }
  return Array.from(trimmed).at(-1) ?? "";
}
