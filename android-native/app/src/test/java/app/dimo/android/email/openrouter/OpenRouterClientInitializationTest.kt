package app.dimo.android.email.openrouter

import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Test

class OpenRouterClientInitializationTest {
  @Test
  fun constructorInitializesResponseSchema() {
    OpenRouterClient()

    val schema = OpenRouterClient.RESPONSE_FORMAT["json_schema"]
      ?.jsonObject
      ?.get("schema")
      ?.jsonObject
    assertEquals("object", schema?.get("type")?.toString()?.trim('"'))
  }
}
