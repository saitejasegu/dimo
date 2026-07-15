package app.dimo.android.sync

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ConvexAPITest {
  @Test
  fun detectsPermanentPayloadErrors() {
    assertTrue(ConvexAPI.isPermanentSyncError("ArgumentValidationError: bad"))
    assertTrue(ConvexAPI.isPermanentSyncError("A push may contain at most 50"))
    assertFalse(ConvexAPI.isPermanentSyncError("Not authenticated"))
    assertFalse(ConvexAPI.isPermanentSyncError("Offline"))
  }
}
