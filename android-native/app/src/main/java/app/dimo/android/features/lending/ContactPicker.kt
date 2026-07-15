package app.dimo.android.features.lending

import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.ContactsContract
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat

data class PickedContact(val contactId: String, val displayName: String)

/**
 * Launches the system contact picker. Photos are never read or persisted.
 */
@Composable
fun rememberContactPicker(onPicked: (PickedContact) -> Unit): () -> Unit {
  val context = LocalContext.current
  val pickLauncher = rememberLauncherForActivityResult(
    ActivityResultContracts.PickContact(),
  ) { uri: Uri? ->
    if (uri == null) return@rememberLauncherForActivityResult
    val cursor = context.contentResolver.query(
      uri,
      arrayOf(
        ContactsContract.Contacts._ID,
        ContactsContract.Contacts.DISPLAY_NAME_PRIMARY,
      ),
      null,
      null,
      null,
    )
    cursor?.use {
      if (it.moveToFirst()) {
        val id = it.getString(0).orEmpty()
        val name = it.getString(1).orEmpty()
        if (id.isNotBlank() && name.isNotBlank()) {
          onPicked(PickedContact(contactId = id, displayName = name))
        }
      }
    }
  }

  val permissionLauncher = rememberLauncherForActivityResult(
    ActivityResultContracts.RequestPermission(),
  ) { granted ->
    if (granted) pickLauncher.launch(null)
  }

  return remember(pickLauncher, permissionLauncher) {
    {
      val granted = ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.READ_CONTACTS,
      ) == PackageManager.PERMISSION_GRANTED
      if (granted) pickLauncher.launch(null)
      else permissionLauncher.launch(Manifest.permission.READ_CONTACTS)
    }
  }
}
