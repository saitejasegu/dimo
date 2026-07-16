# Drop App Store screenshots here

Capture from the iOS Simulator after opening the native app:

```bash
cd ios-native
xcodegen generate
open Dimo.xcodeproj
```

In Xcode: choose a large iPhone simulator (for example iPhone 16 Pro Max / latest 6.9"), then Product → Run.

1. Navigate to Home, Add expense, Activity, Budgets, Stats, Lending
2. File → Save Screen (or ⌘S)
3. Rename clearly, e.g. `01-home.png`

Required size is usually 1320×2868 or 1290×2796 for the largest iPhone slot.

See [../SUBMIT.md](../SUBMIT.md) for the full App Store submission checklist.
