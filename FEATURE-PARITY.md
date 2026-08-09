# Dimo — iOS ↔ Android feature parity report

Generated 2026-08-09 against `main` @ `9772708`.

Scope: `ios-native/Dimo/` (SwiftUI + GRDB, 28.7k LOC) vs
`android-native/app/src/main/` (Compose + Room, 14.7k LOC). Web/Electron are out
of scope except where they define the shared contract.

> **Status:** §1–§3 are the audit as of `9772708`, before any migration work.
> Every iOS-ahead gap they list has since been implemented on Android except the
> Email subsystem — see **§4** for what shipped and **§5** for why Email did
> not. Read §3 as the baseline, not as current state.

---

## 1. Executive summary

The two native clients share the same backend contract, sync protocol, auth
flow, local-first architecture, and domain selectors. Data-layer parity is
essentially complete — every entity type, sanitizer, outbox rule, hybrid-version
conflict rule and push/pull path is ported.

The gap is almost entirely in **product surface**, and it is asymmetric:

| | iOS ahead | Android ahead |
| --- | --- | --- |
| Whole subsystems | Email / Gmail / AI suggestions (9,442 LOC, 31 files) | — |
| Screens | — | Recurring bills list |
| Notable features | Stats period navigation, stats drill-down, filter chips, FX estimate labels, contact photos in lists, legal links | Notification preference toggles, category tint editor, in-context sync error banners, category delete from list |

**Headline:** Android is at ~90% parity on the core spending tracker and is
missing one entire pillar (Email suggestions). iOS is missing several smaller
but user-visible affordances that Android already ships, plus a Recurring
destination.

---

## 2. Navigation shell

| | iOS | Android |
| --- | --- | --- |
| Tabs | 5 — Home, Stats, Budgets, Lending, **Email** | 4 — Home, Stats, Budgets, Lending |
| Recurring | No destination. Reached only through the Home "Upcoming this month" sheet | Dedicated pushed screen (`RecurringScreen.kt`) reached from Home |
| Settings / Account | `NavigationStack` push + edge-swipe-back gesture | `store.view` state + system `BackHandler` |
| Payment methods | Card embedded inside Settings | Separate pushed screen |
| FAB | Home / Budgets / Lending | Home / Budgets / Lending ✅ |
| Tab badge | Email pending-purchase count | n/a |

`RecurringScreen` **is defined on iOS but never referenced**
(`ios-native/Dimo/Features/Stats/FeatureScreens.swift:504`) — it is dead code.
The equivalent iOS UX is the Upcoming sheet at `HomeScreen.swift:210`, which does
support "Show all", paused styling and tap-to-edit, but has no Add button and no
inline pause/resume.

---

## 3. Feature matrix

Legend: ✅ full · ⚠️ partial / different · ❌ missing

### Home / Activity

| Feature | iOS | Android | Notes |
| --- | --- | --- | --- |
| Greeting header + avatar → Settings | ✅ | ✅ | |
| Month hero (spent, budget left) | ✅ | ⚠️ | iOS shows transaction count + "Budget left"; Android shows a left/over-budget caption (`HomeScreen.kt:133`) |
| Upcoming bills | ✅ sheet with "Show all", totals, paused pills, urgency colour | ⚠️ inline top-3 card + "See all" → Recurring screen | |
| Day-grouped transaction list | ✅ | ✅ | |
| Pagination | ✅ auto-load on scroll (`HomeScreen.swift:408`) | ⚠️ manual "Load more" button (`HomeScreen.kt:260`) | |
| Long-press multi-select + bulk delete | ✅ | ✅ | |
| Filter sheet (search, dates, categories, methods) | ✅ | ✅ | |
| Filter apply semantics | Draft → **Apply** commits; debounced match count | ⚠️ Mutates `store.filter` live; Apply only closes the sheet | Android has no cancel path |
| Removable active-filter chips | ✅ (`HomeScreen.swift:427`) | ❌ only a "Clear" link | |
| Foreign-currency source amount on rows | ❌ | ✅ (`HomeScreen.kt:496`) | |
| Payment method in row subtitle | ❌ | ✅ | |
| Sync error banner on screen | ❌ | ✅ | |

