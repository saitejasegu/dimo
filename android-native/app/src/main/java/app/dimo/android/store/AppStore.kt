package app.dimo.android.store

import android.content.Context
import app.dimo.android.app.AppConfig
import app.dimo.android.auth.WorkOSConvexAuthProvider
import app.dimo.android.auth.WorkOSSession
import app.dimo.android.data.Repository
import app.dimo.android.data.db.AppDatabase
import app.dimo.android.data.model.CASH_PAYMENT_METHOD_ID
import app.dimo.android.data.model.CategoryTint
import app.dimo.android.data.model.Currency
import app.dimo.android.data.model.DEFAULT_CATEGORY_EMOJI
import app.dimo.android.data.model.EntityPayload
import app.dimo.android.data.model.EntityType
import app.dimo.android.data.model.LendKind
import app.dimo.android.data.model.NotificationsPrefs
import app.dimo.android.data.model.PaymentMethodType
import app.dimo.android.data.model.PREFERENCES_ID
import app.dimo.android.data.model.RecurringFrequency
import app.dimo.android.data.model.StatsRange
import app.dimo.android.data.model.StoredEntity
import app.dimo.android.data.model.SyncMeta
import app.dimo.android.data.model.ThemePreference
import app.dimo.android.data.model.ViewKey
import app.dimo.android.data.model.WeekStart
import app.dimo.android.domain.DateHelpers
import app.dimo.android.domain.FilterState
import app.dimo.android.domain.Greeting
import app.dimo.android.domain.LendSelectors
import app.dimo.android.domain.RecurringSelectors
import app.dimo.android.domain.StatsConstants
import app.dimo.android.domain.TransactionCSV
import app.dimo.android.sync.NetworkMonitor
import app.dimo.android.sync.SyncCoordinator
import dev.convex.android.ConvexClientWithAuth
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.roundToInt

data class AppUiState(
  val dataReady: Boolean = false,
  val greeting: String = Greeting.greetingFor(),
  val tab: AppTab = AppTab.home,
  val overlay: OverlayKey? = null,
  val detailTransactionId: String? = null,
  val toast: String? = null,
  val filter: FilterState = FilterState(),
  val statsRange: StatsRange = StatsRange.OneYear,
  val currency: Currency = Currency.INR,
  val theme: ThemePreference = ThemePreference.light,
  val navGlassOpacity: Int = 40,
  val defaultStatsRange: StatsRange = StatsRange.OneYear,
  val notifications: NotificationsPrefs = NotificationsPrefs(),
  val syncMeta: SyncMeta = SyncMeta(),
  val pendingCount: Int = 0,
  val blockedCount: Int = 0,
  val deletingHistory: Boolean = false,
  val transactions: List<UiTransaction> = emptyList(),
  val recurring: List<UiRecurring> = emptyList(),
  val lends: List<UiLend> = emptyList(),
  val categories: List<UiCategory> = emptyList(),
  val paymentMethods: List<UiPaymentMethod> = emptyList(),
  val limits: Map<String, Double> = emptyMap(),
  val profileName: String = "",
  val profileEmail: String = "",
  val profilePhotoUrl: String? = null,
  val userId: String = "",
  val expenseDraft: ExpenseDraft = ExpenseDraft(),
  val recurringDraft: RecurringDraft = RecurringDraft(),
  val categoryDraft: CategoryDraft = CategoryDraft(),
  val lendDraft: LendDraft = LendDraft(),
  val showSettings: Boolean = false,
  val showAccount: Boolean = false,
  val homeVisibleCount: Int = TransactionSelectorsPage,
)

private const val TransactionSelectorsPage = 50

