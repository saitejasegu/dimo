"use client";

import { useRef } from "react";
import { cn } from "@/lib/cn";
import { localDateKey, localTimeKey } from "@/lib/dates";
import { DateField } from "@/components/ui/DateField";
import { TimeField } from "@/components/ui/TimeField";

interface ExpenseDateTimeFieldsProps {
  date: string;
  time: string;
  onDateChange: (date: string) => void;
  onTimeChange: (time: string) => void;
  className?: string;
  /** 0 = Sunday, 1 = Monday — forwarded to the calendar. */
  weekStartsOn?: 0 | 1;
  dateLabel?: string;
  allowFuture?: boolean;
  minDate?: string;
  showTime?: boolean;
}

/** Shared date + time row for add/edit expense sheets and modals. */
export function ExpenseDateTimeFields({
  date,
  time,
  onDateChange,
  onTimeChange,
  className,
  weekStartsOn = 0,
  dateLabel = "Date",
  allowFuture = false,
  minDate,
  showTime = true,
}: ExpenseDateTimeFieldsProps) {
  const rowRef = useRef<HTMLDivElement>(null);
  const today = localDateKey(new Date());
  const nowTime = localTimeKey(new Date());

  return (
    <div ref={rowRef} className={cn("grid gap-3", showTime ? "grid-cols-2" : "grid-cols-1", className)}>
      <DateField
        label={dateLabel}
        value={date}
        onChange={onDateChange}
        min={minDate}
        max={allowFuture ? undefined : today}
        weekStartsOn={weekStartsOn}
        popoverContainerRef={rowRef}
      />
      {showTime ? (
        <TimeField
          label="Time"
          value={time}
          onChange={onTimeChange}
          max={date === today || !date ? nowTime : undefined}
        />
      ) : null}
    </div>
  );
}
