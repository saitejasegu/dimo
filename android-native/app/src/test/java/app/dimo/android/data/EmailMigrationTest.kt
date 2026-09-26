package app.dimo.android.data

import android.content.Context
import androidx.room.Room
import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory
import androidx.test.core.app.ApplicationProvider
import app.dimo.android.data.db.DimoDatabase
import app.dimo.android.data.db.Migrations
import app.dimo.android.data.model.EmailAccountRecordModel
import app.dimo.android.data.model.EntityPayload
import app.dimo.android.data.model.EntityType
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Guards the hand-written DDL in [Migrations].
 *
 * Room validates the on-disk schema against its exported hash when it opens a
 * migrated database. These tests reconstruct an older file and reopen it through
 * the migrator so drift fails here rather than on a user's device during upgrade.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [34])
class EmailMigrationTest {
  private val context: Context = ApplicationProvider.getApplicationContext()
  private val name = "migration-test.db"

  private val emailTables = listOf(
    "syncedEmailMessages",
    "emailAccounts",
    "emailMessages",
    "emailAnalysisSettings",
    "emailAnalysisRetry",
  )

  @Test
  fun `migrating 1 to current produces the schema Room expects`() = runTest {
    context.getDatabasePath(name).also { if (it.exists()) it.delete() }

    val seed = Room.databaseBuilder(context, DimoDatabase::class.java, name)
      .allowMainThreadQueries()
      .build()
    seed.openHelper.writableDatabase
    seed.close()
    rewindToVersion1()

    val migrated = Room
      .databaseBuilder(context, DimoDatabase::class.java, name)
      .addMigrations(*Migrations.ALL)
      .allowMainThreadQueries()
      .build()

    try {
      val repository = Repository(migrated)
      val email = EmailRepository(migrated, repository.entityWriter)
      email.saveAccount(
        EmailAccountRecordModel(id = "subject-1", emailAddress = "user@example.com"),
      )
      assertEquals(1, email.accounts().size)
      assertTrue(hasCategoryArchivedColumn(migrated.openHelper.writableDatabase))
      assertTrue(hasLendSharingColumns(migrated.openHelper.writableDatabase))
    } finally {
      migrated.close()
      context.getDatabasePath(name).delete()
    }
  }

  @Test
  fun `migrating 3 to 4 adds lend sharing columns and keeps rows`() = runTest {
    context.getDatabasePath(name).also { if (it.exists()) it.delete() }

    val seed = Room.databaseBuilder(context, DimoDatabase::class.java, name)
      .allowMainThreadQueries()
      .build()
    seed.openHelper.writableDatabase
    seed.close()
    openRaw { db ->
      rebuildLendsWithoutSharing(db)
      db.execSQL(
        "INSERT INTO `lends` (`key`, `workspaceId`, `entityId`, `deleted`, `serverRevision`, " +
          "`contactName`, `contactId`, `amountMinor`, `occurredAt`, `comment`, `kind`, " +
          "`versionTimestamp`, `versionCounter`, `versionDeviceId`) VALUES " +
          "('lend:lend-1', 'global', 'lend-1', 0, 1, 'Sam', 'cn-sam', 5000, 10, '', 'lent', 1, 0, 'd')",
      )
      db.version = 3
    }

    val migrated = Room
      .databaseBuilder(context, DimoDatabase::class.java, name)
      .addMigrations(*Migrations.ALL)
      .allowMainThreadQueries()
      .build()

    try {
      assertTrue(hasLendSharingColumns(migrated.openHelper.writableDatabase))
      val lends = Repository(migrated).activeEntities(EntityType.LEND)
      assertEquals(listOf("lend-1"), lends.map { it.entityId })
      val lend = (lends.single().payload as EntityPayload.Lend).value
      assertNull(lend.connectionId)
      assertNull(lend.currency)
    } finally {
      migrated.close()
      context.getDatabasePath(name).delete()
    }
  }

  @Test
  fun `migrating 2 to 3 adds category archived`() = runTest {
    context.getDatabasePath(name).also { if (it.exists()) it.delete() }

    val seed = Room.databaseBuilder(context, DimoDatabase::class.java, name)
      .allowMainThreadQueries()
      .build()
    seed.openHelper.writableDatabase
    seed.close()
    rewindToVersion2()

    val migrated = Room
      .databaseBuilder(context, DimoDatabase::class.java, name)
      .addMigrations(*Migrations.ALL)
      .allowMainThreadQueries()
      .build()

    try {
      assertTrue(hasCategoryArchivedColumn(migrated.openHelper.writableDatabase))
    } finally {
      migrated.close()
      context.getDatabasePath(name).delete()
    }
  }

  /** Drops email tables and the v3 category column so 1→2→3 all run. */
  private fun rewindToVersion1() {
    openRaw { db ->
      emailTables.forEach { db.execSQL("DROP TABLE IF EXISTS `$it`") }
      rebuildCategoriesWithoutArchived(db)
      rebuildLendsWithoutSharing(db)
      db.version = 1
    }
  }

  /** Restores the v2 categories shape so only [Migrations.MIGRATION_2_3] runs. */
  private fun rewindToVersion2() {
    openRaw { db ->
      rebuildCategoriesWithoutArchived(db)
      rebuildLendsWithoutSharing(db)
      db.version = 2
    }
  }

