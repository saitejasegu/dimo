package app.dimo.android.features.common

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.ContactsContract
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Address-book access for lending, the Android analogue of the iOS
 * `ContactsLoader`.
 *
 * Only the contact identifier and display name ever reach the store — thumbnails
 * are decoded on demand into an in-memory cache and are never written to the
 * local database or uploaded to Convex.
 */
data class DeviceContact(
  val id: String,
  val name: String,
  /** Content URI of the thumbnail, resolved lazily; never persisted. */
  val photoUri: String?,
)

object ContactsLoader {
  /** Process-lifetime thumbnail cache keyed by photo URI. */
  private val thumbnails = mutableMapOf<String, ImageBitmap?>()

  fun hasPermission(context: Context): Boolean =
    ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS) ==
      PackageManager.PERMISSION_GRANTED

  suspend fun load(context: Context): List<DeviceContact> {
    if (!hasPermission(context)) return emptyList()
    return withContext(Dispatchers.IO) {
      val projection = arrayOf(
        ContactsContract.Contacts._ID,
        ContactsContract.Contacts.DISPLAY_NAME_PRIMARY,
        ContactsContract.Contacts.PHOTO_THUMBNAIL_URI,
      )
      val result = mutableListOf<DeviceContact>()
      runCatching {
        context.contentResolver.query(
          ContactsContract.Contacts.CONTENT_URI,
          projection,
          "${ContactsContract.Contacts.DISPLAY_NAME_PRIMARY} IS NOT NULL",
          null,
          "${ContactsContract.Contacts.DISPLAY_NAME_PRIMARY} COLLATE NOCASE ASC",
        )?.use { cursor ->
          val idIndex = cursor.getColumnIndexOrThrow(ContactsContract.Contacts._ID)
          val nameIndex =
            cursor.getColumnIndexOrThrow(ContactsContract.Contacts.DISPLAY_NAME_PRIMARY)
          val photoIndex =
            cursor.getColumnIndexOrThrow(ContactsContract.Contacts.PHOTO_THUMBNAIL_URI)
          val seen = mutableSetOf<String>()
          while (cursor.moveToNext()) {
            val id = cursor.getString(idIndex) ?: continue
            val name = cursor.getString(nameIndex)?.trim().orEmpty()
            if (name.isEmpty()) continue
            if (!seen.add(id)) continue
            result.add(
              DeviceContact(
                id = id,
                name = name,
                photoUri = cursor.getString(photoIndex),
              ),
            )
          }
        }
      }
      result
    }
  }

  /**
   * Process-lifetime `contactId → photo URI` index. Lending rows only store the
   * address-book id, so this is what lets a list row resolve a thumbnail without
   * re-querying the provider per row.
   */
  private var photoIndex: Map<String, String>? = null

  suspend fun photoUris(context: Context): Map<String, String> {
    photoIndex?.let { return it }
    // Not cached while unauthorized, so granting the permission later still works.
    if (!hasPermission(context)) return emptyMap()
    val loaded = load(context).mapNotNull { contact ->
      contact.photoUri?.takeIf { it.isNotEmpty() }?.let { contact.id to it }
    }.toMap()
    photoIndex = loaded
    return loaded
  }

  /** Decodes (and memoizes) a contact thumbnail. Returns null when unavailable. */
  suspend fun thumbnail(context: Context, photoUri: String?): ImageBitmap? {
    if (photoUri.isNullOrEmpty()) return null
    if (thumbnails.containsKey(photoUri)) return thumbnails[photoUri]
    if (!hasPermission(context)) return null
    val bitmap = withContext(Dispatchers.IO) {
      runCatching {
        context.contentResolver.openInputStream(Uri.parse(photoUri))?.use { stream ->
          BitmapFactory.decodeStream(stream)?.asImageBitmap()
        }
      }.getOrNull()
    }
    thumbnails[photoUri] = bitmap
    return bitmap
  }
}

/**
 * `contactId → photo URI` for the current address book, empty until loaded (or
 * when `READ_CONTACTS` has not been granted). Photos are read on-device only and
 * are never persisted or synced.
 */
@Composable
fun rememberContactPhotoUris(): Map<String, String> {
  val context = LocalContext.current
  var photos by remember { mutableStateOf(emptyMap<String, String>()) }
  LaunchedEffect(Unit) { photos = ContactsLoader.photoUris(context) }
  return photos
}

/**
 * Contact avatar: photo when the address book grants one, initial otherwise.
 * The bitmap lives only in the in-memory cache.
 */
@Composable
fun ContactAvatar(
  name: String,
  modifier: Modifier = Modifier,
  photoUri: String? = null,
  size: Dp = 40.dp,
  radius: Dp = 13.dp,
  fontSize: Float = 16f,
  monogram: String? = null,
) {
  val context = LocalContext.current
  var bitmap by remember(photoUri) { mutableStateOf<ImageBitmap?>(null) }

  LaunchedEffect(photoUri) {
    bitmap = ContactsLoader.thumbnail(context, photoUri)
  }

  Box(
    modifier = modifier
      .size(size)
      .clip(RoundedCornerShape(radius))
      .background(DimoColors.greenSoft),
    contentAlignment = Alignment.Center,
  ) {
    val local = bitmap
    if (local != null) {
      Image(
        bitmap = local,
        contentDescription = null,
        modifier = Modifier.size(size),
        contentScale = ContentScale.Crop,
      )
    } else {
      Text(
        text = monogram ?: name.trim().firstOrNull()?.uppercaseChar()?.toString().orEmpty(),
        style = DimoFont.display(fontSize, FontWeight.SemiBold),
        color = DimoColors.green,
      )
    }
  }
}
