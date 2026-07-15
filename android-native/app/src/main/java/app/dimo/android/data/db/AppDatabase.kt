package app.dimo.android.data.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import java.io.File

@Database(
  entities = [
    EntityRecord::class,
    OutboxRecord::class,
    SyncMetaRecord::class,
    DeviceMetaRecord::class,
  ],
  version = 1,
  exportSchema = false,
)
abstract class AppDatabase : RoomDatabase() {
  abstract fun entities(): EntityDao
  abstract fun outbox(): OutboxDao
  abstract fun syncMeta(): SyncMetaDao
  abstract fun deviceMeta(): DeviceMetaDao

  companion object {
    fun dbFileName(userId: String): String {
      val safe = userId.replace("/", "_").replace(":", "_")
      return "dimo-$safe.db"
    }

    fun open(context: Context, userId: String): AppDatabase {
      val dir = File(context.filesDir, "Dimo").apply { mkdirs() }
      val file = File(dir, dbFileName(userId))
      return Room.databaseBuilder(context, AppDatabase::class.java, file.absolutePath)
        .fallbackToDestructiveMigration()
        .build()
    }

    fun deleteAllLocalDatabases(context: Context) {
      val dir = File(context.filesDir, "Dimo")
      if (!dir.exists()) return
      dir.listFiles()?.forEach { file ->
        val name = file.name
        if (name.startsWith("dimo-") && (
            name.endsWith(".db") ||
              name.endsWith(".db-wal") ||
              name.endsWith(".db-shm") ||
              name.endsWith(".sqlite") ||
              name.endsWith(".sqlite-wal") ||
              name.endsWith(".sqlite-shm")
            )
        ) {
          file.delete()
        }
      }
    }
  }
}