  private fun openRaw(block: (SupportSQLiteDatabase) -> Unit) {
    val configuration = androidx.sqlite.db.SupportSQLiteOpenHelper.Configuration
      .builder(context)
      .name(name)
      .callback(
        object : androidx.sqlite.db.SupportSQLiteOpenHelper.Callback(3) {
          override fun onCreate(db: SupportSQLiteDatabase) = Unit
          override fun onUpgrade(
            db: SupportSQLiteDatabase,
            oldVersion: Int,
            newVersion: Int,
          ) = Unit
          override fun onDowngrade(
            db: SupportSQLiteDatabase,
            oldVersion: Int,
            newVersion: Int,
          ) = Unit
        },
      )
      .build()
    FrameworkSQLiteOpenHelperFactory().create(configuration).use { helper ->
      block(helper.writableDatabase)
    }
  }

  private fun columns(db: SupportSQLiteDatabase, table: String): Set<String> {
    val names = mutableSetOf<String>()
    db.query("PRAGMA table_info(`$table`)").use { cursor ->
      val nameIndex = cursor.getColumnIndex("name")
      while (cursor.moveToNext()) names += cursor.getString(nameIndex)
    }
    return names
  }

  private fun hasLendSharingColumns(db: SupportSQLiteDatabase): Boolean =
    columns(db, "lends").containsAll(listOf("currency", "connectionId", "createdBy", "lastEditedBy"))

  /** v1–v3 lends have no sharing columns; rebuild the table before replaying migrations. */
  private fun rebuildLendsWithoutSharing(db: SupportSQLiteDatabase) {
    if (!hasLendSharingColumns(db)) return
    db.execSQL("DROP TABLE `lends`")
    db.execSQL(
      "CREATE TABLE IF NOT EXISTS `lends` (`key` TEXT NOT NULL, `workspaceId` TEXT NOT NULL, " +
        "`entityId` TEXT NOT NULL, `deleted` INTEGER NOT NULL, `serverRevision` INTEGER NOT NULL, " +
        "`contactName` TEXT NOT NULL, `contactId` TEXT, `amountMinor` INTEGER NOT NULL, " +
        "`occurredAt` INTEGER NOT NULL, `comment` TEXT NOT NULL, `kind` TEXT, " +
        "`versionTimestamp` INTEGER NOT NULL, `versionCounter` INTEGER NOT NULL, " +
        "`versionDeviceId` TEXT NOT NULL, PRIMARY KEY(`key`))",
    )
    db.execSQL(
      "CREATE INDEX IF NOT EXISTS `index_lends_workspaceId_entityId` " +
        "ON `lends` (`workspaceId`, `entityId`)",
    )
    db.execSQL(
      "CREATE INDEX IF NOT EXISTS `index_lends_workspaceId_serverRevision` " +
        "ON `lends` (`workspaceId`, `serverRevision`)",
    )
  }

  private fun hasCategoryArchivedColumn(db: SupportSQLiteDatabase): Boolean {
    db.query("PRAGMA table_info(`categories`)").use { cursor ->
      val nameIndex = cursor.getColumnIndex("name")
      while (cursor.moveToNext()) {
        if (cursor.getString(nameIndex) == "archived") return true
      }
    }
    return false
  }

  /**
   * v1 and v2 categories have no `archived` column. The current Room schema
   * includes it, so rewind has to rebuild the table before replaying migrations.
   */
  private fun rebuildCategoriesWithoutArchived(db: SupportSQLiteDatabase) {
    if (!hasCategoryArchivedColumn(db)) return
    db.execSQL("ALTER TABLE `categories` RENAME TO `categories_old`")
    db.execSQL(
      "CREATE TABLE IF NOT EXISTS `categories` (`key` TEXT NOT NULL, " +
        "`workspaceId` TEXT NOT NULL, `entityId` TEXT NOT NULL, " +
        "`deleted` INTEGER NOT NULL, `serverRevision` INTEGER NOT NULL, " +
        "`name` TEXT NOT NULL, `emoji` TEXT, `monthlyBudgetMinor` INTEGER, " +
        "`tint` TEXT NOT NULL, `sortOrder` INTEGER NOT NULL, " +
        "`system` INTEGER NOT NULL, `versionTimestamp` INTEGER NOT NULL, " +
        "`versionCounter` INTEGER NOT NULL, `versionDeviceId` TEXT NOT NULL, " +
        "PRIMARY KEY(`key`))",
    )
    db.execSQL(
      "INSERT INTO `categories` (`key`, `workspaceId`, `entityId`, `deleted`, " +
        "`serverRevision`, `name`, `emoji`, `monthlyBudgetMinor`, `tint`, " +
        "`sortOrder`, `system`, `versionTimestamp`, `versionCounter`, " +
        "`versionDeviceId`) SELECT `key`, `workspaceId`, `entityId`, `deleted`, " +
        "`serverRevision`, `name`, `emoji`, `monthlyBudgetMinor`, `tint`, " +
        "`sortOrder`, `system`, `versionTimestamp`, `versionCounter`, " +
        "`versionDeviceId` FROM `categories_old`",
    )
    db.execSQL("DROP TABLE `categories_old`")
    db.execSQL(
      "CREATE INDEX IF NOT EXISTS `index_categories_workspaceId_entityId` " +
        "ON `categories` (`workspaceId`, `entityId`)",
    )
    db.execSQL(
      "CREATE INDEX IF NOT EXISTS `index_categories_workspaceId_serverRevision` " +
        "ON `categories` (`workspaceId`, `serverRevision`)",
    )
  }
}
