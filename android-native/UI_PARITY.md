# Android ↔ iOS UI look-and-feel parity

Status key: **Match** · **Close** · **Divergent** · **Missing**

Scope: visual tokens, layout metrics, and **control types** (dropdown vs chips, etc.). Functional feature parity (lending kinds, reminders, onboarding) is covered separately in PR #10.

---

## Headline gaps (most visible)

| Priority | Area | iOS | Android | Status |
| --- | --- | --- | --- | --- |
| P0 | Add Expense **category** | Searchable dropdown flyout + “Add category” | Wrapping **emoji chip tags** | **Divergent** |
| P0 | Add Expense **category + payment** layout | Side-by-side `HStack` | Stacked full-width | **Divergent** |
| P0 | Recurring **category** | Same searchable dropdown | Plain `LabeledDropdown` (no search, no add) | **Divergent** |
| P0 | Home **filters** categories/payment | Searchable multi-select flyout + checklist | Chip tags only | **Divergent** |
| P1 | Lend **contact** | Searchable inline dropdown + recent capsules | Contact picker / search list + recent chips | **Close** |
| P1 | Frequency / direction controls | Capsule toggles (height 46) | Chips or `SegmentedControl` (different chrome) | **Divergent** |
| P1 | FAB position | Trailing 22, **bottom 68** (above tab bar) | Trailing 22, **bottom 16** + navBars | **Divergent** |
| P1 | Content H padding | **22** | **18** | **Divergent** |
| P1 | Primary save button | H **54** | H **52** | **Close** |
| P2 | Screen titles | Display **24** | ScreenHeader **22** | **Close** |
| P2 | Section labels | Body **12** + kerning 0.96 | **11sp** uppercase + 0.9sp | **Divergent** |
| P2 | Hero eyebrow | Body **13** sentence case | **11sp** UPPERCASE | **Divergent** |
| P2 | Empty state vertical pad | **44–48** | **32** | **Divergent** |
| P2 | Tab bar | 5 tabs + Liquid Glass | 4 tabs + Material3 `NavigationBar` | **Divergent** (Email omitted by design) |

---

## 1. Design tokens

| Token | iOS | Android | Status |
| --- | --- | --- | --- |
| Color palette | `Theme.swift` hex pairs | `Theme.kt` same names/hex | **Match** |
| Display font | Space Grotesk | Space Grotesk | **Match** |
| Body font | IBM Plex Sans | IBM Plex Sans | **Match** |
| Type scale | Call-site sizes | Call-site + Material defaults | **Close** |
| Shared spacing constants | None (inline) | None (inline) | **Match** (both ad hoc) |

---

## 2. Shell / navigation / FAB

| Element | iOS | Android | Status |
| --- | --- | --- | --- |
| Tabs | Home, Stats, Budgets, Lending, **Email** | Home, Stats, Budgets, Lending | **Divergent** (Email intentional) |
| Tab chrome | System TabView / Liquid Glass | Material3 `NavigationBar`, labels 11sp | **Divergent** |
| FAB visibility | Home / Budgets / Lending | Same | **Match** |
| FAB implementation | System `.borderedProminent` large | Custom `FabButton` **58×58** | **Divergent** |
| FAB position | end **22**, bottom **68** | end **22**, bottom **16** + navBars | **Divergent** |
| List FAB clearance | bottom pad **110** | bottom pad **120** | **Close** |
| Content H padding | **22** | **18** | **Divergent** |

---

## 3. Control-type matrix (forms & sheets)

This is where Android feels “completely different,” not just smaller/larger.

### Add Expense

| Field | iOS control | Android control | Status |
| --- | --- | --- | --- |
| Amount (create) | Custom `AmountKeypad` (keys 52 / r14 / display 22) | Same `AmountKeypad` metrics | **Match** |
| Amount (edit) | Keypad / editor path | `DimoTextField` decimal | **Divergent** |
| Amount display | Display **44** bold | Display **36** bold | **Divergent** |
| Merchant | TextField + **suggestion chips when focused** | TextField + suggestion **list card** | **Close** |
| **Category** | **Searchable dropdown flyout** (search row 44, results 42, “+ Add category”) | **Wrapping CategoryChip tags** (emoji 22 + name 13sp) | **Divergent** |
| **Payment** | Non-searchable flyout (`PaymentMethodField`, trigger 48, rows 58 + manage) | Same component pattern | **Match** |
| Category + payment layout | **Side-by-side** | **Stacked** | **Divergent** |
| Date | Compact `DatePicker` date+time in well H50 | Material DatePicker + TimePicker, `DateField` H50 | **Close** |
| Recurring (create) | Checkbox + Monthly/Yearly menu pill | Chip tags: One-off / Monthly / Yearly | **Divergent** |
| Currency | Menu on amount (when multi-currency) | `LabeledDropdown` full field | **Divergent** |
| Notes | None | None | **Match** |
| Save CTA | H **54**, r **14**, body 16 semibold | PrimaryButton H **52**, r **14**, display 16 | **Close** |

### Recurring

| Field | iOS | Android | Status |
| --- | --- | --- | --- |
| Name | TextField well H50 | `LabeledTextField` | **Close** |
| Amount | TextField + decimal pad (no keypad) | `LabeledTextField` | **Match** |
| Category | **Searchable `CategoryDropdown`** | **`LabeledDropdown`** (no search / no add) | **Divergent** |
| Payment | `PaymentMethodField` | `PaymentMethodField` | **Match** |
| Frequency | Two **capsule toggles** H46 | **`Chip` tags** | **Divergent** |
| Start date | Compact DatePicker | `DateField` | **Close** |

