/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as compat from "../compat.js";
import type * as crons from "../crons.js";
import type * as exchangeRates from "../exchangeRates.js";
import type * as migrations from "../migrations.js";
import type * as recurringJobs from "../recurringJobs.js";
import type * as syncTyped from "../syncTyped.js";
import type * as tombstonePurge from "../tombstonePurge.js";
import type * as values from "../values.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  compat: typeof compat;
  crons: typeof crons;
  exchangeRates: typeof exchangeRates;
  migrations: typeof migrations;
  recurringJobs: typeof recurringJobs;
  syncTyped: typeof syncTyped;
  tombstonePurge: typeof tombstonePurge;
  values: typeof values;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {
  migrations: import("@convex-dev/migrations/_generated/component.js").ComponentApi<"migrations">;
};
