package app.dimo.android.features.email

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.MailOutline
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.dimo.android.design.ActionButton
import app.dimo.android.design.ActionButtonVariant
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.data.model.EmailAnalysisProvider
import app.dimo.android.data.model.OpenRouterAccessMode

/**
 * Port of `ios-native/Dimo/Features/Email/EmailScreen.swift`.
 *
 * The account strip and filter chips are pinned; only the results scroll, so the
 * user never loses the refresh affordance while paging through suggestions.
 */
@Composable
fun EmailScreen(
  store: EmailFeatureStore,
  onOpenSettings: () -> Unit,
  modifier: Modifier = Modifier,
) {
  Column(
    modifier = modifier
      .fillMaxSize()
      .background(DimoColors.canvas),
  ) {
    EmailHeader(store = store, onOpenSettings = onOpenSettings)

    if (store.accounts.isEmpty()) {
      LazyColumn(
        contentPadding = androidx.compose.foundation.layout.PaddingValues(
          start = 22.dp,
          end = 22.dp,
          top = 10.dp,
          bottom = 34.dp,
        ),
      ) {
        item { ConnectAccountCard(store) }
      }
    } else {
      Column(
        verticalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier
          .fillMaxWidth()
          .padding(horizontal = 22.dp)
          .padding(top = 10.dp, bottom = 12.dp),
      ) {
        AccountAndAnalyzerStrip(store, onOpenSettings)
        EmailFilters(store)
      }

      LazyColumn(
        verticalArrangement = Arrangement.spacedBy(16.dp),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(
          start = 22.dp,
          end = 22.dp,
          bottom = 34.dp,
        ),
      ) {
        if (store.selectedFilter.displaysMessages) {
          if (store.filteredEmails.isEmpty()) {
            item { EmailEmptyState(store.selectedFilter) }
          } else {
            // Suggestion and message rows share the email key as their identity,
            // so the key is namespaced per card type to avoid reuse across tabs.
            items(store.filteredEmails, key = { "message:${it.id}" }) { email ->
              EmailMessageStatusCard(
                email = email,
                onOpen = { store.presentEmail(email.id) },
                onRestore = if (email.analysisState == EmailUIMessageAnalysisState.DISMISSED) {
                  { store.restoreSuggestion(email.id) }
                } else {
                  null
                },
                onRetry = if (email.analysisState == EmailUIMessageAnalysisState.FAILED) {
                  { store.retryAnalysis(email.id) }
                } else {
                  null
                },
              )
            }
          }
        } else if (store.filteredSuggestions.isEmpty()) {
          item { EmailEmptyState(store.selectedFilter) }
        } else {
          items(store.filteredSuggestions, key = { "suggestion:${it.id}" }) { suggestion ->
            EmailSuggestionCard(
              suggestion = suggestion,
              activeCurrency = store.activeCurrency,
              onOpen = { store.presentSources(suggestion) },
              onReview = { store.review(suggestion) },
              onDismiss = { store.dismissSuggestion(suggestion) },
              onRestore = if (suggestion.status == EmailUISuggestionStatus.DISMISSED) {
                { store.restoreSuggestion(suggestion) }
              } else {
                null
              },
              onLinkLate = suggestion.lateMatch?.let { { store.linkLateSuggestion(suggestion) } },
              onKeepLateSeparate = suggestion.lateMatch?.let {
                { store.keepLateSuggestionSeparate(suggestion) }
              },
            )
          }
        }
        item { PrivacyNote(store) }
      }
    }
  }

  store.emailDetail?.let { EmailDetailSheet(it, store::dismissEmailDetail) }
  store.sourceEmailsPresentation?.let { presentation ->
    SourceEmailsSheet(
      presentation = presentation,
      onClose = store::dismissSourceEmails,
      onShowSeparately = if (presentation.canSeparate) {
        {
          val suggestion = presentation.suggestion
          store.dismissSourceEmails()
          store.separateSuggestion(suggestion)
        }
      } else {
        null
      },
    )
  }
  store.purchaseReview?.let { draft ->
    EmailPurchaseReviewSheet(store, draft) { store.purchaseReview = null }
  }
  store.refundReview?.let { review ->
    RefundReviewSheet(
      review = review,
      activeCurrency = store.activeCurrency,
      onCancel = { store.refundReview = null },
      onMarkReviewed = {
        store.dismissSuggestion(it.suggestionId)
        store.refundReview = null
      },
      onConfirm = { store.applyFullRefund(it) },
    )
  }

  store.lastActionError?.let { message ->
    AlertDialog(
      onDismissRequest = store::clearError,
      title = { Text("Email action failed", style = DimoFont.display(17f, FontWeight.SemiBold)) },
      text = { Text(message, style = DimoFont.body(14f)) },
      confirmButton = {
        val accountId = store.pendingReconnectAccountId
        if (accountId != null) {
          TextButton(onClick = {
            store.clearError()
            store.reconnectAccount(accountId)
          }) { Text("Reconnect Gmail") }
        } else {
          TextButton(onClick = store::clearError) { Text("OK") }
        }
      },
      dismissButton = if (store.pendingReconnectAccountId != null) {
        { TextButton(onClick = store::clearError) { Text("OK") } }
      } else {
        null
      },
      containerColor = DimoColors.surface,
    )
  }
}

