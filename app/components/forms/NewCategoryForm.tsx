"use client";

import { money } from "@/lib/format";
import { cn } from "@/lib/cn";
import { useAppActions, useAppState } from "@/store/app-store";
import { TextField } from "@/components/ui/TextField";
import { Chip } from "@/components/ui/Chip";
import { Button } from "@/components/ui/Button";

const PRESETS = [1000, 2500, 5000, 10000];

export function NewCategoryForm({ onCancel }: { onCancel?: () => void }) {
  const { categoryDraft, limits } = useAppState();
  const actions = useAppActions();

  const name = categoryDraft.name.trim();
  const duplicate = Object.keys(limits).some(
    (c) => c.toLowerCase() === name.toLowerCase(),
  );
  const valid = name.length > 0 && !duplicate;
  const selectedLimit =
    parseInt(categoryDraft.limit.replace(/[^0-9]/g, ""), 10) || 0;

  return (
    <div>
      <TextField
        label="Name"
        value={categoryDraft.name}
        onChange={actions.setCategoryName}
        placeholder="e.g. Pets, Travel, Health"
        className="mb-4"
      />

      <TextField
        label={
          <>
            Monthly budget <span className="text-faint">(optional)</span>
          </>
        }
        value={categoryDraft.limit}
        onChange={actions.setCategoryLimit}
        placeholder="₹ amount"
        inputMode="numeric"
        className="mb-3"
      />

      <div className="mb-5 flex flex-wrap gap-2">
        {PRESETS.map((preset) => (
          <Chip
            key={preset}
            label={money(preset)}
            surface="canvas"
            selected={selectedLimit === preset}
            onClick={() => actions.setCategoryLimit(String(preset))}
          />
        ))}
      </div>

      <div className={cn("flex gap-3")}>
        {onCancel ? (
          <Button variant="secondary" onClick={onCancel} className="shrink-0">
            Cancel
          </Button>
        ) : null}
        <Button onClick={actions.saveCategory} enabled={valid} className="flex-1">
          Create category
        </Button>
      </div>
    </div>
  );
}