### Stats

| Feature | iOS | Android |
| --- | --- | --- |
| Range picker (synced default) | ✅ | ✅ |
| Hero (scope total, average label) | ✅ | ✅ |
| **Period navigation** (‹ current period ›) | ✅ `statsPeriodOffset`, `hasEarlierData`, `periodLabel` | ❌ not implemented — no offset in store or selectors |
| **Horizontal swipe between periods** | ✅ (`FeatureScreens.swift:149`) | ❌ |
| Trend bars, selectable month | ✅ | ✅ |
| Auto-scroll bars to latest | ✅ | ❌ |
| Category breakdown + expand | ✅ | ✅ |
| Top merchants + expand | ✅ | ✅ |
| **Tap a category/merchant → transaction list sheet** | ✅ (`StatsTransactionListSheet`) | ❌ rows are not tappable |
| Empty state | ❌ | ✅ |

Android's `StatsSelectors.kt` is missing `hasEarlierData`, `periodLabel`,
`statsAnchor`, `monthYearLabel`, `weekdayLabel`, `monthDayLabel` — the whole
period-offset family. This is the single largest functional gap outside Email.

### Budgets

| Feature | iOS | Android |
| --- | --- | --- |
| Month hero with progress bar | ✅ + "% used" and "N days to go" | ⚠️ progress bar only |
| Per-category budget cards | ✅ | ✅ + emoji tint + % badge |
| Tap card → edit category | ✅ | ✅ |
| **Delete category from the list** | ❌ | ✅ with linked-transaction count in the confirm |
| Suggested budgets | ✅ sparkles button in header → sheet | ✅ inline CTA card → sheet |
| Suggested-budget multi-select + apply | ✅ | ✅ |
| Empty state | ❌ | ✅ |

### Recurring