@Composable
private fun EmailHeader(store: EmailFeatureStore, onOpenSettings: () -> Unit) {
  Row(
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
    modifier = Modifier
      .fillMaxWidth()
      .statusBarsPadding()
      .heightIn(min = 64.dp)
      .padding(horizontal = 22.dp)
      .padding(top = 8.dp),
  ) {
    Column(modifier = Modifier.weight(1f)) {
      Text("Email", style = DimoFont.display(24f, FontWeight.SemiBold), color = DimoColors.ink)
      Text(
        "Purchase and refund suggestions",
        style = DimoFont.body(12f),
        color = DimoColors.muted,
      )
    }
    if (store.hasFailedAnalyses) {
      IconSquareButton(
        icon = Icons.Filled.Refresh,
        contentDescription = if (store.isReanalyzing) {
          "Reanalysing failed emails"
        } else {
          "Reanalyse failed emails"
        },
        enabled = !store.isReanalyzing,
        onClick = store::reanalyzeAllEmails,
      )
    }
    IconSquareButton(
      icon = Icons.Filled.Settings,
      contentDescription = "Email accounts and analyzer settings",
      onClick = onOpenSettings,
    )
  }
}

@Composable
private fun IconSquareButton(
  icon: ImageVector,
  contentDescription: String,
  onClick: () -> Unit,
  enabled: Boolean = true,
) {
  Box(
    contentAlignment = Alignment.Center,
    modifier = Modifier
      .size(42.dp)
      .clip(RoundedCornerShape(13.dp))
      .background(DimoColors.surface)
      .border(1.dp, DimoColors.line, RoundedCornerShape(13.dp))
      .clickable(enabled = enabled, onClick = onClick),
  ) {
    Icon(
      imageVector = icon,
      contentDescription = contentDescription,
      tint = if (enabled) DimoColors.ink else DimoColors.disabled,
      modifier = Modifier.size(18.dp),
    )
  }
}

@Composable
private fun ConnectAccountCard(store: EmailFeatureStore) {
  Column(
    verticalArrangement = Arrangement.spacedBy(14.dp),
    modifier = Modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(20.dp))
      .background(DimoColors.surface)
      .border(1.dp, DimoColors.line, RoundedCornerShape(20.dp))
      .padding(20.dp),
  ) {
    Box(
      contentAlignment = Alignment.Center,
      modifier = Modifier
        .size(48.dp)
        .clip(RoundedCornerShape(15.dp))
        .background(DimoColors.greenSoft),
    ) {
      Icon(
        Icons.Filled.MailOutline,
        contentDescription = null,
        tint = DimoColors.green,
        modifier = Modifier.size(24.dp),
      )
      Box(
        modifier = Modifier
          .align(Alignment.TopEnd)
          .padding(top = 8.dp, end = 8.dp)
          .size(6.dp)
          .clip(CircleShape)
          .background(DimoColors.green),
      )
    }
    Text(
      "Find expenses in Gmail",
      style = DimoFont.display(20f, FontWeight.SemiBold),
      color = DimoColors.ink,
    )
    Text(
      "Connect one or more Gmail accounts. Dimo reads the latest " +
        "${store.syncWindow.title} directly on this device. Configure OpenRouter in " +
        "settings for analysis; analyzed suggestions sync through Dimo for restore.",
      style = DimoFont.body(14f),
      color = DimoColors.body,
    )
    ActionButton(
      title = "Connect Gmail",
      onClick = store::connectAccount,
      variant = ActionButtonVariant.Accent,
    )
    Text(
      "Read-only Gmail access. Gmail credentials stay on this device. You approve every " +
        "transaction change.",
      style = DimoFont.body(11f),
      color = DimoColors.muted,
      textAlign = TextAlign.Center,
      modifier = Modifier.fillMaxWidth(),
    )
  }
}

