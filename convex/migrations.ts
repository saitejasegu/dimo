import { Migrations } from "@convex-dev/migrations";
import { components } from "./_generated/api";
import type { DataModel } from "./_generated/dataModel";
import { typedFieldsFromPayload } from "./compat";

/**
 * Migrations component retained for future schema backfills.
 * The entities → typed / exchangeRates → entries backfills already ran; those
 * legacy tables are removed from the schema.
 */
export const migrations = new Migrations<DataModel>(components.migrations);

/** Test helper: explode a payload without writing (parity checks). */
export function explodePayloadForTest(payload: Record<string, unknown>) {
  return typedFieldsFromPayload(payload);
}