class AppStore(
  private val context: Context,
  private val session: WorkOSSession,
  private val refreshSession: suspend (force: Boolean) -> WorkOSSession,
) {
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
  private val idCounter = AtomicInteger(0)
  private val _state = MutableStateFlow(
    AppUiState(
      userId = session.user.id,
      profileName = session.user.displayName,
      profileEmail = session.user.email,
      profilePhotoUrl = session.user.profilePictureUrl,
    ),
  )
  val state: StateFlow<AppUiState> = _state.asStateFlow()

  private lateinit var db: AppDatabase
  private lateinit var repository: Repository
  private var convexClient: ConvexClientWithAuth<WorkOSSession>? = null
  private var sync: SyncCoordinator? = null
  private var previousDefaultStats = StatsRange.OneYear

  suspend fun start() {
    db = AppDatabase.open(context, session.user.id)
    repository = Repository(db)
    repository.initializeLocalDatabase()

    val authProvider = WorkOSConvexAuthProvider(
      getSession = { force -> refreshSession(force) },
      clearSession = {},
    )
    val client = ConvexClientWithAuth(
      deploymentUrl = AppConfig.convexUrl,
      authProvider = authProvider,
    )
    client.loginFromCache()
    convexClient = client

    sync = SyncCoordinator(
      repository = repository,
      client = client,
      networkMonitor = NetworkMonitor(context),
      scope = CoroutineScope(SupervisorJob() + Dispatchers.IO),
      profileName = { _state.value.profileName.ifBlank { null } },
      profileEmail = { _state.value.profileEmail.ifBlank { null } },
    ).also { it.start() }

    scope.launch {
      combine(
        repository.observeEntities(),
        repository.observeSyncMeta(),
        repository.observePendingCount(),
        repository.observeBlockedCount(),
      ) { entities, meta, pending, blocked ->
        Quadriver(entities, meta, pending, blocked)
      }.collect { q ->
        hydrate(q.entities, q.meta, q.pending, q.blocked)
      }
    }
  }

  fun tearDown() {
    sync?.stop()
    scope.cancel()
    if (::db.isInitialized) db.close()
  }

  fun sceneBecameActive() {
    sync?.sceneBecameActive()
    _state.update { it.copy(greeting = Greeting.greetingFor()) }
  }

  fun selectTab(tab: AppTab) = _state.update { it.copy(tab = tab, showSettings = false, showAccount = false) }
  fun openSettings() = _state.update { it.copy(showSettings = true, showAccount = false) }
  fun openAccount() = _state.update { it.copy(showAccount = true, showSettings = true) }
  fun closeSettings() = _state.update { it.copy(showSettings = false, showAccount = false) }
  fun showOverlay(key: OverlayKey?) = _state.update { it.copy(overlay = key) }
  fun setFilter(filter: FilterState) = _state.update { it.copy(filter = filter) }
  fun setStatsRange(range: StatsRange) = _state.update { it.copy(statsRange = range) }
  fun loadMoreHome() = _state.update { it.copy(homeVisibleCount = it.homeVisibleCount + TransactionSelectorsPage) }
  fun showToast(message: String) {
    _state.update { it.copy(toast = message) }
    scope.launch {
      delay(1800)
      _state.update { cur -> if (cur.toast == message) cur.copy(toast = null) else cur }
    }
  }

  fun syncNow() = sync?.request()
  fun fullReplaceSync() = sync?.requestFullSync()

  suspend fun clearCloudWorkspace() {
    sync?.clearRemoteAll()
  }

  fun updateExpenseDraft(transform: (ExpenseDraft) -> ExpenseDraft) =
    _state.update { it.copy(expenseDraft = transform(it.expenseDraft)) }

  fun updateLendDraft(transform: (LendDraft) -> LendDraft) =
    _state.update { it.copy(lendDraft = transform(it.lendDraft)) }

  fun updateCategoryDraft(transform: (CategoryDraft) -> CategoryDraft) =
    _state.update { it.copy(categoryDraft = transform(it.categoryDraft)) }

  fun updateRecurringDraft(transform: (RecurringDraft) -> RecurringDraft) =
    _state.update { it.copy(recurringDraft = transform(it.recurringDraft)) }

  fun beginAddExpense() {
    val preferred = preferredPaymentMethodId()
    _state.update {
      it.copy(
        overlay = OverlayKey.add,
        expenseDraft = ExpenseDraft(paymentMethodId = preferred, occurredAt = System.currentTimeMillis()),
      )
    }
  }

  fun beginEditTransaction(tx: UiTransaction) {
    _state.update {
      it.copy(
        overlay = OverlayKey.add,
        expenseDraft = ExpenseDraft(
          id = tx.id,
          name = tx.name,
          amount = tx.amount.toString(),
          category = tx.category,
          paymentMethodId = tx.paymentMethodId,
          occurredAt = tx.occurredAt,
        ),
      )
    }
  }

  fun beginAddCategory() {
    _state.update { it.copy(overlay = OverlayKey.category, categoryDraft = CategoryDraft()) }
  }

  fun beginEditCategory(cat: UiCategory) {
    _state.update {
      it.copy(
        overlay = OverlayKey.category,
        categoryDraft = CategoryDraft(
          id = cat.id,
          name = cat.name,
          emoji = cat.emoji,
          monthlyBudget = cat.monthlyBudget?.toString().orEmpty(),
          tint = cat.tint,
        ),
      )
    }
  }

  fun beginAddLend() {
    _state.update {
      it.copy(overlay = OverlayKey.lend, lendDraft = LendDraft(occurredAt = System.currentTimeMillis()))
    }
  }

  fun saveExpense() {
    scope.launch {
      val draft = _state.value.expenseDraft
      val amount = draft.amount.toDoubleOrNull() ?: return@launch
      if (amount <= 0) return@launch
      val category = resolveOrCreateCategory(draft.category)
      val name = draft.name.ifBlank { "Expense" }
      val amountMinor = (amount * 100).roundToInt()
      val occurredAt = minOf(draft.occurredAt, System.currentTimeMillis())
      val txId = draft.id ?: nextId("tx_")
      val tx = EntityPayload.Transaction(
        id = txId,
        name = name,
        amountMinor = amountMinor,
        occurredAt = occurredAt,
        categoryId = category.id,
        paymentMethodId = draft.paymentMethodId,
      )
      val batch = mutableListOf(Triple(EntityType.Transaction, tx as EntityPayload, false))
      if (draft.makeRecurring && draft.id == null) {
        val recId = nextId("rec_")
        val anchor = DateHelpers.localDateKey(occurredAt)
        val recurring = EntityPayload.Recurring(
          id = recId,
          name = name,
          amountMinor = amountMinor,
          categoryId = category.id,
          paymentMethodId = draft.paymentMethodId,
          frequency = draft.frequency,
          anchorDate = anchor,
          paused = false,
        )
        batch += Triple(EntityType.Recurring, recurring, false)
        if (draft.includeHistorical) {
          for (date in DateHelpers.occurrencesThrough(anchor, draft.frequency)) {
            if (DateHelpers.localDateKey(date) == anchor) continue
            batch += Triple(
              EntityType.Transaction,
              EntityPayload.Transaction(
                id = nextId("tx_"),
                name = name,
                amountMinor = amountMinor,
                occurredAt = DateHelpers.occurrenceTimestamp(date),
                categoryId = category.id,
                paymentMethodId = draft.paymentMethodId,
              ),
              false,
            )
          }
        }
      }
      repository.saveEntities(batch)
      draft.paymentMethodId?.let { repository.setLastPaymentMethod(it) }
      _state.update { it.copy(overlay = null, expenseDraft = ExpenseDraft()) }
      showToast(if (draft.id == null) "Expense saved" else "Updated")
    }
  }

  fun saveLend() {
    scope.launch {
      val draft = _state.value.lendDraft
      val amount = draft.amount.toDoubleOrNull() ?: return@launch
      if (amount <= 0 || draft.contactId.isBlank()) return@launch
      val amountMinor = (amount * 100).roundToInt()
      if (draft.kind == LendKind.repaid) {
        val outstanding = LendSelectors.outstandingAmount(
          _state.value.lends,
          draft.contactId,
          excludingLendId = draft.id,
        )
        if (amount > outstanding + 0.0001) {
          showToast("Repayment exceeds outstanding")
          return@launch
        }
      }
      val occurredAt = if (draft.id != null) {
        val existing = _state.value.lends.firstOrNull { it.id == draft.id }
        if (existing != null && DateHelpers.localDateKey(existing.occurredAt) == DateHelpers.localDateKey(draft.occurredAt)) {
          existing.occurredAt
        } else if (DateHelpers.localDateKey(draft.occurredAt) == DateHelpers.localDateKey()) {
          System.currentTimeMillis()
        } else {
          DateHelpers.occurrenceTimestamp(DateHelpers.parseLocalDate(DateHelpers.localDateKey(draft.occurredAt)))
        }
      } else if (DateHelpers.localDateKey(draft.occurredAt) == DateHelpers.localDateKey()) {
        System.currentTimeMillis()
      } else {
        DateHelpers.occurrenceTimestamp(DateHelpers.parseLocalDate(DateHelpers.localDateKey(draft.occurredAt)))
      }
      val payload = EntityPayload.Lend(
        id = draft.id ?: nextId("lend_"),
        contactName = draft.contactName,
        contactId = draft.contactId,
        amountMinor = amountMinor,
        occurredAt = occurredAt,
        comment = draft.comment,
        kind = draft.kind,
      )
      repository.saveEntity(EntityType.Lend, payload)
      _state.update { it.copy(overlay = null, lendDraft = LendDraft()) }
      showToast("Saved")
    }
  }

  fun saveCategory() {
    scope.launch {
      val draft = _state.value.categoryDraft
      val name = draft.name.trim()
      if (name.isEmpty()) return@launch
      val budget = draft.monthlyBudget.toDoubleOrNull()
      val monthlyBudgetMinor = if (budget == null || budget <= 0) null else (budget * 100).roundToInt()
      val existing = _state.value.categories.firstOrNull { it.id == draft.id }
      val payload = EntityPayload.Category(
        id = draft.id ?: nextId("category_"),
        name = name,
        emoji = draft.emoji.ifBlank { DEFAULT_CATEGORY_EMOJI },
        monthlyBudgetMinor = monthlyBudgetMinor,
        tint = draft.tint,
        sortOrder = existing?.sortOrder ?: _state.value.categories.size,
        system = existing?.system ?: false,
      )
      repository.saveEntity(EntityType.Category, payload)
      _state.update { it.copy(overlay = null) }
      showToast("Category saved")
    }
  }

  fun saveRecurring() {
    scope.launch {
      val draft = _state.value.recurringDraft
      val amount = draft.amount.toDoubleOrNull() ?: return@launch
      if (amount <= 0) return@launch
      val category = resolveOrCreateCategory(draft.category)
      val amountMinor = (amount * 100).roundToInt()
      val anchor = draft.anchorDate.ifBlank { DateHelpers.localDateKey() }
      val id = draft.id ?: nextId("rec_")
      val payload = EntityPayload.Recurring(
        id = id,
        name = draft.name.ifBlank { "Bill" },
        amountMinor = amountMinor,
        categoryId = category.id,
        paymentMethodId = draft.paymentMethodId,
        frequency = draft.frequency,
        anchorDate = anchor,
        paused = false,
      )
      val batch = mutableListOf(Triple(EntityType.Recurring, payload as EntityPayload, false))
      if (draft.id == null) {
        val selection = if (draft.includeHistorical) {
          DateHelpers.OccurrenceSelection.ALL
        } else if (anchor == DateHelpers.localDateKey()) {
          DateHelpers.OccurrenceSelection.SELECTED
        } else {
          null
        }
        if (selection != null) {
          for (date in DateHelpers.recurringTransactionDates(anchor, draft.frequency, selection)) {
            batch += Triple(
              EntityType.Transaction,
              EntityPayload.Transaction(
                id = nextId("tx_"),
                name = payload.name,
                amountMinor = amountMinor,
                occurredAt = DateHelpers.occurrenceTimestamp(date),
                categoryId = category.id,
                paymentMethodId = draft.paymentMethodId,
              ),
              false,
            )
          }
        }
      }
      repository.saveEntities(batch)
      _state.update { it.copy(overlay = null) }
      showToast("Recurring saved")
    }
  }

  fun toggleRecurring(id: String) {
    scope.launch {
      val item = _state.value.recurring.firstOrNull { it.id == id } ?: return@launch
      val payload = EntityPayload.Recurring(
        id = item.id,
        name = item.name,
        amountMinor = (item.amount * 100).roundToInt(),
        categoryId = item.categoryId,
        paymentMethodId = item.paymentMethodId,
        frequency = item.frequency,
        anchorDate = item.anchorDate,
        paused = !item.paused,
      )
      repository.saveEntity(EntityType.Recurring, payload)
    }
  }

  fun deleteTransaction(id: String) = scope.launch { repository.removeEntity(EntityType.Transaction, id) }
  fun deleteRecurring(id: String) = scope.launch { repository.removeEntity(EntityType.Recurring, id) }
  fun deleteLend(id: String) = scope.launch { repository.removeEntity(EntityType.Lend, id) }

  fun deleteCategoryAndTransactions(id: String) {
    scope.launch {
      val linked = _state.value.transactions.filter { it.categoryId == id }
      val batch = linked.map {
        Triple(
          EntityType.Transaction,
          EntityPayload.Transaction(
            id = it.id,
            name = it.name,
            amountMinor = (it.amount * 100).roundToInt(),
            occurredAt = it.occurredAt,
            categoryId = it.categoryId,
            paymentMethodId = it.paymentMethodId,
          ) as EntityPayload,
          true,
        )
      }.toMutableList()
      val cat = _state.value.categories.firstOrNull { it.id == id } ?: return@launch
      batch += Triple(
        EntityType.Category,
        EntityPayload.Category(
          id = cat.id,
          name = cat.name,
          emoji = cat.emoji,
          monthlyBudgetMinor = cat.monthlyBudget?.let { (it * 100).roundToInt() },
          tint = cat.tint,
          sortOrder = cat.sortOrder,
          system = cat.system,
        ),
        true,
      )
      repository.saveEntities(batch)
      showToast("Category deleted")
    }
  }

  fun deleteTransactions(ids: Collection<String>) {
    scope.launch {
      for (id in ids) repository.removeEntity(EntityType.Transaction, id)
    }
  }

  fun deleteHistory() {
    scope.launch {
      _state.update { it.copy(deletingHistory = true) }
      repository.removeActiveEntities(EntityType.Transaction)
      _state.update { it.copy(deletingHistory = false) }
      showToast("History deleted")
    }
  }

  fun exportCSV(): String = TransactionCSV.format(_state.value.transactions)

  fun importCSV(csv: String) {
    scope.launch {
      val rows = TransactionCSV.parse(csv)
      val pmId = TransactionCSV.defaultPaymentMethodIdForImport(_state.value.paymentMethods)
      val batch = mutableListOf<Triple<EntityType, EntityPayload, Boolean>>()
      val categoryIds = _state.value.categories.associateBy { it.name.lowercase() }.toMutableMap()
      for (row in rows) {
        var cat = categoryIds[row.categoryName.lowercase()]
        if (cat == null) {
          val newCat = EntityPayload.Category(
            id = nextId("category_"),
            name = row.categoryName,
            emoji = TransactionCSV.categoryEmojiForName(row.categoryName),
            monthlyBudgetMinor = null,
            tint = CategoryTint.neutral,
            sortOrder = categoryIds.size,
            system = false,
          )
          batch += Triple(EntityType.Category, newCat, false)
          cat = UiCategory(newCat.id, newCat.name, newCat.emoji, null, newCat.tint, newCat.sortOrder, false)
          categoryIds[row.categoryName.lowercase()] = cat
        }
        batch += Triple(
          EntityType.Transaction,
          EntityPayload.Transaction(
            id = nextId("tx_"),
            name = row.name,
            amountMinor = row.amountMinor,
            occurredAt = row.occurredAt,
            categoryId = cat.id,
            paymentMethodId = pmId,
          ),
          false,
        )
      }
      if (batch.isNotEmpty()) {
        repository.saveEntities(batch)
        showToast("Imported ${rows.size} rows")
      }
    }
  }

  fun updatePreferences(
    currency: Currency? = null,
    theme: ThemePreference? = null,
    defaultStatsRange: StatsRange? = null,
    notifications: NotificationsPrefs? = null,
    defaultPaymentMethodId: String? = null,
    profileName: String? = null,
    profileEmail: String? = null,
  ) {
    scope.launch {
      val current = currentPreferences()
      val updated = current.copy(
        currency = currency ?: current.currency,
        theme = theme ?: current.theme,
        weekStart = WeekStart.Mon,
        defaultStatsRange = defaultStatsRange ?: current.defaultStatsRange,
        notifications = notifications ?: current.notifications,
        defaultPaymentMethodId = defaultPaymentMethodId ?: current.defaultPaymentMethodId,
        profileName = profileName ?: current.profileName,
        profileEmail = profileEmail ?: current.profileEmail,
        defaultView = ViewKey.home,
      )
      repository.saveEntity(EntityType.Preferences, updated)
    }
  }

  fun savePaymentMethod(id: String?, name: String, type: PaymentMethodType, detail: String) {
    scope.launch {
      val trimmed = name.trim()
      if (trimmed.isEmpty()) return@launch
      val clash = _state.value.paymentMethods.any {
        it.id != id && it.name.equals(trimmed, ignoreCase = true)
      }
      if (clash) {
        showToast("Name already used")
        return@launch
      }
      val payload = EntityPayload.PaymentMethod(
        id = id ?: nextId("payment-method_"),
        name = trimmed,
        type = type,
        detail = if (type == PaymentMethodType.Cash) "" else detail,
        archived = false,
      )
      repository.saveEntity(EntityType.PaymentMethod, payload)
      showToast("Payment method saved")
    }
  }

  fun setDefaultPaymentMethod(id: String) {
    updatePreferences(defaultPaymentMethodId = id)
  }

  fun setPaymentMethodArchived(id: String, archived: Boolean) {
    scope.launch {
      val methods = _state.value.paymentMethods
      val target = methods.firstOrNull { it.id == id } ?: return@launch
      val active = methods.filter { !it.archived && it.id != id }
      if (archived && active.isEmpty() && !target.archived) {
        showToast("Keep at least one active method")
        return@launch
      }
      repository.saveEntity(
        EntityType.PaymentMethod,
        EntityPayload.PaymentMethod(target.id, target.name, target.type, target.detail, archived),
      )
      if (archived && target.isDefault) {
        val next = active.firstOrNull()?.id ?: CASH_PAYMENT_METHOD_ID
        updatePreferences(defaultPaymentMethodId = next)
      }
    }
  }

  fun applySuggestedBudgets(updates: List<Pair<String, Double>>) {
    scope.launch {
      val batch = updates.mapNotNull { (id, suggested) ->
        val cat = _state.value.categories.firstOrNull { it.id == id } ?: return@mapNotNull null
        Triple(
          EntityType.Category,
          EntityPayload.Category(
            id = cat.id,
            name = cat.name,
            emoji = cat.emoji,
            monthlyBudgetMinor = (suggested * 100).roundToInt(),
            tint = cat.tint,
            sortOrder = cat.sortOrder,
            system = cat.system,
          ) as EntityPayload,
          false,
        )
      }
      if (batch.isNotEmpty()) repository.saveEntities(batch)
    }
  }

  private suspend fun resolveOrCreateCategory(name: String): UiCategory {
    val trimmed = name.trim().ifBlank { "General" }
    val existing = _state.value.categories.firstOrNull { it.name.equals(trimmed, true) }
    if (existing != null) return existing
    val payload = EntityPayload.Category(
      id = nextId("category_"),
      name = trimmed,
      emoji = TransactionCSV.categoryEmojiForName(trimmed),
      monthlyBudgetMinor = null,
      tint = CategoryTint.neutral,
      sortOrder = _state.value.categories.size,
      system = false,
    )
    repository.saveEntity(EntityType.Category, payload)
    return UiCategory(payload.id, payload.name, payload.emoji, null, payload.tint, payload.sortOrder, false)
  }

  private suspend fun currentPreferences(): EntityPayload.Preferences {
    val stored = repository.activeEntities(EntityType.Preferences)
      .firstOrNull()?.payload as? EntityPayload.Preferences
    return stored ?: EntityPayload.Preferences(
      id = PREFERENCES_ID,
      profileName = _state.value.profileName,
      profileEmail = _state.value.profileEmail,
      currency = _state.value.currency,
      weekStart = WeekStart.Mon,
      theme = _state.value.theme,
      navGlassOpacity = _state.value.navGlassOpacity,
      defaultView = ViewKey.home,
      defaultStatsRange = _state.value.defaultStatsRange,
      notifications = _state.value.notifications,
      defaultPaymentMethodId = _state.value.paymentMethods.firstOrNull { it.isDefault }?.id
        ?: CASH_PAYMENT_METHOD_ID,
    )
  }

  private fun preferredPaymentMethodId(): String? {
    val methods = _state.value.paymentMethods.filter { !it.archived }
    // device last is async; use default then first
    return methods.firstOrNull { it.isDefault }?.id ?: methods.firstOrNull()?.id
  }

  private fun nextId(prefix: String): String =
    "$prefix${System.currentTimeMillis()}_${idCounter.incrementAndGet()}"

  private fun hydrate(entities: List<StoredEntity>, meta: SyncMeta, pending: Int, blocked: Int) {
    val active = entities.filter { !it.deleted }
    val categories = active.filter { it.entityType == EntityType.Category }
      .map { it.payload as EntityPayload.Category }
      .sortedBy { it.sortOrder }
      .map {
        UiCategory(
          id = it.id,
          name = it.name,
          emoji = it.emoji,
          monthlyBudget = it.monthlyBudgetMinor?.div(100.0),
          tint = it.tint,
          sortOrder = it.sortOrder,
          system = it.system,
        )
      }
    val catById = categories.associateBy { it.id }
    val prefs = active.firstOrNull { it.entityType == EntityType.Preferences }
      ?.payload as? EntityPayload.Preferences
    val defaultPm = prefs?.defaultPaymentMethodId ?: CASH_PAYMENT_METHOD_ID
    val paymentMethods = active.filter { it.entityType == EntityType.PaymentMethod }
      .map { it.payload as EntityPayload.PaymentMethod }
      .sortedBy { it.name }
      .map {
        UiPaymentMethod(it.id, it.name, it.type, it.detail, it.archived, it.id == defaultPm)
      }
    val pmById = paymentMethods.associateBy { it.id }
    val transactions = active.filter { it.entityType == EntityType.Transaction }
      .map { it.payload as EntityPayload.Transaction }
      .sortedByDescending { it.occurredAt }
      .map { tx ->
        val cat = catById[tx.categoryId]
        UiTransaction(
          id = tx.id,
          name = tx.name,
          amount = tx.amountMinor / 100.0,
          occurredAt = tx.occurredAt,
          categoryId = tx.categoryId,
          category = cat?.name ?: "General",
          emoji = cat?.emoji ?: DEFAULT_CATEGORY_EMOJI,
          tint = cat?.tint?.name ?: "neutral",
          paymentMethodId = tx.paymentMethodId,
          paymentMethod = tx.paymentMethodId?.let { pmById[it]?.name },
        )
      }
    val recurring = active.filter { it.entityType == EntityType.Recurring }
      .map { it.payload as EntityPayload.Recurring }
      .map { rec ->
        val cat = catById[rec.categoryId]
        val ui = UiRecurring(
          id = rec.id,
          name = rec.name,
          amount = rec.amountMinor / 100.0,
          categoryId = rec.categoryId,
          category = cat?.name ?: "General",
          emoji = cat?.emoji ?: DEFAULT_CATEGORY_EMOJI,
          paymentMethodId = rec.paymentMethodId,
          paymentMethod = rec.paymentMethodId?.let { pmById[it]?.name },
          frequency = rec.frequency,
          anchorDate = rec.anchorDate,
          paused = rec.paused,
          dueLabel = DateHelpers.recurringDueLabel(
            DateHelpers.nextOccurrence(rec.anchorDate, rec.frequency),
          ),
        )
        ui to DateHelpers.nextOccurrence(rec.anchorDate, rec.frequency)
      }
      .sortedBy { it.second }
      .map { it.first }
    val lends = active.filter { it.entityType == EntityType.Lend }
      .map { it.payload as EntityPayload.Lend }
      .sortedByDescending { it.occurredAt }
      .map {
        UiLend(
          id = it.id,
          contactName = it.contactName,
          contactId = it.contactId,
          amount = it.amountMinor / 100.0,
          occurredAt = it.occurredAt,
          comment = it.comment,
          kind = it.kind ?: LendKind.lent,
        )
      }

    val nextDefault = prefs?.defaultStatsRange ?: StatsRange.OneYear
    val hydratedRange = StatsConstants.hydratedRange(
      current = _state.value.statsRange,
      previousDefault = previousDefaultStats,
      nextDefault = nextDefault,
      dataReady = true,
    )
    previousDefaultStats = nextDefault

    _state.update { cur ->
      cur.copy(
        dataReady = true,
        categories = categories,
        paymentMethods = paymentMethods,
        transactions = transactions,
        recurring = recurring,
        lends = lends,
        limits = categories.associate { it.name to (it.monthlyBudget ?: 0.0) },
        syncMeta = meta,
        pendingCount = pending,
        blockedCount = blocked,
        currency = prefs?.currency ?: cur.currency,
        theme = prefs?.theme ?: cur.theme,
        navGlassOpacity = prefs?.navGlassOpacity ?: cur.navGlassOpacity,
        defaultStatsRange = nextDefault,
        statsRange = hydratedRange,
        notifications = prefs?.notifications ?: cur.notifications,
        profileName = prefs?.profileName?.takeIf { it.isNotBlank() } ?: session.user.displayName,
        profileEmail = prefs?.profileEmail?.takeIf { it.isNotBlank() } ?: session.user.email,
      )
    }
  }

  private data class Quadriver(
    val entities: List<StoredEntity>,
    val meta: SyncMeta,
    val pending: Int,
    val blocked: Int,
  )
}