@Composable
private fun AccountAndAnalyzerStrip(store: EmailFeatureStore, onOpenSettings: () -> Unit) {
  Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
    LazyRow(
      horizontalArrangement = Arrangement.spacedBy(8.dp),
      modifier = Modifier.weight(1f),
    ) {
      items(store.accounts, key = { it.id }) { account ->
        val needsAttention = account.syncState == EmailUIAccountSyncState.FAILED ||
          account.syncState == EmailUIAccountSyncState.NEEDS_RECONNECT
        Row(
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.spacedBy(8.dp),
          modifier = Modifier
            .height(52.dp)
            .clip(RoundedCornerShape(13.dp))
            .background(DimoColors.surface)
            .border(1.dp, DimoColors.line, RoundedCornerShape(13.dp))
            .clickable(enabled = account.syncState != EmailUIAccountSyncState.SYNCING) {
              if (account.syncState == EmailUIAccountSyncState.NEEDS_RECONNECT) {
                store.reconnectAccount(account.id)
              } else {
                store.refreshAccount(account.id)
              }
            }
            .padding(horizontal = 10.dp),
        ) {
          Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
              .size(28.dp)
              .clip(RoundedCornerShape(9.dp))
              .background(
                if (needsAttention) DimoColors.dangerSoft else DimoColors.greenSoft,
              ),
          ) {
            if (account.syncState == EmailUIAccountSyncState.SYNCING) {
              CircularProgressIndicator(
                strokeWidth = 2.dp,
                color = DimoColors.green,
                modifier = Modifier.size(14.dp),
              )
            } else {
              Icon(
                Icons.Filled.Refresh,
                contentDescription = null,
                tint = if (needsAttention) DimoColors.danger else DimoColors.green,
                modifier = Modifier.size(14.dp),
              )
            }
          }
          Column(modifier = Modifier.widthIn(max = 168.dp)) {
            Text(
              account.emailAddress,
              style = DimoFont.body(11f, FontWeight.Medium),
              color = DimoColors.ink,
              maxLines = 1,
              overflow = TextOverflow.Ellipsis,
            )
            Text(
              account.statusDetail ?: account.syncState.title,
              style = DimoFont.body(10f),
              color = if (needsAttention) DimoColors.danger else DimoColors.muted,
              maxLines = 1,
              overflow = TextOverflow.Ellipsis,
            )
          }
        }
      }
    }

    Row(
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(8.dp),
      modifier = Modifier
        .weight(1f)
        .height(52.dp)
        .clip(RoundedCornerShape(13.dp))
        .background(DimoColors.surface)
        .border(1.dp, DimoColors.line, RoundedCornerShape(13.dp))
        .clickable(onClick = onOpenSettings)
        .padding(horizontal = 10.dp),
    ) {
      Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
          .size(28.dp)
          .clip(RoundedCornerShape(9.dp))
          .background(
            if (store.selectedProvider != null) DimoColors.greenSoft else DimoColors.canvasDeep,
          ),
      ) {
        Icon(
          Icons.Filled.Cloud,
          contentDescription = null,
          tint = if (store.selectedProvider != null) DimoColors.green else DimoColors.muted,
          modifier = Modifier.size(14.dp),
        )
      }
      Column(modifier = Modifier.weight(1f)) {
        Text(
          store.activeAnalyzerTitle,
          style = DimoFont.body(11f, FontWeight.SemiBold),
          color = DimoColors.ink,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
        )
        Text(
          store.analysisStatusDetail,
          style = DimoFont.body(10f),
          color = DimoColors.muted,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
        )
      }
    }
  }
}

