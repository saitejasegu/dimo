import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

// Refresh ECB exchange rates before materialization so foreign-currency
// recurring bills convert against fresh rates. 18:15 UTC precedes the 18:35 job.
crons.cron(
  "refresh exchange rates",
  "15 18 * * *",
  internal.exchangeRates.refreshRates,
  {},
);

// 18:35 UTC is 00:05 IST on the following calendar day.
crons.cron(
  "materialize recurring transactions",
  "35 18 * * *",
  internal.recurringJobs.materializeDue,
  {},
);

// Hard-delete expired delete-tombstones (TOMBSTONE_RETENTION_DAYS, default 90).
crons.cron(
  "purge expired tombstones",
  "5 19 * * *",
  internal.tombstonePurge.purgeExpired,
  {},
);

export default crons;
