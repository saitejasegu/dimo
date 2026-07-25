package app.dimo.android.sync

/**
 * Port of `isPermanentSyncError` in `ios-native/Dimo/Sync/ConvexAPI.swift:569`.
 *
 * A permanent error means the payload itself is unacceptable to Convex, so the
 * coordinator bisects the batch and parks the single bad operation as `blocked`
 * rather than retrying forever. Auth, deployment, and network failures are
 * retryable and must NOT match here.
 */
private val PERMANENT_SYNC_ERROR = Regex(
  listOf(
    "ArgumentValidationError",
    "Payload does not match",
    "Entity ID mismatch",
    "Workspace mismatch",
    "Unsupported workspace",
    "Invalid logical version",
    "Invalid minor-unit amount",
    "Invalid recurring anchor date",
    "A push may contain at most 50",
  ).joinToString("|"),
)

fun isPermanentSyncError(message: String): Boolean =
  PERMANENT_SYNC_ERROR.containsMatchIn(message)
