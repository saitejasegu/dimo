# Android ↔ iOS UI look-and-feel parity

Status key: **Match** · **Close** · **Platform** (intentional native chrome)

Last updated after the visual parity pass on this branch.

---

## Fixed in this pass

| Area | Change |
| --- | --- |
| Add Expense category | Searchable `CategoryDropdown` + “+ Add category” (replaces chip tags) |
| Category + payment layout | Side-by-side row |
| Recurring category / frequency | Searchable dropdown + capsule Monthly/Yearly |
| Home filters | Searchable multi-select categories + payment flyout |
| Frequency / lend / lending sections | Capsule toggles H46 (ink selected) |
| Category sheet | 50×50 emoji well + budget preset chips |
| Content H padding | **22** (`ScreenContentPadding`) |
| FAB bottom | **68** (`FabBottomPadding`) |
| Primary save | H **54**, body 16 semibold |
| Screen titles | Display **24** semibold |
| Home greeting name | Display **22** semibold |
| Hero labels | Body **13** sentence case |
| Section labels | Body **12** medium, tracking 0.96 |
| Empty states | V pad **46**, title semibold |
| Sheet header | Top **22**, bottom **10** |
| List row pad | **12×11** on Home / Lending / Recurring |

---

## Remaining (platform-native by design)

| Element | iOS | Android | Status |
| --- | --- | --- | --- |
| Tab bar | 5 tabs + Liquid Glass (incl. Email) | 4 tabs + Material3 `NavigationBar` | **Platform** |
| FAB chrome | System borderedProminent | Custom 58×58 `FabButton` | **Platform** |
| Date / time pickers | Compact `DatePicker` | Material DatePicker / TimePicker dialogs | **Platform** |
| Contact picker | Searchable inline dropdown | System contacts + search list | **Close** / **Platform** |
