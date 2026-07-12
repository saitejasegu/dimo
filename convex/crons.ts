import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

// 18:35 UTC is 00:05 IST on the following calendar day.
crons.daily(
  "materialize recurring transactions",
  { hourUTC: 18, minuteUTC: 35 },
  internal.recurringJobs.materializeDue,
  {},
);

export default crons;
