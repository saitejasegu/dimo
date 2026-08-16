package app.dimo.android.data.db

import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

/**
 * Schema migrations for the account-scoped database.
 *
 * A destructive fallback is deliberately not configured: the local store owns the
 * pending outbox, so wiping it on upgrade would silently drop writes that have not
 * reached Convex yet.
 *
 * `MIGRATION_1_2` is copied verbatim from the exported schema in
 * `app/schemas/app.dimo.android.data.db.DimoDatabase/2.json`. Room validates the
 * resulting schema against the exported hash on open, so those CREATE statements
 * must stay byte-identical — regenerate rather than hand-edit them.
 */
object Migrations {
  /** Adds the Email tab's synced entity table and its four device-local tables. */
  val MIGRATION_1_2 = object : Migration(1, 2) {
    override fun migrate(db: SupportSQLiteDatabase) {
      db.execSQL(
        "CREATE TABLE IF NOT EXISTS `syncedEmailMessages` (`key` TEXT NOT NULL, " +
          "`workspaceId` TEXT NOT NULL, `entityId` TEXT NOT NULL, `deleted` INTEGER NOT NULL, " +
          "`serverRevision` INTEGER NOT NULL, `accountId` TEXT NOT NULL, " +
          "`accountEmail` TEXT NOT NULL, `gmailMessageId` TEXT NOT NULL, " +
          "`threadId` TEXT NOT NULL, `rfcMessageId` TEXT, `senderName` TEXT, " +
          "`senderAddress` TEXT NOT NULL, `subject` TEXT NOT NULL, `snippet` TEXT NOT NULL, " +
          "`internalDate` INTEGER NOT NULL, `normalizedBodyText` TEXT, `analyzerType` TEXT, " +
          "`modelVersion` TEXT, `promptVersion` INTEGER, `classification` TEXT, " +
          "`merchant` TEXT, `amount` TEXT, `currency` TEXT, `occurredAt` INTEGER, " +
          "`categoryId` TEXT, `paymentMethodId` TEXT, `paymentLastFour` TEXT, " +
          "`reference` TEXT, `state` TEXT NOT NULL, `purchaseGroupId` TEXT, " +
          "`linkedTransactionId` TEXT, `analyzedAt` INTEGER, `reviewedAt` INTEGER, " +
          "`createdAt` INTEGER NOT NULL, `updatedAt` INTEGER NOT NULL, " +
          "`versionTimestamp` INTEGER NOT NULL, `versionCounter` INTEGER NOT NULL, " +
          "`versionDeviceId` TEXT NOT NULL, PRIMARY KEY(`key`))",
      )
      db.execSQL(
        "CREATE INDEX IF NOT EXISTS `index_syncedEmailMessages_workspaceId_entityId` " +
          "ON `syncedEmailMessages` (`workspaceId`, `entityId`)",
      )
      db.execSQL(
        "CREATE INDEX IF NOT EXISTS `index_syncedEmailMessages_workspaceId_serverRevision` " +
          "ON `syncedEmailMessages` (`workspaceId`, `serverRevision`)",
      )

      db.execSQL(
        "CREATE TABLE IF NOT EXISTS `emailAccounts` (`id` TEXT NOT NULL, " +
          "`emailAddress` TEXT NOT NULL, `historyId` TEXT, `backfillPageToken` TEXT, " +
          "`backfillCompletedAt` INTEGER, `lastAttemptAt` INTEGER, " +
          "`lastSuccessfulSyncAt` INTEGER, `syncState` TEXT NOT NULL, `lastError` TEXT, " +
          "`createdAt` INTEGER NOT NULL, `updatedAt` INTEGER NOT NULL, PRIMARY KEY(`id`))",
      )
      db.execSQL(
        "CREATE INDEX IF NOT EXISTS `index_emailAccounts_emailAddress` " +
          "ON `emailAccounts` (`emailAddress`)",
      )

      db.execSQL(
        "CREATE TABLE IF NOT EXISTS `emailMessages` (`key` TEXT NOT NULL, " +
          "`accountId` TEXT NOT NULL, `gmailMessageId` TEXT NOT NULL, " +
          "`threadId` TEXT NOT NULL, `rfcMessageId` TEXT, `senderName` TEXT, " +
          "`senderAddress` TEXT NOT NULL, `subject` TEXT NOT NULL, `snippet` TEXT NOT NULL, " +
          "`internalDate` INTEGER NOT NULL, `normalizedBodyText` TEXT, " +
          "`analysisProviderOverride` TEXT, `analyzerType` TEXT, `modelVersion` TEXT, " +
          "`promptVersion` INTEGER, `classification` TEXT, `merchant` TEXT, `amount` TEXT, " +
          "`currency` TEXT, `occurredAt` INTEGER, `categoryId` TEXT, " +
          "`paymentMethodId` TEXT, `paymentLastFour` TEXT, `reference` TEXT, " +
          "`state` TEXT NOT NULL, `purchaseGroupId` TEXT, `linkedTransactionId` TEXT, " +
          "`analyzedAt` INTEGER, `reviewedAt` INTEGER, `createdAt` INTEGER NOT NULL, " +
          "`updatedAt` INTEGER NOT NULL, PRIMARY KEY(`key`))",
      )
      db.execSQL(
        "CREATE INDEX IF NOT EXISTS `index_emailMessages_accountId` " +
          "ON `emailMessages` (`accountId`)",
      )
      db.execSQL(
        "CREATE INDEX IF NOT EXISTS `index_emailMessages_state_internalDate` " +
          "ON `emailMessages` (`state`, `internalDate`)",
      )
      db.execSQL(
        "CREATE INDEX IF NOT EXISTS `index_emailMessages_linkedTransactionId` " +
          "ON `emailMessages` (`linkedTransactionId`)",
      )
      db.execSQL(
        "CREATE INDEX IF NOT EXISTS `index_emailMessages_purchaseGroupId` " +
          "ON `emailMessages` (`purchaseGroupId`)",
      )

      db.execSQL(
        "CREATE TABLE IF NOT EXISTS `emailAnalysisSettings` (`id` TEXT NOT NULL, " +
          "`selectedProvider` TEXT, `openRouterAccessMode` TEXT, `openRouterModelId` TEXT, " +
          "`lastFreeOpenRouterModelId` TEXT, `lastBYOKOpenRouterModelId` TEXT, " +
          "`openRouterPrivacyMode` TEXT NOT NULL, `nonZDRConsentVersion` INTEGER, " +
          "`lastFreeOpenRouterPrivacyMode` TEXT, `lastFreeNonZDRConsentVersion` INTEGER, " +
          "`lastBYOKOpenRouterPrivacyMode` TEXT, `lastBYOKNonZDRConsentVersion` INTEGER, " +
          "`syncWindow` TEXT NOT NULL, `updatedAt` INTEGER NOT NULL, PRIMARY KEY(`id`))",
      )

      db.execSQL(
        "CREATE TABLE IF NOT EXISTS `emailAnalysisRetry` (`id` TEXT NOT NULL, " +
          "`attempt` INTEGER NOT NULL, `notBefore` INTEGER, `reason` TEXT, " +
          "`lastHttpStatus` INTEGER, `updatedAt` INTEGER NOT NULL, PRIMARY KEY(`id`))",
      )
    }
  }

  /** Adds `categories.archived`. Existing rows stay active (`0`). */
  val MIGRATION_2_3 = object : Migration(2, 3) {
    override fun migrate(db: SupportSQLiteDatabase) {
      db.execSQL(
        "ALTER TABLE `categories` ADD COLUMN `archived` INTEGER NOT NULL DEFAULT 0",
      )
    }
  }

  val ALL = arrayOf(MIGRATION_1_2, MIGRATION_2_3)
}
