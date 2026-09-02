package app.dimo.android.auth

import java.io.IOException
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AuthExceptionTests {
  @Test
  fun invalidGrantIsTerminal() {
    val error = AuthException.fromHttp(
      400,
      """{"error":"invalid_grant","error_description":"expired"}""",
    )
    assertTrue(error.isTerminalRefresh)
  }

  @Test
  fun rateLimitAndServerErrorsAreTransient() {
    assertTrue(AuthException.isTransient(AuthException.fromHttp(429, "slow")))
    assertTrue(AuthException.isTransient(AuthException.fromHttp(503, "")))
    assertTrue(AuthException.isTransient(IOException("offline")))
    assertFalse(AuthException.fromHttp(429, "slow").isTerminalRefresh)
  }
}
