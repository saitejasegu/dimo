package app.dimo.android.store

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.dimo.android.app.AppConfig
import app.dimo.android.auth.WorkOSAuthProvider
import app.dimo.android.auth.WorkOSSession
import app.dimo.android.data.Repository
import app.dimo.android.data.SeedData
import app.dimo.android.data.db.AppDatabase
import app.dimo.android.data.model.CategoryEntity
import app.dimo.android.data.model.CategoryLimits
import app.dimo.android.data.model.CategoryTint
import app.dimo.android.data.model.Currency
import app.dimo.android.data.model.DEFAULT_CATEGORY_EMOJI
import app.dimo.android.data.model.EntityPayload
import app.dimo.android.data.model.EntityType
import app.dimo.android.data.model.Lend
import app.dimo.android.data.model.LendEntity
import app.dimo.android.data.model.LendKind
import app.dimo.android.data.model.NotificationSettings
import app.dimo.android.data.model.PaymentMethodEntity
import app.dimo.android.data.model.PaymentMethodOption
import app.dimo.android.data.model.PaymentMethodType
import app.dimo.android.data.model.PreferencesEntity
import app.dimo.android.data.model.Recurring
import app.dimo.android.data.model.RecurringEntity
import app.dimo.android.data.model.RecurringFrequency
import app.dimo.android.data.model.StatsRange
import app.dimo.android.data.model.StoredEntity
import app.dimo.android.data.model.SyncMeta
import app.dimo.android.data.model.ThemePreference
import app.dimo.android.data.model.Transaction
import app.dimo.android.data.model.TransactionEntity
import app.dimo.android.data.model.ViewKey
import app.dimo.android.data.model.WeekStart
import app.dimo.android.domain.BudgetCategoryInput
import app.dimo.android.domain.BudgetSelectors
import app.dimo.android.domain.DateHelpers
import app.dimo.android.domain.ExchangeRates
import app.dimo.android.domain.ExpenseReminderSettings
import app.dimo.android.domain.ExpenseReminderStore
import app.dimo.android.domain.LendDirection
import app.dimo.android.domain.LendSelectors
import app.dimo.android.domain.OnboardingStore
import app.dimo.android.domain.RateTable
import app.dimo.android.domain.RatesService
import app.dimo.android.domain.RecurringOccurrenceSelection
import app.dimo.android.domain.StatsConstants
import app.dimo.android.domain.TransactionCSV
import app.dimo.android.domain.TransactionFilter
import app.dimo.android.notifications.ExpenseReminderAuthorization
import app.dimo.android.notifications.ExpenseReminderRouter
import app.dimo.android.notifications.ExpenseReminderScheduler
import app.dimo.android.sync.ConvexSyncTransport
import app.dimo.android.sync.NetworkMonitor
import app.dimo.android.sync.SyncCoordinator
import dev.convex.android.ConvexClientWithAuth
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import kotlin.math.max
import kotlin.math.roundToLong
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Port of `ios-native/Dimo/Store/AppStore.swift` without the Email / Gmail
 * suggestions subsystem (Android excludes that surface).
 */
