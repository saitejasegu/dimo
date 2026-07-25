package app.dimo.android.data.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import java.io.File

/**
 * Account-scoped local store, the Android counterpart of
 * `ios-native/Dimo/Data/Database/AppDatabase.swift`.
 *
 * iOS opens `dimo-{userId}.sqlite`; Android opens `dimo-{userId}.db`. There is no
 * migration history to replay — the schema starts at the current iOS v6/v7 typed
 * shape — so this is version 1.
 */
@Database(
  entities = [
    CategoryRecord::class,
    PaymentMethodRecord::class,
    TransactionRecord::class,
    RecurringRecord::class,
    LendRecord::class,
    PreferencesRecord::class,
    OutboxRecord::class,
    SyncMetaRecord::class,
    DeviceMetaRecord::class,
  ],
  version = 1,
  exportSchema = false,
)
abstract class DimoDatabase : RoomDatabase() {
  abstract fun categories(): CategoryDao
  abstract fun paymentMethods(): PaymentMethodDao
  abstract fun transactions(): TransactionDao
  abstract fun recurring(): RecurringDao
  abstract fun lends(): LendDao
  abstract fun preferences(): PreferencesDao
  abstract fun outbox(): OutboxDao
  abstract fun syncMeta(): SyncMetaDao
  abstract fun deviceMeta(): DeviceMetaDao
}

object AppDatabase {
  private val lock = Any()
  private var database: DimoDatabase? = null
  private var activeUserId: String? = null

  private const val PREFIX = "dimo-"
  private const val SUFFIX = ".db"

  fun fileName(userId: String): String {
    val safe = userId.replace("/", "_").replace(":", "_")
    return "$PREFIX$safe$SUFFIX"
  }

  fun activate(context: Context, userId: String): DimoDatabase = synchronized(lock) {
    val existing = database
    if (activeUserId == userId && existing != null) return existing
    existing?.close()
    val opened = Room
      .databaseBuilder(
        context.applicationContext,
        DimoDatabase::class.java,
        fileName(userId),
      )
      .build()
    database = opened
    activeUserId = userId
    opened
  }

  fun close() = synchronized(lock) {
    database?.close()
    database = null
    activeUserId = null
  }

  /**
   * Sign-out cleanup: every local Dimo database on the device is removed, not just
   * the active account's, matching `deleteAllLocalDatabases()` on iOS.
   */
  fun deleteAllLocalDatabases(context: Context) {
    synchronized(lock) {
      database?.close()
      database = null
      activeUserId = null
      val dir: File =
        context.applicationContext.getDatabasePath("placeholder").parentFile ?: return
      val files = dir.listFiles() ?: return
      for (file in files) {
        val name = file.name
        if (!name.startsWith(PREFIX)) continue
        // Also removes the -wal / -shm sidecars SQLite leaves behind.
        if (name.endsWith(SUFFIX) || name.contains(SUFFIX)) {
          file.delete()
        }
      }
    }
  }
}
