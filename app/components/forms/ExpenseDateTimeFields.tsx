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
}

/** Shared date + time row for add/edit expense sheets and modals. */
export function ExpenseDateTimeFields({
  date,
  time,
  onDateChange,
  onTimeChange,
  className,
  weekStartsOn = 0,
}: ExpenseDateTimeFieldsProps) {
  const rowRef = useRef<HTMLDivElement>(null);
  const today = localDateKey(new Date());
  const nowTime = localTimeKey(new Date());

  return (
    <div ref={rowRef} className={cn("grid grid-cols-2 gap-3", className)}>
      <DateField
        label="Date"
        value={date}
        onChange={onDateChange}
        max={today}
        weekStartsOn={weekStartsOn}
        popoverContainerRef={rowRef}
      />
      <TimeField
        label="Time"
        value={time}
        onChange={onTimeChange}
        max={date === today || !date ? nowTime : undefined}
      />
    </div>
  );
}
