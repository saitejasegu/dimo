/** Builds delete-warning copy from non-zero counts only. */
export function deleteCategoryWarning(
  name: string,
  txCount: number,
  recCount: number,
) {
  const parts: string[] = [];
  if (txCount > 0) {
    parts.push(txCount === 1 ? "1 transaction" : `${txCount} transactions`);
  }
  if (recCount > 0) {
    parts.push(recCount === 1 ? "1 recurring bill" : `${recCount} recurring bills`);
  }

  if (parts.length === 0) {
    return `This permanently removes “${name}”.`;
  }

  if (parts.length === 1) {
    return `This permanently removes “${name}” and its ${parts[0]}.`;
  }

  return `This permanently removes “${name}” and its ${parts[0]} and ${parts[1]}.`;
}
