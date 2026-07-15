# How to test Dimo Android

## Fast checks (no device)

```bash
cd android-native
# local.properties must contain: sdk.dir=/path/to/Android/sdk
./gradlew :app:testProdDebugUnitTest
./gradlew :app:assembleProdDebug
```

Unit tests cover domain selectors, dates, CSV, lending math, and permanent sync-error classification.

## Local emulator / device (recommended)

Cloud VMs usually lack `/dev/kvm`. Use a laptop or a VM with hardware acceleration.

1. Install Android Studio + SDK 35 + an API 34/35 system image.
2. Create an AVD (Pixel 6+) **with KVM/HAXM/WHPX enabled**.
3. Register WorkOS redirect URI `dimo://callback` on the public client used by Android.
4. Run:

```bash
cd android-native
./gradlew :app:installProdDebug
adb shell am start -n app.dimo.android/.app.MainActivity
```

Or open `android-native/` in Android Studio and Run the `prodDebug` variant.

### Manual smoke checklist

1. Cold start shows **Dimo** Sign-in with **Continue with Google**.
2. Sign in via WorkOS → lands on Home tab.
3. Add expense offline (airplane mode) → row appears locally.
4. Go online → sync clears pending outbox; web/iOS pull sees the expense.
5. Budgets: create category with monthly budget; spend against it.
6. Lending: pick contact, lend + repay (cap enforced); Share unsettled text.
7. Settings: theme/currency/CSV export+import; Account Sync now / full replace.
8. Sign out → local `dimo-*.db` files deleted.

## Cloud agent limitation

This Cursor cloud instance has no `/dev/kvm`. Software TCG emulation can boot the APK and briefly show the Sign-in brand, but Compose + first-frame work is too slow and triggers ANRs (`Dimo isn't responding` / `System UI isn't responding`). Use a KVM-backed machine for UI QA.