### Category / budget sheet

| Field | iOS | Android | Status |
| --- | --- | --- | --- |
| Emoji | Single TextField **50×50** | Grid of **44×44** tiles | **Divergent** |
| Name | TextField H50 | `LabeledTextField` | **Close** |
| Budget | Decimal field + **wrapping preset chips** | Text field + suggested CTA card | **Divergent** |
| Tint | (via category model) | Chip: Neutral / Green | **Close** |

### Lend

| Field | iOS | Android | Status |
| --- | --- | --- | --- |
| Direction | Capsule chips H46 “I lent” / “I borrowed” | `SegmentedControl` (r12, pad 3, 13sp) | **Divergent** |
| Contact | **Searchable inline dropdown** (maxH 240, rows 48) | Contact intent / search list | **Close** |
| Recent | Horizontal avatar capsules | Recent `Chip`s | **Close** |
| Amount | TextField decimal | `LabeledTextField` | **Match** |
| Date | Compact DatePicker | `DateField` | **Close** |
| Comments | Optional TextField | Optional note field | **Match** |

### Settings / payment methods

| Field | iOS | Android | Status |
| --- | --- | --- | --- |
| Appearance / range / currency | `PillDropdown` H36 capsule | Same | **Match** |
| Reminder toggle / time | System Toggle + DatePicker | Switch + dialogs | **Close** |
| Payment type | Wrapping `Chip`s | Wrapping `Chip`s | **Match** |
| Payment name fields | TextField H52 | `LabeledTextField` | **Close** |

### Home filters

| Field | iOS | Android | Status |
| --- | --- | --- | --- |
| Search | TextField H50 | `DimoTextField` | **Close** |
| Categories | **Searchable multi-select flyout** | **Chip tags** | **Divergent** |
| Payment | Expandable checklist | **Chip tags** | **Divergent** |
| Date range | Compact date pickers | `OptionalDateField` H46 | **Close** |

---

## 4. Screen chrome (sizing / type)

| Element | iOS | Android | Status |
| --- | --- | --- | --- |
| Screen title | Display **24** semibold | ScreenHeader **22** Bold | **Close** |
| Home greeting name | Display **22** | Display **24** Bold | **Divergent** (Android larger) |
| Home greeting eyebrow | Body **13** | Body **13** | **Match** |
| Hero label | Body **13** sentence case | HeroLabel **11sp** UPPERCASE + tracking | **Divergent** |
| Hero amount (home) | Display **34** semibold | HeroAmount **34** Bold | **Close** |
| Hero card pad / radius | pad ~20–22, r **20** | pad **22×20**, r **20** | **Match** |
| Section title | Display **16** | SectionTitle **16** SemiBold | **Match** |
| Section / day label | Body **12** medium, kerning 0.96 | SectionLabel **11sp** UPPERCASE | **Divergent** |
| List row pad | often **12×11**, r **14** | often **14×12**, r **14** | **Close** |
| Category tint | **38×38**, r **11** | Same | **Match** |
| Empty state V pad | **44–48** | EmptyState **32** | **Divergent** |
| Progress bar | H **8** | H **8** (hero); some bars **4–6** | **Close** |
| Lending dual amounts | Display **26** | HeroAmount **26** | **Match** |
| Lending section switcher | Capsule H **46** | SegmentedControl (different) | **Divergent** |

---

## 5. Shared primitives inventory

| Primitive | iOS | Android | Notes |
| --- | --- | --- | --- |
| `PillDropdown` | ✓ H36 capsule | ✓ same | Match |
| `PaymentMethodField` | ✓ | ✓ | Match |
| `CategoryDropdown` (searchable) | ✓ | **Missing** | Android uses chips / plain dropdown |
| `AmountKeypad` | ✓ | ✓ | Match |
| Capsule dual toggle H46 | ✓ (freq / lend / sections) | Missing as shared | Android uses chips or SegmentedControl |
| `Chip` | ✓ | ✓ | Match |
| Sheet chrome | `SheetContainer` title 18, top 22 | `DimoBottomSheet` + `SheetHeader` (top 8 / title bottom 6) | Divergent |
| `FabButton` | Exists unused; shell uses system FAB | Used by shell | Divergent |
| Contact searchable dropdown | ✓ | Partial (list, not same flyout) | Close |

---

## Recommended fix order (control parity first)

1. **Port `CategoryDropdown`** to Android (search + results + “Add category”); use in Add Expense (side-by-side with payment) and Recurring.
2. **Align frequency / direction** to capsule dual toggles (H46) instead of chips / Material segmented where iOS uses capsules.
3. **Home FilterSheet**: searchable multi-select for categories; checklist/flyout for payment (not only chips).
4. **Metric pass**: content H pad 22; FAB bottom ~68 above tab; PrimaryButton 54; ScreenHeader 24; HeroLabel/SectionLabel sizes & casing; empty-state padding; sheet title top inset.
5. **Category sheet emoji**: single editable well vs tile grid — pick iOS pattern or document intentional Android choice.
6. Leave Material tab bar / system date pickers as platform-native unless Liquid Glass is in scope.
