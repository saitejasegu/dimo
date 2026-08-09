package app.dimo.android.data

import android.content.Context
import androidx.room.Room
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory
import androidx.test.core.app.ApplicationProvider
import app.dimo.android.data.db.DimoDatabase
import app.dimo.android.data.db.Migrations
import app.dimo.android.data.model.EmailAccountRecordModel
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Guards the hand-written DDL in [Migrations.MIGRATION_1_2].
 *
 * Room validates the on-disk schema against its exported hash when it opens a
 * migrated database, so this reconstructs a v1 file — a v2 database with the
 * email tables dropped and `user_version` rewound — and reopens it through the
 * migration. Any drift between `Migrations.kt` and the entity definitions fails
 * here rather than on a user's device during an upgrade.
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
  fun `migrating 1 to 2 produces the schema Room expects`() = runTest {
    context.getDatabasePath(name).also { if (it.exists()) it.delete() }

    // 1. Let Room create the current schema, then keep a v1-shaped file.
    val seed = Room.databaseBuilder(context, DimoDatabase::class.java, name)
      .allowMainThreadQueries()
      .build()
    seed.openHelper.writableDatabase
    seed.close()
    rewindToVersion1()

    // 2. Reopening runs the migration and then Room's own schema validation.
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
    } finally {
      migrated.close()
      context.getDatabasePath(name).delete()
    }
  }

  /** Drops everything the migration is responsible for creating. */
  private fun rewindToVersion1() {
    val configuration = androidx.sqlite.db.SupportSQLiteOpenHelper.Configuration
      .builder(context)
      .name(name)
      .callback(
        object : androidx.sqlite.db.SupportSQLiteOpenHelper.Callback(2) {
          override fun onCreate(db: androidx.sqlite.db.SupportSQLiteDatabase) = Unit
          override fun onUpgrade(
            db: androidx.sqlite.db.SupportSQLiteDatabase,
            oldVersion: Int,
            newVersion: Int,
          ) = Unit
        },
      )
      .build()
    FrameworkSQLiteOpenHelperFactory().create(configuration).use { helper ->
      helper.writableDatabase.apply {
        emailTables.forEach { execSQL("DROP TABLE IF EXISTS `$it`") }
        version = 1
      }
    }
  }
}
