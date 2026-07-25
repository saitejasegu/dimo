# Android testing

## Unit tests (JVM)

```bash
cd android-native
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home   # or Temurin 21
./gradlew :app:testProdDebugUnitTest
```

Coverage today:

- `domain/DomainTests.kt` — ports of `ios-native/DimoTests/DomainTests.swift`
  (dates, formatting, stats, budgets, recurring, lending, CSV, exchange rates)
- `data/RepositoryTests.kt` — Room in-memory: fresh bootstrap, local write +
  outbox, LWW merge, tombstones, blocked outbox, full-upload boundaries

Add repository/sync cases when changing sync: offline write → reconnect,
conflicting versions, batch bisection isolating a permanent payload error,
sign-out DB deletion, and account-deletion clear boundaries (no `emailMessage`).

## Assemble

```bash
./gradlew :app:assembleProdDebug
```

## Emulator checklist

Needs an AVD (e.g. `dimo`) with hardware acceleration and network.

```bash
./gradlew :app:installProdDebug
adb shell am start -n app.dimo.android/.app.MainActivity
```

1. Cold start → Google via WorkOS → Home.
2. Airplane mode: add an expense; row appears; pending count > 0.
3. Go online; pending drains; expense appears on web and iOS.
4. Edit the same transaction on iOS and Android while Android is offline; on
   reconnect the higher `LogicalVersion` wins on both.
5. Budgets: category with monthly budget → progress + suggested budgets.
6. Lending: pick a contact, lend, repay (cap enforced), share unsettled summary;
   web remains read-only for lending.
7. Foreign-currency expense uses `exchangeRates:latest` and keeps the original
   amount on re-open.
8. CSV export from Android imports cleanly on web, and vice versa.
9. Settings → full cloud replacement from Android; on iOS confirm **email
   suggestions survived**.
10. Sign out → all `dimo-*.db` files gone; sign back in → cloud data restores.
