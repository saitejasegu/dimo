package app.dimo.android.domain

/** How an expense divides between the user and other people. */
enum class SplitMode(val label: String) {
  EQUAL("Equally"),
  EXACT("By amount"),
  PERCENT("By percent"),
}

data class SplitShareInput(
  val contactId: String,
  /** Minor units for [SplitMode.EXACT], a percentage for [SplitMode.PERCENT]; ignored for [SplitMode.EQUAL]. */
  val value: Double,
)

data class SplitShares(
  /** The user's own share, recorded as the expense. */
  val mine: Long,
  val others: List<Share>,
) {
  data class Share(val contactId: String, val share: Long)

  fun shareFor(contactId: String): Long? = others.firstOrNull { it.contactId == contactId }?.share
}

/**
 * Splitting one expense between the user and other people. All amounts are
 * integer minor units of the currency the expense was entered in; the user's
 * share is whatever is left, so shares always add up to the total exactly.
 * Port of `ios-native/Dimo/Domain/SplitSelectors.swift` and
 * `app/features/transactions/split.ts`.
 */
object SplitSelectors {
  /**
   * Shares of [totalMinor], or `null` when the split doesn't add up (more than
   * the total, over 100%, or nobody to split with). An equal split gives any
   * leftover minor units to the user first.
   */
  fun shares(totalMinor: Long, mode: SplitMode, people: List<SplitShareInput>): SplitShares? {
    if (totalMinor <= 0 || people.isEmpty()) return null

    if (mode == SplitMode.EQUAL) {
      val count = people.size + 1
      val base = totalMinor / count
      val remainder = totalMinor - base * count
      return SplitShares(
        mine = base + if (remainder > 0) 1 else 0,
        others = people.mapIndexed { index, person ->
          SplitShares.Share(person.contactId, base + if (index + 1 < remainder) 1 else 0)
        },
      )
    }

    if (people.any { !it.value.isFinite() || it.value < 0 }) return null
    if (mode == SplitMode.PERCENT && people.sumOf { it.value } > 100 + 1e-9) return null
    val others = people.map { person ->
      // Rounding down leaves any fraction of a minor unit with the user.
      SplitShares.Share(
        person.contactId,
        if (mode == SplitMode.EXACT) {
          Math.round(person.value)
        } else {
          Math.floor(totalMinor * person.value / 100 + 1e-9).toLong()
        },
      )
    }
    val mine = totalMinor - others.sumOf { it.share }
    return if (mine < 0) null else SplitShares(mine, others)
  }
}