| Feature | iOS | Android |
| --- | --- | --- |
| Dedicated list screen | ❌ (dead `RecurringScreen`) | ✅ |
| Monthly commitment hero | ✅ (unreachable) | ✅ |
| Add recurring bill button | ❌ (only via Add-expense "Recurring" checkbox) | ✅ |
| Inline pause / resume | ❌ (pause lives on the edit sheet's primary button) | ✅ badge toggle |
| Yearly badge | ❌ | ✅ |
| **FX estimate label ("≈ ₹1,200 today")** | ✅ `Recurring.convertedEstimateLabel` | ❌ field does not exist in the Android UI model (`Entities.kt:382`) |
| Edit / delete / backfill history | ✅ (unified `ExpenseEditorSheet`) | ✅ (separate `RecurringSheet`) |

### Lending

| Feature | iOS | Android |
| --- | --- | --- |
| Summary / Transactions segmented view | ✅ | ✅ |
| Owed-to-me / I-owe hero | ✅ | ✅ |
| Contact grouping by `contactId` | ✅ | ✅ |
| All four kinds (lent/repaid/borrowed/returned) | ✅ | ✅ — **`LendKind.fromWire` no longer coerces to `lent`**; `LendSheet.kt:208` offers "I lent" / "I borrowed" |
| Settlement cap via `settlementLimit` | ✅ | ✅ |
| Share unsettled cycle as plain text | ✅ `UIActivityViewController` | ✅ `ACTION_SEND`, byte-compatible format |
| **Contact photos in list rows** | ✅ `ContactsLoader.thumbnailImage(contactId:)` | ❌ initials only — photos appear only in the contact picker (`LendSheet.kt:316`) |
| History pagination | ✅ `LendSelectors.paginateByDay` | ❌ renders every lend |

> `AGENTS.md` (Platform rules → Lending) still says Android coerces unknown
> `kind` to `lent` and lacks borrowing UI. **That is now stale** — the enum,
> `signedAmount`, the balance selectors and the entry form are all ported.
> Worth correcting in the doc.

### Add / edit expense

| Feature | iOS | Android |
| --- | --- | --- |
| Amount keypad + live conversion caption | ✅ | ✅ |
| Merchant autocomplete chips | ✅ | ✅ (also restores payment method) |
| Category dropdown + inline "add category" | ✅ | ✅ |
| Payment method field + "manage" | ✅ | ✅ |
| Per-entry currency picker | ✅ | ✅ |
| Date (+ time) picker | ✅ | ✅ |
| Recurring toggle from the add flow | ✅ checkbox + frequency menu | ✅ segmented One-off / Monthly / Yearly |
| Backfill past occurrences | ✅ alert prompt, only when start date is in the past, shows occurrence count | ⚠️ always-visible segmented control, no count |
| Edit mode keypad | ✅ | ⚠️ plain decimal text field |
| Delete from sheet | ✅ | ✅ |
| Email-suggestion review mode, duplicate linking, source-email viewer | ✅ | n/a (no Email subsystem) |

### Categories

| Feature | iOS | Android |
| --- | --- | --- |
| Emoji + name + optional monthly budget | ✅ | ✅ |
| 6-month lookback spend hint + suggested budget | ✅ | ✅ |
| **Tint picker (Neutral / Green)** | ❌ — `CategoryDraft.tint` exists (`AppStore.swift:1302`) but no UI | ✅ (`CategorySheet.kt:197`) |
| Delete with linked-transaction warning | ✅ | ✅ |

### Settings

| Feature | iOS | Android |
| --- | --- | --- |
| Theme / default stats range / currency | ✅ | ✅ |
| Daily expense reminder + time picker | ✅ | ✅ |
| Notification-permission-denied hint → system settings | ✅ | ✅ (plus runtime `POST_NOTIFICATIONS` request flow) |
| **Synced notification toggles** (bills, budget alerts, weekly summary, large expenses) | ❌ — `preferences.notifications` syncs but has no UI | ✅ (`SettingsScreen.kt:387`) |
| Payment method manager | ✅ inline card | ✅ separate screen (+ archive confirm dialog) |
| CSV import / export / template | ✅ | ✅ |
| Delete history | ✅ | ✅ |
| **Email settings section** | ✅ | ❌ |

### Account

| Feature | iOS | Android |
| --- | --- | --- |
| Read-only WorkOS profile | ✅ | ✅ |
| Cloud sync status, pending/blocked counts, last sync | ✅ | ✅ |
| Sync now / Sync now (full replace) | ✅ | ✅ (excludes `emailMessage` by design) |
| **Help & legal links** (Support, Privacy, Terms) | ✅ | ❌ — likely a Play Store submission blocker |
| Sign out / delete account with confirms | ✅ | ✅ |

### Email / Gmail / AI suggestions — **iOS only**

31 files, 9,442 LOC with no Android counterpart:

- Gmail OAuth, API client, message parser, credential vault, sync coordinator
- OpenRouter client routed through a Convex transport, model picker, pacing,
  structured-output validator, prompt builder
- Purchase-suggestion review, refund review, source-email viewer, duplicate
  detection and link-to-existing-transaction
- `BGTaskScheduler` background analysis
- `emailMessage` entity type, deliberately excluded from Android's pull, push,
  full upload and `clearWorkspace`

### Platform / infra

| | iOS | Android |
| --- | --- | --- |
| Auth | WorkOS PKCE via `ASWebAuthenticationSession`, Keychain | WorkOS PKCE via Custom Tabs, EncryptedSharedPreferences |
| Sync coordinator | debounce, retry backoff, revision subscription, batch split, paged pull/clear | ✅ same structure, 1:1 port |
| Exchange rates | Convex ECB pull + offline cache | ✅ (DataStore instead of UserDefaults) |
| Reminder scheduling | `UNUserNotificationCenter` | `AlarmManager` + boot receiver |
| Onboarding carousel + reminder opt-in | ✅ | ✅ 1:1 |
| Tests | `DomainTests.swift`, 4,320 lines | `DomainTests` + `RepositoryTests` + `DeviceLocalStoreTests`, 1,672 lines total |

---

## 4. Migration status — iOS-ahead features ported to Android

Everything listed as "iOS ahead" in §3 has been implemented on Android except
the Email subsystem (see §5). Verified with
`./gradlew :app:testProdDebugUnitTest :app:assembleProdDebug` — 86 tests, 0
failures, no new compiler warnings.

| Feature | Where |
| --- | --- |
| Stats period navigation | `StatsSelectors.statsAnchor` / `periodLabel` / `hasEarlierData`, `StatsScope.periodLabel`, `offset` threaded through `statsScope` + `trendBars`; `AppStore.statsPeriodOffset`; chevron row and horizontal swipe in `StatsScreen.kt` |
| Stats drill-down | Category and merchant rows open `StatsTransactionsSheet` (day-grouped, read-only) |
| Trend bars scroll to latest | `TrendBars` scrolls to `maxValue` on bar-set change |
| Recurring FX estimate | `Recurring.convertedEstimateLabel`, computed in `AppStore.hydrate`, rendered in `RecurringScreen` and the Home upcoming card; `refreshExchangeRates` re-hydrates on a rate-date change |
| Help & legal links | `LegalLink` card in `AccountScreen.kt` (Support / Privacy / Terms via `LocalUriHandler`) |
| Contact photos in lending rows | `ContactsLoader.photoUris` cache + `rememberContactPhotoUris`, passed to `ContactAvatar` in summary and history rows |
| Filter draft semantics | `FilterSheet` edits a local draft, commits via `onApply`; Clear commits an empty filter; match count debounced 180 ms |
| Removable filter chips | `FilterTag` / `filterTags` / `removeFilterTag` + `RemovableFilterChip` under the Activity header |
| Lending history pagination | `LendSelectors.paginateByDay` + paged Transactions tab |
| Auto-load on scroll | Shared `LoadingRow`; Home and Lending advance page size from a `LaunchedEffect` on the tail row (the "Load more" button is gone) |

New tests in `android-native/app/src/test/.../DomainTests.kt`: anchor at current
period, previous month covering the whole month, current/shifted labels, week
and multi-month label spans, contiguous non-overlapping periods,
`hasEarlierData` boundary, trend bars following the offset, and three
`paginateByDay` cases.

### Deliberate behavioural differences kept

- Android keeps its empty states, sync-error banners, category tint picker,
  notification toggles, Budgets delete action, Recurring screen, and foreign
  source amount on transaction rows. These are Android-ahead items; porting them
  to iOS is §6.
- The Home hero keeps Android's left/over-budget caption rather than iOS's
  transaction-count + "Budget left" split.
- The Home upcoming card still links to the Recurring screen instead of opening
  an iOS-style "Upcoming this month" sheet, because Android has a real Recurring
  destination and iOS does not.

## 5. Email / Gmail / AI suggestions — not ported

This is the one iOS-ahead item left. It is out of reach of a code-only port:

- **Scale.** 31 files, 9,442 LOC: Gmail OAuth + API client + message parser +
  credential vault + sync coordinator, an OpenRouter client routed through a
  Convex transport with pacing and a structured-output validator, suggestion and
  refund review UI, duplicate detection, and `BGTaskScheduler` background
  analysis.
- **External credentials.** It needs a Google Cloud OAuth client provisioned for
  the Android package name and signing SHA-1, plus OpenRouter routing config.
  Neither can be created from the repo.
- **Sync contract.** Android currently excludes `emailMessage` from pull, push,
  full upload and `clearWorkspace` *by design*, so iOS-owned email data survives
  an Android full cloud replacement (`AGENTS.md` → Native Android). Porting the
  feature means deliberately reversing that rule and re-testing the full
  replacement boundary on both clients.

Recommend treating it as a separate, scoped project rather than folding it into
a parity pass.

## 6. Remaining backlog — iOS side

These are the Android-ahead items from §3, unchanged by this migration:

1. **Notification preference toggles** — the four `preferences.notifications`
   fields already sync but are unreachable on iOS.
2. **Category tint picker** — `CategoryDraft.tint` is wired end-to-end but has no
   control in `NewCategorySheet`.
3. **A Recurring destination** — either wire up the dead `RecurringScreen` or
   fold Add / pause / resume into the Upcoming sheet.
4. **In-context sync error banners** — errors are only visible from Account.
5. Delete a category directly from the Budgets list.
6. Empty states on Stats and Budgets.
7. Show the original foreign amount on home transaction rows.