@Composable
private fun EmailFilters(store: EmailFeatureStore) {
  LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
    items(EmailSuggestionFilter.entries.toList(), key = { it.name }) { filter ->
      val selected = store.selectedFilter == filter
      val count = filterCount(store, filter)
      Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier
          .height(38.dp)
          .clip(RoundedCornerShape(50))
          .background(if (selected) DimoColors.ink else DimoColors.surface)
          .then(
            if (selected) {
              Modifier
            } else {
              Modifier.border(1.dp, DimoColors.line, RoundedCornerShape(50))
            },
          )
          .clickable { store.setFilter(filter) }
          .padding(horizontal = 14.dp),
      ) {
        Text(
          filter.title,
          style = DimoFont.body(12f, FontWeight.Medium),
          color = if (selected) DimoColors.canvas else DimoColors.ink,
        )
        if (count > 0) {
          Text(
            count.toString(),
            style = DimoFont.body(10f, FontWeight.Bold),
            color = if (selected) DimoColors.canvas else DimoColors.ink,
            modifier = Modifier
              .clip(RoundedCornerShape(50))
              .background(
                if (selected) {
                  DimoColors.canvas.copy(alpha = 0.2f)
                } else {
                  DimoColors.canvasDeep
                },
              )
              .padding(horizontal = 5.dp, vertical = 2.dp),
          )
        }
      }
    }
  }
}

private fun filterCount(store: EmailFeatureStore, filter: EmailSuggestionFilter): Int =
  when (filter) {
    EmailSuggestionFilter.ALL -> store.allEmails.size
    EmailSuggestionFilter.PURCHASES -> store.pendingPurchaseCount
    EmailSuggestionFilter.REFUNDS -> store.suggestions.count {
      it.status == EmailUISuggestionStatus.PENDING_REFUND &&
        it.kind == EmailUISuggestionKind.REFUND
    }

    EmailSuggestionFilter.AWAITING_ANALYSIS -> store.allEmails.count {
      it.analysisState == EmailUIMessageAnalysisState.PENDING
    }

    EmailSuggestionFilter.ERRORS -> store.analysisErrorCount
    EmailSuggestionFilter.REVIEWED -> store.suggestions.count { it.status.isReviewed }
  }

@Composable
private fun EmailEmptyState(filter: EmailSuggestionFilter) {
  val (title, detail) = when (filter) {
    EmailSuggestionFilter.ALL -> "No scanned emails yet" to
      "Scanned messages and their local analysis status will appear here."

    EmailSuggestionFilter.PURCHASES -> "No purchase suggestions" to
      "Email scanning is best effort and is not real time. Tap an account above to refresh."

    EmailSuggestionFilter.REFUNDS -> "No refund suggestions" to
      "Email scanning is best effort and is not real time. Tap an account above to refresh."

    EmailSuggestionFilter.AWAITING_ANALYSIS -> "No emails awaiting analysis" to
      "Fetched emails waiting for analysis will appear here."

    EmailSuggestionFilter.ERRORS -> "No analysis errors" to
      "Emails that could not be analyzed will appear here with retry options."

    EmailSuggestionFilter.REVIEWED -> "Nothing reviewed yet" to
      "Suggestions you add, dismiss, or apply will appear here."
  }
  Column(
    horizontalAlignment = Alignment.CenterHorizontally,
    verticalArrangement = Arrangement.spacedBy(10.dp),
    modifier = Modifier
      .fillMaxWidth()
      .padding(horizontal = 24.dp, vertical = 44.dp),
  ) {
    Text(title, style = DimoFont.body(15f, FontWeight.SemiBold), color = DimoColors.ink)
    Text(
      detail,
      style = DimoFont.body(13f),
      color = DimoColors.muted,
      textAlign = TextAlign.Center,
    )
  }
}

@Composable
private fun PrivacyNote(store: EmailFeatureStore) {
  val text = when (store.selectedProvider) {
    EmailAnalysisProvider.OPEN_ROUTER -> when (store.openRouterAccessMode) {
      OpenRouterAccessMode.FREE_SHARED ->
        "Free-model analysis goes from this device through Dimo's servers to OpenRouter. " +
          "Analyzed suggestions and their email text then sync through Dimo so they restore " +
          "across your devices. You still approve every transaction change."

      OpenRouterAccessMode.BRING_YOUR_OWN_KEY ->
        "Analysis goes from this device to OpenRouter and the selected provider. Analyzed " +
          "suggestions and their email text then sync through Dimo so they restore across " +
          "your devices. You still approve every transaction change."
    }

    null ->
      "Gmail credentials and pending email content stay on this device until you configure " +
        "OpenRouter. Analyzed suggestions later sync through Dimo for restore."
  }
  Text(
    text = text,
    style = DimoFont.body(11f),
    color = DimoColors.muted,
    modifier = Modifier.padding(top = 4.dp),
  )
}
