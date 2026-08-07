# App Privacy answers — iOS

Use these answers for Dimo's iOS App Privacy questionnaire in App Store
Connect. They reflect the production iOS code as of August 7, 2026. Re-audit
them whenever data handling changes.

## Top-level answers

- **Do you or your third-party partners collect data from this app?** Yes
- **Tracking:** No. Dimo does not use collected data to track users across
  other companies' apps or websites and does not show third-party ads.
- **Purpose for every type below:** App Functionality
- **Linked to the user's identity:** Yes

## Select these data types

| App Store Connect data type | Why Dimo collects it |
| --- | --- |
| Name | WorkOS account profile and synced workspace profile |
| Email Address | WorkOS account, workspace profile, and connected Gmail account |
| User ID | WorkOS/Convex ownership and sync |
| Device ID | Dimo's generated device identifier in conflict-resolution versions |
| Contacts | The name and address-book ID of a contact selected for a lending record; the full address book and contact photos do not leave the device |
| Emails or Text Messages | Optional Gmail message fields/body used for Email suggestions; normalized email records can sync and message content is sent to OpenRouter for analysis |
| Photos or Videos | Optional profile photo handled by the social sign-in provider and displayed from its hosted URL; address-book contact photos stay on-device |
| Payment Info | User-created payment-method labels used on expense records; Dimo does not collect card or bank-account numbers |
| Other Financial Info | Expense amounts, budgets, recurring bills, and lending balances |
| Purchase History | Logged expenses and optional Gmail purchase/refund suggestions |
| Other User Content | Notes, category names, recurring details, lending comments, preferences, and related user-entered content |

For every selected type answer:

- **Used for tracking:** No
- **Linked to the user's identity:** Yes
- **Purposes:** App Functionality only

Do not select advertising, marketing, analytics, or personalization purposes
for the native iOS app. Apple may collect its own App Store diagnostics under
Apple's policies; Dimo does not embed a native analytics or advertising SDK.

## Relevant recipients

- WorkOS handles sign-in profile data.
- Convex stores authenticated synced workspace records and proxies the shared
  free-tier OpenRouter request.
- Google supplies optional read-only Gmail data after separate consent.
- OpenRouter receives the prompt built from an email when the user enables
  Email analysis.

The public policy is `https://dimoapp.xyz/privacy`. The app-level
`PrivacyInfo.xcprivacy` mirrors the categories above and declares the app's
`UserDefaults` required-reason API use (`CA92.1`).