class AppStore(
  application: Application,
  val userId: String,
  profileName: String,
  profileEmail: String,
  profilePhotoUrl: String? = null,
  private val authProvider: WorkOSAuthProvider,
) : AndroidViewModel(application) {

  var profileName by mutableStateOf(profileName)
    private set
  var profileEmail by mutableStateOf(profileEmail)
    private set
  var profilePhotoUrl by mutableStateOf(profilePhotoUrl)
    private set

  private var _view by mutableStateOf(ViewKey.HOME)
  /** Active product destination (iOS `view`). Read-only; navigate via [setView]. */
  val view: ViewKey get() = _view
  var accountReturnView by mutableStateOf<ViewKey?>(null)
  var overlay by mutableStateOf<OverlayKey?>(null)
  var detailId by mutableStateOf<String?>(null)
  var toast by mutableStateOf<String?>(null)
  private var toastJob: Job? = null

  var transactions by mutableStateOf<List<Transaction>>(emptyList())
    private set
  var recurring by mutableStateOf<List<Recurring>>(emptyList())
    private set
  var lends by mutableStateOf<List<Lend>>(emptyList())
    private set
  var categories by mutableStateOf<List<CategoryEntity>>(emptyList())
    private set
  var paymentMethods by mutableStateOf<List<PaymentMethodOption>>(emptyList())
    private set
  var limits by mutableStateOf<CategoryLimits>(emptyMap())
    private set
  var filter by mutableStateOf(TransactionFilter())
  var statsRange by mutableStateOf(StatsRange.ONE_YEAR)
  var selectedMonth by mutableStateOf<String?>(null)
  var merchantsExpanded by mutableStateOf(false)
  var categoriesExpanded by mutableStateOf(false)
  var currency by mutableStateOf(Currency.INR)
    private set
  /** Latest ECB rates for foreign-currency display; null until first fetch/cache. */
  var rates by mutableStateOf<RateTable?>(null)
    private set
  var theme by mutableStateOf(ThemePreference.LIGHT)
    private set
  var navGlassOpacity by mutableStateOf(40.0)
    private set
  var defaultStatsRange by mutableStateOf(StatsRange.ONE_YEAR)
    private set
  var notifications by mutableStateOf(
    NotificationSettings(bills = true, budget = true, weekly = false, large = true),
  )
    private set
  var dataReady by mutableStateOf(false)
    private set
  var syncMeta by mutableStateOf<SyncMeta?>(null)
    private set
  var pendingCount by mutableStateOf(0)
    private set
  var blockedCount by mutableStateOf(0)
    private set
  var deletingHistory by mutableStateOf(false)
    private set

  var expenseReminder by mutableStateOf(ExpenseReminderSettings.DEFAULT)
  var expenseReminderAuthorization by mutableStateOf(ExpenseReminderAuthorization.NotDetermined)

  var expenseDraft by mutableStateOf(ExpenseDraft())
  var recurringDraft by mutableStateOf(RecurringDraft())
  var categoryDraft by mutableStateOf(CategoryDraft())
  var lendDraft by mutableStateOf(LendDraft())

  private val ratesService = RatesService(application)
  private var repository: Repository? = null
  private var coordinator: SyncCoordinator? = null
  private var convexClient: ConvexClientWithAuth<WorkOSSession>? = null
  private var networkMonitor: NetworkMonitor? = null
  private var writeListener: UUID? = null
  private var idCounter = 0
  private var cachedLastPaymentMethodId: String? = null

  private var entityJob: Job? = null
  private var syncMetaJob: Job? = null
  private var outboxCountJob: Job? = null
  private var remoteStartJob: Job? = null

  suspend fun start() {
    try {
      val db = AppDatabase.activate(getApplication(), userId)
      val repo = Repository(db)
      repo.initializeLocalDatabase()
      repository = repo
      cachedLastPaymentMethodId = repo.deviceMeta()?.lastPaymentMethodId
      rates = ratesService.loadCached()

      entityJob?.cancel()
      entityJob = viewModelScope.launch {
        repo.observeEntities().collect { hydrate(it) }
      }
      syncMetaJob?.cancel()
      syncMetaJob = viewModelScope.launch {
        repo.observeSyncMeta().collect { syncMeta = it }
      }
      outboxCountJob?.cancel()
      outboxCountJob = viewModelScope.launch {
        combine(repo.observePendingCount(), repo.observeBlockedCount()) { pending, blocked ->
          pending to blocked
        }.collect { (pending, blocked) ->
          pendingCount = pending
          blockedCount = blocked
        }
      }
      writeListener?.let { repo.removeLocalWriteListener(it) }
      writeListener = repo.onLocalWrite {
        viewModelScope.launch {
          val counts = runCatching { repo.outboxCounts() }.getOrNull() ?: return@launch
          pendingCount = counts.first
          blockedCount = counts.second
        }
      }

      hydrate(repo.allEntities())
      dataReady = true

      expenseReminder = ExpenseReminderStore.load(getApplication(), userId)
      ExpenseReminderRouter.store = this
      refreshExpenseReminderAuthorization()
      // Redeem a notification opt-in taken during onboarding, before any user
      // existed to scope the setting to.
      if (OnboardingStore.consumePendingReminderOptIn(getApplication()) &&
        !expenseReminder.enabled
      ) {
        updateExpenseReminder { it.copy(enabled = true) }
      } else {
        refreshExpenseReminderSchedule()
      }

      remoteStartJob?.cancel()
      remoteStartJob = viewModelScope.launch {
        startRemoteServices(repo)
      }
    } catch (error: CancellationException) {
      throw error
    } catch (error: Throwable) {
      showToast(error.message ?: error.toString())
    }
  }

  private suspend fun startRemoteServices(repo: Repository) {
    try {
      val client = ConvexClientWithAuth(AppConfig.convexURL, authProvider)
      val login = client.loginFromCache()
      login.exceptionOrNull()?.let { error ->
        runCatching {
          repo.updateSyncMeta {
            it.copy(syncing = false, error = error.message ?: error.toString())
          }
        }
        showToast(error.message ?: error.toString())
        return
      }
      convexClient = client

      val transport = ConvexSyncTransport(client)
      val monitor = NetworkMonitor(getApplication())
      networkMonitor = monitor
      val next = SyncCoordinator(
        repository = repo,
        transport = transport,
        network = monitor,
        scope = viewModelScope,
      )
      next.setProfile(profileName, profileEmail)
      coordinator = next
      next.start()
      refreshExchangeRates()
    } catch (_: CancellationException) {
      return
    } catch (error: Throwable) {
      showToast(error.message ?: error.toString())
    }
  }

  suspend fun tearDown() {
    remoteStartJob?.cancel()
    remoteStartJob = null
    entityJob?.cancel()
    entityJob = null
    syncMetaJob?.cancel()
    syncMetaJob = null
    outboxCountJob?.cancel()
    outboxCountJob = null
    writeListener?.let { repository?.removeLocalWriteListener(it) }
    writeListener = null
    coordinator?.stop()
    coordinator = null
    networkMonitor = null
    repository = null
    convexClient = null
    if (ExpenseReminderRouter.store === this) {
      ExpenseReminderRouter.store = null
    }
    ExpenseReminderScheduler.cancel(getApplication())
    ExpenseReminderStore.clear(getApplication(), userId)
    toastJob?.cancel()
    toast = null
  }

  fun sceneBecameActive() {
    viewModelScope.launch {
      coordinator?.request()
      refreshExchangeRates()
      refreshExpenseReminderAuthorization()
      refreshExpenseReminderSchedule()
    }
  }

  fun updateExpenseReminder(mutate: (ExpenseReminderSettings) -> ExpenseReminderSettings) {
    var next = mutate(expenseReminder).clamped
    if (next.enabled && expenseReminderAuthorization != ExpenseReminderAuthorization.Authorized) {
      // Caller is expected to request runtime permission first when needed.
      // If still unauthorized after that attempt, force disabled.
      refreshExpenseReminderAuthorization()
      if (expenseReminderAuthorization != ExpenseReminderAuthorization.Authorized) {
        next = next.copy(enabled = false)
        expenseReminder = next
        ExpenseReminderStore.save(getApplication(), next, userId)
        ExpenseReminderScheduler.cancel(getApplication())
        showToast("Enable notifications for Dimo in Settings to get reminders.")
        return
      }
    }
    expenseReminder = next
    ExpenseReminderStore.save(getApplication(), next, userId)
    refreshExpenseReminderSchedule()
  }

  fun refreshExpenseReminderSchedule() {
    ExpenseReminderScheduler.apply(
      context = getApplication(),
      settings = expenseReminder,
      pendingPurchaseCount = 0,
    )
  }

  fun refreshExpenseReminderAuthorization() {
    expenseReminderAuthorization =
      ExpenseReminderScheduler.authorizationStatus(getApplication())
  }

  private suspend fun refreshExchangeRates() {
    try {
      val table = coordinator?.latestExchangeRates() ?: return
      ratesService.store(table)
      rates = table
    } catch (_: Throwable) {
      // Offline / auth — keep the DataStore cache already seeded into `rates`.
    }
  }

  fun syncNow() {
    coordinator?.request(cancelInFlight = true)
  }

  fun requestFullSync() {
    coordinator?.requestFullSync()
  }

  suspend fun clearCloudWorkspace() {
    coordinator?.clearCloudWorkspace()
  }

  // MARK: - Navigation

  fun setView(next: ViewKey) {
    _view = if (next == ViewKey.TX || next == ViewKey.RECURRING) ViewKey.HOME else next
  }

  fun openAccount() {
    accountReturnView = _view
    _view = ViewKey.ACCOUNT
  }

  fun closeAccount() {
    _view = accountReturnView ?: ViewKey.HOME
    accountReturnView = null
  }

  fun openOverlay(key: OverlayKey) {
    when (key) {
      OverlayKey.Add -> {
        expenseDraft = ExpenseDraft(
          category = "",
          paymentMethodId = preferredPaymentMethodId(),
        )
      }
      OverlayKey.Recurring -> {
        recurringDraft = RecurringDraft(
          currency = currency.wire,
          category = categories.firstOrNull { it.name == "Bills" }?.name
            ?: categories.firstOrNull()?.name
            ?: "Bills",
          paymentMethodId = preferredPaymentMethodId(),
          anchorDate = DateHelpers.localDateKey(LocalDate.now(DateHelpers.zone())),
        )
      }
      OverlayKey.Category -> categoryDraft = CategoryDraft()
      OverlayKey.Lend -> lendDraft = LendDraft()
    }
    overlay = key
  }

  fun closeOverlay() {
    overlay = null
  }

  fun openDetail(id: String) {
    detailId = id
  }

  fun closeDetail() {
    detailId = null
  }

  // MARK: - Mutations

  private data class TransactionCurrencyFields(
    val amountMinor: Long,
    val currency: String,
    val sourceCurrency: String?,
    val sourceAmountMinor: Long?,
    val exchangeRate: Double?,
  )

  /**
   * Converts a one-off expense into the account currency while retaining its
   * original amount and rate for later display and editing. Always stamps
   * `currency` with the account default at write time.
   */
  private fun transactionCurrencyFields(
    amount: Double,
    entryCurrency: String,
  ): TransactionCurrencyFields? {
    val sourceMinor = max(1L, ExchangeRates.toMinorUnits(amount, entryCurrency))
    val defaultCurrency = currency.wire
    if (entryCurrency == defaultCurrency) {
      return TransactionCurrencyFields(sourceMinor, defaultCurrency, null, null, null)
    }
    val convertedMinor = ExchangeRates.convertMinor(
      sourceMinor,
      from = entryCurrency,
      to = defaultCurrency,
      rates = rates,
    ) ?: return null
    val rate = ExchangeRates.rateBetween(entryCurrency, defaultCurrency, rates) ?: return null
    return TransactionCurrencyFields(
      amountMinor = max(1L, convertedMinor),
      currency = defaultCurrency,
      sourceCurrency = entryCurrency,
      sourceAmountMinor = sourceMinor,
      exchangeRate = rate,
    )
  }

  fun saveExpense() {
    val amount = expenseDraft.amount.toDoubleOrNull() ?: return
    if (amount <= 0) return
    val category = categories.firstOrNull { it.name == expenseDraft.category } ?: return
    val id = makeId("tx_")
    val paymentMethodId = resolvedPaymentMethodId(expenseDraft.paymentMethodId)
    val trimmed = expenseDraft.name.trim()
    val entity = TransactionEntity(
      id = id,
      name = if (trimmed.isEmpty()) category.name else trimmed,
      amountMinor = (amount * 100).roundToLong(),
      occurredAt = expenseDraft.date.toEpochMilli(),
      categoryId = category.id,
      paymentMethodId = paymentMethodId,
      currency = currency.wire,
    )
    viewModelScope.launch {
      repository?.saveEntity(EntityPayload.Transaction(entity))
      repository?.setLastPaymentMethod(paymentMethodId)
      cachedLastPaymentMethodId = paymentMethodId
      filter = TransactionFilter()
      closeOverlay()
      setView(ViewKey.HOME)
      showToast("Expense saved")
    }
  }

  fun saveExpense(
    name: String,
    amount: Double,
    categoryName: String,
    paymentMethodId: String?,
    date: Instant,
    recurringFrequency: RecurringFrequency?,
    occurrenceSelection: RecurringOccurrenceSelection = RecurringOccurrenceSelection.SELECTED,
    entryCurrency: String? = null,
  ) {
    if (amount <= 0) return
    val category = categories.firstOrNull { it.name == categoryName } ?: return
    val trimmedName = name.trim()
    val resolvedEntryCurrency = entryCurrency ?: currency.wire
    val converted = transactionCurrencyFields(amount, resolvedEntryCurrency)
    if (converted == null) {
      showToast("Exchange rates unavailable — try again once online")
      return
    }

    val resolvedMethodId = resolvedPaymentMethodId(paymentMethodId)
    if (recurringFrequency == null) {
      val transaction = TransactionEntity(
        id = makeId("tx_"),
        name = if (trimmedName.isEmpty()) category.name else trimmedName,
        amountMinor = converted.amountMinor,
        occurredAt = minOf(date.toEpochMilli(), System.currentTimeMillis()),
        categoryId = category.id,
        paymentMethodId = resolvedMethodId,
        currency = converted.currency,
        sourceCurrency = converted.sourceCurrency,
        sourceAmountMinor = converted.sourceAmountMinor,
        exchangeRate = converted.exchangeRate,
      )
      viewModelScope.launch {
        repository?.saveEntity(EntityPayload.Transaction(transaction))
        repository?.setLastPaymentMethod(resolvedMethodId)
        cachedLastPaymentMethodId = resolvedMethodId
        closeOverlay()
        setView(ViewKey.HOME)
        showToast("Expense saved")
      }
      return
    }

    if (trimmedName.isEmpty()) return
    val anchorDate = DateHelpers.localDateKey(date.toEpochMilli())
    val (recurringMinor, recurringCurrency) =
      ExchangeRates.recurringFields(amount, resolvedEntryCurrency)
    val recurringEntity = RecurringEntity(
      id = makeId("rec_"),
      name = trimmedName,
      amountMinor = recurringMinor,
      categoryId = category.id,
      paymentMethodId = resolvedMethodId,
      frequency = recurringFrequency,
      anchorDate = anchorDate,
      paused = false,
      currency = recurringCurrency,
    )
    val dates = DateHelpers.recurringTransactionDates(
      anchorDate = anchorDate,
      frequency = recurringFrequency,
      selection = occurrenceSelection,
    )
    val zone = DateHelpers.zone()
    val entryTime = date.atZone(zone).toLocalTime()
    val batch = mutableListOf<EntityPayload>(EntityPayload.Recurring(recurringEntity))
    for (occurrence in dates) {
      batch.add(
        EntityPayload.Transaction(
          TransactionEntity(
            id = makeId("tx_"),
            name = trimmedName,
            amountMinor = converted.amountMinor,
            occurredAt = DateHelpers.occurrenceTimestamp(occurrence, entryTime),
            categoryId = category.id,
            paymentMethodId = resolvedMethodId,
            currency = converted.currency,
            sourceCurrency = converted.sourceCurrency,
            sourceAmountMinor = converted.sourceAmountMinor,
            exchangeRate = converted.exchangeRate,
          ),
        ),
      )
    }
    viewModelScope.launch {
      repository?.saveEntities(batch)
      repository?.setLastPaymentMethod(resolvedMethodId)
      cachedLastPaymentMethodId = resolvedMethodId
      closeOverlay()
      setView(ViewKey.HOME)
      showToast(
        if (dates.isEmpty()) {
          "Recurring expense added"
        } else {
          val suffix = if (dates.size == 1) "" else "s"
          "Recurring expense added · ${dates.size} transaction$suffix"
        },
      )
    }
  }

  fun saveLend() {
    val amount = lendDraft.amount.toDoubleOrNull() ?: return
    if (amount <= 0) return
    val contact = lendDraft.contactName.trim()
    if (contact.isEmpty()) return
    val existing = lendDraft.editingId?.let { id -> lends.firstOrNull { it.id == id } }
    val contactId = lendDraft.contactId ?: existing?.contactId ?: return
    // Editing never flips direction; the saved row's kind wins.
    val kind = existing?.kind ?: lendDraft.kind
    val limit = LendSelectors.settlementLimit(
      kind = kind,
      contactId = contactId,
      lends = lends,
      excludingLendId = existing?.id,
    )
    if (limit != null && amount > limit + 0.000_001) return
    val zone = DateHelpers.zone()
    val occurredAt = if (
      existing != null &&
      Instant.ofEpochMilli(existing.occurredAt).atZone(zone).toLocalDate() ==
      lendDraft.date.atZone(zone).toLocalDate()
    ) {
      existing.occurredAt
    } else {
      lendTimestamp(lendDraft.date)
    }
    val entity = LendEntity(
      id = existing?.id ?: makeId("lend_"),
      contactName = contact,
      contactId = contactId,
      amountMinor = (amount * 100).roundToLong(),
      occurredAt = occurredAt,
      comment = lendDraft.comment.trim(),
      kind = kind,
    )
    viewModelScope.launch {
      repository?.saveEntity(EntityPayload.Lend(entity))
      closeOverlay()
      val noun = lendNoun(kind)
      showToast(if (existing == null) "$noun saved" else "$noun updated")
    }
  }

  fun openEditLend(id: String) {
    val lend = lends.firstOrNull { it.id == id } ?: return
    lendDraft = LendDraft(
      editingId = id,
      kind = lend.kind,
      contactName = lend.contactName,
      contactId = lend.contactId,
      amount = if (lend.amount.roundToLong().toDouble() == lend.amount) {
        lend.amount.toLong().toString()
      } else {
        String.format("%.2f", lend.amount)
      },
      date = Instant.ofEpochMilli(lend.occurredAt),
      comment = lend.comment,
    )
    overlay = OverlayKey.Lend
  }

  /**
   * Opens the sheet pre-set to whichever entry closes this contact's balance:
   * a repayment when they owe the user, a payment back when the user owes them.
   */
  fun openAddSettlement(contactName: String, contactId: String, direction: LendDirection) {
    lendDraft = LendDraft(
      kind = direction.settlementKind,
      contactName = contactName,
      contactId = contactId,
    )
    overlay = OverlayKey.Lend
  }

  fun deleteLend(id: String) {
    val kind = lends.firstOrNull { it.id == id }?.kind ?: LendKind.LENT
    viewModelScope.launch {
      repository?.removeEntity(EntityType.LEND, id)
      closeOverlay()
      showToast("${lendNoun(kind)} deleted")
    }
  }

  private fun lendNoun(kind: LendKind): String = when (kind) {
    LendKind.LENT -> "Lend"
    LendKind.REPAID -> "Repayment"
    LendKind.BORROWED -> "Borrowing"
    LendKind.RETURNED -> "Payment"
  }

  /** Today keeps the current time so entries order naturally; past dates pin to noon. */
  private fun lendTimestamp(date: Instant): Long {
    val zone = DateHelpers.zone()
    val local = date.atZone(zone).toLocalDate()
    return if (local == LocalDate.now(zone)) {
      System.currentTimeMillis()
    } else {
      DateHelpers.occurrenceTimestamp(local)
    }
  }

  fun deleteTransaction(id: String) {
    viewModelScope.launch {
      repository?.removeEntity(EntityType.TRANSACTION, id)
      closeDetail()
      showToast("Transaction deleted")
    }
  }

  fun deleteRecurring(id: String) {
    viewModelScope.launch {
      repository?.removeEntity(EntityType.RECURRING, id)
      closeOverlay()
      showToast("Recurring transaction deleted")
    }
  }

  fun deleteCategoryAndTransactions(categoryId: String) {
    val transactionIds = transactions.filter { it.categoryId == categoryId }.map { it.id }
    viewModelScope.launch {
      for (id in transactionIds) {
        repository?.removeEntity(EntityType.TRANSACTION, id)
      }
      repository?.removeEntity(EntityType.CATEGORY, categoryId)
      closeOverlay()
      showToast(
        if (transactionIds.isEmpty()) {
          "Category deleted"
        } else {
          val suffix = if (transactionIds.size == 1) "" else "s"
          "Category and ${transactionIds.size} transaction$suffix deleted"
        },
      )
    }
  }

  fun saveTransactionEdits(
    id: String,
    name: String,
    amount: Double,
    categoryName: String,
    paymentMethodId: String?,
    date: Instant,
    entryCurrency: String? = null,
  ) {
    if (amount <= 0) return
    val category = categories.firstOrNull { it.name == categoryName } ?: return
    if (transactions.none { it.id == id }) return
    val converted = transactionCurrencyFields(amount, entryCurrency ?: currency.wire)
    if (converted == null) {
      showToast("Exchange rates unavailable — try again once online")
      return
    }
    val entity = TransactionEntity(
      id = id,
      name = name,
      amountMinor = converted.amountMinor,
      occurredAt = date.toEpochMilli(),
      categoryId = category.id,
      paymentMethodId = resolvedPaymentMethodId(paymentMethodId),
      currency = converted.currency,
      sourceCurrency = converted.sourceCurrency,
      sourceAmountMinor = converted.sourceAmountMinor,
      exchangeRate = converted.exchangeRate,
    )
    viewModelScope.launch {
      repository?.saveEntity(EntityPayload.Transaction(entity))
      closeDetail()
      showToast("Transaction updated")
    }
  }

  fun saveRecurring(includeHistoricalTransactions: Boolean = false) {
    val amount = recurringDraft.amount.toDoubleOrNull() ?: return
    if (amount <= 0) return
    val category = categories.firstOrNull { it.name == recurringDraft.category } ?: return
    val name = recurringDraft.name.trim()
    if (name.isEmpty()) return
    val id = recurringDraft.editingId ?: makeId("rec_")
    val entryCurrency = recurringDraft.currency ?: currency.wire
    val converted = transactionCurrencyFields(amount, entryCurrency)
    if (recurringDraft.editingId == null && converted == null) {
      showToast("Exchange rates unavailable — try again once online")
      return
    }
    val (recurringMinor, recurringCurrency) = ExchangeRates.recurringFields(amount, entryCurrency)
    val paymentMethodId = resolvedPaymentMethodId(recurringDraft.paymentMethodId)
    val entity = RecurringEntity(
      id = id,
      name = name,
      amountMinor = recurringMinor,
      categoryId = category.id,
      paymentMethodId = paymentMethodId,
      frequency = recurringDraft.frequency,
      anchorDate = recurringDraft.anchorDate,
      paused = recurringDraft.paused,
      currency = recurringCurrency,
    )
    val batch = mutableListOf<EntityPayload>(EntityPayload.Recurring(entity))
    if (recurringDraft.editingId == null) {
      val fields = converted!!
      val anchor = DateHelpers.parseLocalDate(entity.anchorDate)
      val today = LocalDate.now(DateHelpers.zone())
      val occurrenceDates = when {
        includeHistoricalTransactions -> DateHelpers.occurrencesThrough(
          anchorDate = entity.anchorDate,
          frequency = entity.frequency,
        )
        anchor == today -> listOf(anchor)
        else -> emptyList()
      }
      for (date in occurrenceDates) {
        batch.add(
          EntityPayload.Transaction(
            TransactionEntity(
              id = makeId("tx_"),
              name = name,
              amountMinor = fields.amountMinor,
              occurredAt = DateHelpers.occurrenceTimestamp(date),
              categoryId = category.id,
              paymentMethodId = entity.paymentMethodId,
              currency = fields.currency,
              sourceCurrency = fields.sourceCurrency,
              sourceAmountMinor = fields.sourceAmountMinor,
              exchangeRate = fields.exchangeRate,
            ),
          ),
        )
      }
    }
    val isNew = recurringDraft.editingId == null
    viewModelScope.launch {
      repository?.saveEntities(batch)
      closeOverlay()
      showToast(if (isNew) "Recurring added" else "Recurring updated")
    }
  }

  fun openEditRecurring(id: String) {
    val rec = recurring.firstOrNull { it.id == id } ?: return
    recurringDraft = RecurringDraft(
      editingId = id,
      name = rec.name,
      amount = String.format("%.2f", rec.amount),
      currency = rec.currency,
      category = rec.category,
      paymentMethodId = rec.paymentMethodId,
      frequency = rec.frequency ?: RecurringFrequency.MONTHLY,
      anchorDate = rec.anchorDate
        ?: DateHelpers.localDateKey(LocalDate.now(DateHelpers.zone())),
      paused = rec.paused,
    )
    overlay = OverlayKey.Recurring
  }

  fun toggleRecurring(id: String) {
    viewModelScope.launch {
      val existing = repository?.activeEntities(EntityType.RECURRING)
        ?.firstOrNull { it.entityId == id }
        ?: return@launch
      val payload = (existing.payload as? EntityPayload.Recurring)?.value ?: return@launch
      val next = payload.copy(
        currency = payload.currency ?: currency.wire,
        paused = !payload.paused,
      )
      repository?.saveEntity(EntityPayload.Recurring(next))
      showToast(if (next.paused) "Paused" else "Resumed")
    }
  }

  fun saveCategory() {
    val name = categoryDraft.name.trim()
    if (name.isEmpty()) return
    val id = categoryDraft.editingId ?: makeId("category_")
    val limit = categoryDraft.limitText.toDoubleOrNull()?.let { value ->
      if (value > 0) (value * 100).roundToLong() else null
    }
    val existing = categories.firstOrNull { it.id == id }
    val entity = CategoryEntity(
      id = id,
      name = name,
      emoji = if (categoryDraft.emoji.isEmpty()) DEFAULT_CATEGORY_EMOJI else categoryDraft.emoji,
      monthlyBudgetMinor = limit,
      tint = categoryDraft.tint,
      sortOrder = existing?.sortOrder ?: categories.size,
      system = existing?.system ?: false,
    )
    val isNew = categoryDraft.editingId == null
    viewModelScope.launch {
      repository?.saveEntity(EntityPayload.Category(entity))
      closeOverlay()
      showToast(if (isNew) "Category created" else "Category updated")
    }
  }

  fun openEditCategory(id: String) {
    val cat = categories.firstOrNull { it.id == id } ?: return
    categoryDraft = CategoryDraft(
      editingId = id,
      name = cat.name,
      emoji = cat.emoji,
      limitText = cat.monthlyBudgetMinor?.let { String.format("%.0f", it.toDouble() / 100) } ?: "",
      tint = cat.tint,
    )
    overlay = OverlayKey.Category
  }

  fun applySuggestedBudgets(ids: Set<String>) {
    val suggestions = BudgetSelectors.suggestedCategoryBudgetUpdates(
      transactions,
      categories = categories.map {
        BudgetCategoryInput(it.id, it.name, it.monthlyBudgetMinor)
      },
    )
    val batch = mutableListOf<EntityPayload>()
    for (suggestion in suggestions) {
      if (suggestion.id !in ids) continue
      val cat = categories.firstOrNull { it.id == suggestion.id } ?: continue
      batch.add(
        EntityPayload.Category(
          cat.copy(monthlyBudgetMinor = (suggestion.suggestedLimit * 100).roundToLong()),
        ),
      )
    }
    viewModelScope.launch {
      repository?.saveEntities(batch)
      showToast("Budgets updated")
    }
  }

  fun updatePreferences(mutate: (PreferencesEntity) -> PreferencesEntity) {
    viewModelScope.launch {
      val prefs = mutate(currentPreferences())
      repository?.saveEntity(EntityPayload.Preferences(prefs))
    }
  }

  fun pressAmountKey(key: String) {
    expenseDraft = expenseDraft.copy(amount = applyKeypad(expenseDraft.amount, key))
  }

  fun exportCSV(): String {
    val sources = transactions.map {
      TransactionCSV.Source(
        name = it.name,
        category = it.category,
        amount = it.amount,
        amountMinor = it.amountMinor,
        occurredAt = it.occurredAt,
      )
    }
    return TransactionCSV.format(sources)
  }

  suspend fun importCSV(text: String) {
    val rows = TransactionCSV.parse(text)
    val defaultPM = TransactionCSV.defaultPaymentMethodIdForImport(paymentMethods)
    val categoryByName = categories.associateBy { it.name.lowercase() }.toMutableMap()
    val batch = mutableListOf<EntityPayload>()
    for (row in rows) {
      val key = row.category.lowercase()
      val category = categoryByName[key] ?: run {
        val created = CategoryEntity(
          id = makeId("category_"),
          name = row.category,
          emoji = TransactionCSV.categoryEmojiForName(row.category),
          monthlyBudgetMinor = null,
          tint = CategoryTint.NEUTRAL,
          sortOrder = categories.size + batch.size,
          system = false,
        )
        categoryByName[key] = created
        batch.add(EntityPayload.Category(created))
        created
      }
      batch.add(
        EntityPayload.Transaction(
          TransactionEntity(
            id = makeId("tx_"),
            name = row.merchant,
            amountMinor = row.amountMinor,
            occurredAt = row.occurredAt,
            categoryId = category.id,
            paymentMethodId = defaultPM,
            currency = currency.wire,
          ),
        ),
      )
    }
    repository?.saveEntities(batch)
    showToast("Imported ${rows.size} transactions")
  }

  fun deleteHistory() {
    val repo = repository ?: return
    if (deletingHistory) return
    deletingHistory = true
    viewModelScope.launch {
      try {
        val count = withContext(Dispatchers.IO) {
          repo.removeActiveEntities(EntityType.TRANSACTION)
        }
        showToast(
          if (count == 1) "Transaction deleted" else "$count transactions deleted",
        )
      } catch (_: Throwable) {
        showToast("Could not delete history")
      }
      deletingHistory = false
    }
  }

  fun deleteTransactions(ids: List<String>) {
    if (ids.isEmpty()) return
    viewModelScope.launch {
      for (id in ids) {
        repository?.removeEntity(EntityType.TRANSACTION, id)
      }
      showToast(
        if (ids.size == 1) "Transaction deleted" else "${ids.size} transactions deleted",
      )
    }
  }

  /** Returns a validation error message, or null on success. */
  fun savePaymentMethod(
    id: String?,
    name: String,
    type: PaymentMethodType,
    detail: String,
  ): String? {
    val trimmed = name.trim()
    if (trimmed.isEmpty()) {
      val message = "Enter a name for this payment method."
      showToast(message)
      return message
    }
    val duplicate = paymentMethods.any {
      it.id != id && it.name.equals(trimmed, ignoreCase = true)
    }
    if (duplicate) {
      val message = "That payment method already exists."
      showToast(message)
      return message
    }
    val methodId = id ?: makeId("payment-method_")
    val entity = PaymentMethodEntity(
      id = methodId,
      name = trimmed,
      type = type,
      detail = if (type == PaymentMethodType.CASH) "" else detail.trim(),
      archived = paymentMethods.firstOrNull { it.id == methodId }?.archived ?: false,
    )
    viewModelScope.launch {
      repository?.saveEntity(EntityPayload.PaymentMethod(entity))
      showToast(if (id == null) "Payment method added" else "Payment method updated")
    }
    return null
  }

  fun setDefaultPaymentMethod(id: String) {
    updatePreferences { it.copy(defaultPaymentMethodId = id) }
    showToast("Default payment updated")
  }

  fun setPaymentMethodArchived(id: String, archived: Boolean) {
    val method = paymentMethods.firstOrNull { it.id == id } ?: return
    if (archived && id == SeedData.CASH_PAYMENT_METHOD.id) {
      showToast("Cash can't be archived")
      return
    }
    val activeCount = paymentMethods.count { !it.archived }
    if (archived && activeCount <= 1) {
      showToast("Keep at least one payment method")
      return
    }
    val entity = PaymentMethodEntity(
      id = method.id,
      name = method.name,
      type = method.type,
      detail = method.detail,
      archived = archived,
    )
    val batch = mutableListOf<EntityPayload>(EntityPayload.PaymentMethod(entity))
    if (archived && method.isDefault) {
      val next = paymentMethods.firstOrNull { !it.archived && it.id != id }
      if (next != null) {
        batch.add(
          EntityPayload.Preferences(
            currentPreferences().copy(defaultPaymentMethodId = next.id),
          ),
        )
      }
    }
    viewModelScope.launch {
      repository?.saveEntities(batch)
      showToast(if (archived) "Payment method archived" else "Payment method restored")
    }
  }

  fun showToast(message: String) {
    toast = message
    toastJob?.cancel()
    toastJob = viewModelScope.launch {
      delay(1_800)
      toast = null
    }
  }

  /**
   * Resolves a row emoji the same way the web does: explicit value, then the
   * category looked up by id, then by name, then the default.
   */
  fun categoryEmoji(explicit: String?, categoryId: String?, category: String): String =
    explicit
      ?: categories.firstOrNull { it.id == categoryId }?.emoji
      ?: categories.firstOrNull { it.name == category }?.emoji
      ?: DEFAULT_CATEGORY_EMOJI

  // MARK: - Hydration

  private fun hydrate(entities: List<StoredEntity>) {
    val active = entities.filter { !it.deleted }
    val nextCategories = mutableListOf<CategoryEntity>()
    val nextPaymentMethods = mutableListOf<PaymentMethodEntity>()
    val nextTransactions = mutableListOf<TransactionEntity>()
    val nextRecurring = mutableListOf<RecurringEntity>()
    val nextLends = mutableListOf<LendEntity>()
    var prefs = SeedData.DEFAULT_PREFERENCES

    for (entity in active) {
      when (val payload = entity.payload) {
        is EntityPayload.Category -> nextCategories.add(payload.value)
        is EntityPayload.PaymentMethod -> nextPaymentMethods.add(payload.value)
        is EntityPayload.Transaction -> nextTransactions.add(payload.value)
        is EntityPayload.Recurring -> nextRecurring.add(payload.value)
        is EntityPayload.Lend -> nextLends.add(payload.value)
        is EntityPayload.Preferences -> prefs = payload.value
      }
    }

    nextCategories.sortBy { it.sortOrder }
    categories = nextCategories
    limits = nextCategories.associate { cat ->
      cat.name to cat.monthlyBudgetMinor?.let { it.toDouble() / 100 }
    }
    val defaultPM = prefs.defaultPaymentMethodId
    paymentMethods = nextPaymentMethods
      .sortedBy { it.name }
      .map {
        PaymentMethodOption(
          id = it.id,
          name = it.name,
          type = it.type,
          detail = it.detail,
          isDefault = it.id == defaultPM,
          archived = it.archived,
        )
      }

    val categoryById = nextCategories.associateBy { it.id }
    val pmById = paymentMethods.associateBy { it.id }
    val currentRates = rates

    transactions = nextTransactions
      .sortedByDescending { it.occurredAt }
      .map { tx ->
        val cat = categoryById[tx.categoryId]
        val pm = tx.paymentMethodId?.let { pmById[it] }
        val sourceAmount = tx.sourceCurrency?.let { code ->
          tx.sourceAmountMinor?.let { ExchangeRates.toMajorUnits(it, code) }
        }
        val amountCurrency = tx.currency ?: prefs.currency.wire
        Transaction(
          id = tx.id,
          name = tx.name,
          category = cat?.name ?: "Unknown",
          time = DateHelpers.formatTransactionTime(tx.occurredAt),
          day = DateHelpers.formatTransactionDay(tx.occurredAt),
          amount = ExchangeRates.transactionAmountInDefault(
            amountMinor = tx.amountMinor,
            currency = tx.currency,
            defaultCurrency = prefs.currency.wire,
            rates = currentRates,
          ),
          paymentMethod = pm?.label,
          green = cat?.tint == CategoryTint.GREEN,
          emoji = cat?.emoji,
          amountMinor = tx.amountMinor,
          occurredAt = tx.occurredAt,
          categoryId = tx.categoryId,
          paymentMethodId = tx.paymentMethodId,
          currency = amountCurrency,
          sourceCurrency = tx.sourceCurrency,
          sourceAmount = sourceAmount,
        )
      }

    lends = nextLends
      .sortedByDescending { it.occurredAt }
      .map { lend ->
        Lend(
          id = lend.id,
          contactName = lend.contactName,
          contactId = lend.contactId,
          amount = lend.amountMinor.toDouble() / 100,
          comment = lend.comment,
          time = DateHelpers.formatTransactionTime(lend.occurredAt),
          day = DateHelpers.formatTransactionDay(lend.occurredAt),
          amountMinor = lend.amountMinor,
          occurredAt = lend.occurredAt,
          kind = lend.kind ?: LendKind.LENT,
        )
      }

    nextRecurring.sortBy {
      DateHelpers.nextOccurrence(anchorDate = it.anchorDate, frequency = it.frequency)
    }
    recurring = nextRecurring.map { rec ->
      val cat = categoryById[rec.categoryId]
      Recurring(
        id = rec.id,
        name = rec.name,
        category = cat?.name ?: "",
        due = DateHelpers.recurringDueLabel(
          anchorDate = rec.anchorDate,
          frequency = rec.frequency,
        ),
        amount = ExchangeRates.toMajorUnits(
          rec.amountMinor,
          rec.currency ?: prefs.currency.wire,
        ),
        paused = rec.paused,
        green = cat?.tint == CategoryTint.GREEN,
        emoji = cat?.emoji,
        amountMinor = rec.amountMinor,
        categoryId = rec.categoryId,
        paymentMethodId = rec.paymentMethodId,
        anchorDate = rec.anchorDate,
        frequency = rec.frequency,
        currency = rec.currency,
      )
    }

    val previousDefaultStatsRange = defaultStatsRange
    currency = prefs.currency
    theme = prefs.theme
    navGlassOpacity = prefs.navGlassOpacity.toDouble()
    defaultStatsRange = prefs.defaultStatsRange
    notifications = prefs.notifications
    statsRange = StatsConstants.hydratedRange(
      current = statsRange,
      previousDefault = previousDefaultStatsRange,
      nextDefault = prefs.defaultStatsRange,
      dataReady = dataReady,
    )
    if (profileName.isEmpty()) profileName = prefs.profileName
    if (profileEmail.isEmpty()) profileEmail = prefs.profileEmail
    dataReady = true
  }

  private fun currentPreferences(): PreferencesEntity = PreferencesEntity(
    id = "preferences",
    profileName = profileName,
    profileEmail = profileEmail,
    currency = currency,
    weekStart = WeekStart.MON,
    theme = theme,
    navGlassOpacity = navGlassOpacity.roundToLong().toInt(),
    defaultView = ViewKey.HOME,
    defaultStatsRange = defaultStatsRange,
    notifications = notifications,
    defaultPaymentMethodId = paymentMethods.firstOrNull { it.isDefault }?.id
      ?: SeedData.CASH_PAYMENT_METHOD.id,
  )

  private fun preferredPaymentMethodId(): String {
    val last = cachedLastPaymentMethodId
    if (
      last != null &&
      paymentMethods.any { it.id == last && !it.archived }
    ) {
      return last
    }
    return paymentMethods.firstOrNull { it.isDefault && !it.archived }?.id
      ?: paymentMethods.firstOrNull { !it.archived }?.id
      ?: SeedData.CASH_PAYMENT_METHOD.id
  }

  private fun resolvedPaymentMethodId(requested: String?): String {
    val trimmed = requested?.trim().orEmpty()
    if (trimmed.isNotEmpty() && paymentMethods.any { it.id == trimmed }) {
      return trimmed
    }
    return preferredPaymentMethodId()
  }

  private fun makeId(prefix: String): String {
    idCounter += 1
    return "${prefix}${System.currentTimeMillis()}_$idCounter"
  }

  private fun applyKeypad(current: String, key: String): String {
    if (key == "⌫") {
      return if (current.isEmpty()) "" else current.dropLast(1)
    }
    if (key == ".") {
      return when {
        current.contains(".") -> current
        current.isEmpty() -> "0."
        else -> "$current."
      }
    }
    val digits = current.filter { it.isDigit() }
    if (digits.length >= 7) return current
    if (current == "0" && key != ".") return key
    return current + key
  }
}
