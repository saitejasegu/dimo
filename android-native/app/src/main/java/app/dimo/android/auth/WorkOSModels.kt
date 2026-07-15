package app.dimo.android.auth

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class WorkOSUser(
  val id: String,
  val email: String,
  @SerialName("first_name") val firstName: String? = null,
  @SerialName("last_name") val lastName: String? = null,
  @SerialName("profile_picture_url") val profilePictureUrl: String? = null,
) {
  val displayName: String
    get() {
      val joined = listOfNotNull(firstName?.takeIf { it.isNotBlank() }, lastName?.takeIf { it.isNotBlank() })
        .joinToString(" ")
      return joined.ifBlank { email }
    }
}

data class WorkOSSession(
  val accessToken: String,
  val refreshToken: String,
  val user: WorkOSUser,
  val expiresAtEpochSeconds: Long,
)

object WorkOSJson {
  val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
}
