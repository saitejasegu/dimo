package app.dimo.android.features.onboarding

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.TrackChanges
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.dimo.android.design.ActionButton
import app.dimo.android.design.ActionButtonVariant
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.domain.OnboardingCopy
import app.dimo.android.domain.OnboardingPage
import app.dimo.android.domain.OnboardingStore
import app.dimo.android.notifications.ExpenseReminderScheduler
import kotlinx.coroutines.launch

/**
 * First-run walkthrough shown ahead of SignInScreen. Port of
 * `ios-native/Dimo/Features/Onboarding/OnboardingFlow.swift`.
 */
@Composable
fun OnboardingFlow(
  onFinish: () -> Unit,
  modifier: Modifier = Modifier,
) {
  val context = LocalContext.current
  val pages = OnboardingCopy.allPages
  val pagerState = rememberPagerState(pageCount = { pages.size })
  val scope = rememberCoroutineScope()
  var isRequestingNotifications by remember { mutableStateOf(false) }
  val isLastPage = pagerState.currentPage >= pages.lastIndex

  val permissionLauncher = rememberLauncherForActivityResult(
    ActivityResultContracts.RequestPermission(),
  ) { granted ->
    isRequestingNotifications = false
    if (granted) {
      OnboardingStore.setPendingReminderOptIn(context)
    }
    onFinish()
  }

  fun enableReminders() {
    if (isRequestingNotifications) return
    isRequestingNotifications = true
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
      !ExpenseReminderScheduler.hasRuntimePermission(context)
    ) {
      permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
      return
    }
    // Pre-Tiramisu (or already granted): treat as opted-in when notifications
    // are not explicitly disabled at the system level.
    val authorized = ExpenseReminderScheduler.authorizationStatus(context) !=
      app.dimo.android.notifications.ExpenseReminderAuthorization.Denied
    if (authorized) {
      OnboardingStore.setPendingReminderOptIn(context)
    }
    isRequestingNotifications = false
    onFinish()
  }

  Column(
    modifier = modifier
      .fillMaxSize()
      .background(DimoColors.canvas)
      .statusBarsPadding(),
  ) {
    Row(
      modifier = Modifier
        .fillMaxWidth()
        .padding(horizontal = 22.dp)
        .height(44.dp),
      horizontalArrangement = Arrangement.End,
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Text(
        text = "Skip",
        style = DimoFont.body(15f, FontWeight.SemiBold),
        color = DimoColors.muted.copy(alpha = if (isLastPage) 0f else 1f),
        modifier = Modifier
          .clickable(enabled = !isLastPage) { onFinish() }
          .padding(horizontal = 4.dp, vertical = 8.dp),
      )
    }

    HorizontalPager(
      state = pagerState,
      modifier = Modifier
        .weight(1f)
        .fillMaxWidth(),
    ) { index ->
      OnboardingPageView(page = pages[index])
    }

    Row(
      modifier = Modifier
        .fillMaxWidth()
        .padding(top = 8.dp),
      horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      pages.indices.forEach { index ->
        val selected = index == pagerState.currentPage
        Box(
          modifier = Modifier
            .height(7.dp)
            .width(if (selected) 22.dp else 7.dp)
            .clip(RoundedCornerShape(50))
            .background(if (selected) DimoColors.green else DimoColors.lineSoft),
        )
      }
    }

    Column(
      modifier = Modifier
        .fillMaxWidth()
        .padding(horizontal = 24.dp)
        .padding(top = 28.dp, bottom = 24.dp),
      verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
      ActionButton(
        title = when {
          !isLastPage -> "Continue"
          isRequestingNotifications -> "Turning on…"
          else -> "Turn on reminders"
        },
        onClick = {
          if (isLastPage) {
            enableReminders()
          } else {
            scope.launch {
              pagerState.animateScrollToPage(pagerState.currentPage + 1)
            }
          }
        },
        variant = ActionButtonVariant.Accent,
        enabled = !isRequestingNotifications,
      )
      Text(
        text = "Not now",
        style = DimoFont.body(15f, FontWeight.SemiBold),
        color = DimoColors.muted.copy(alpha = if (isLastPage) 1f else 0f),
        textAlign = TextAlign.Center,
        modifier = Modifier
          .fillMaxWidth()
          .clickable(enabled = isLastPage && !isRequestingNotifications) { onFinish() }
          .padding(vertical = 10.dp),
      )
    }
  }
}

@Composable
private fun OnboardingPageView(page: OnboardingPage) {
  Column(
    modifier = Modifier
      .fillMaxSize()
      .padding(horizontal = 32.dp),
    verticalArrangement = Arrangement.Center,
    horizontalAlignment = Alignment.CenterHorizontally,
  ) {
    Box(
      modifier = Modifier
        .size(64.dp)
        .clip(RoundedCornerShape(16.dp))
        .background(DimoColors.greenSoft),
      contentAlignment = Alignment.Center,
    ) {
      Icon(
        imageVector = iconFor(page.iconKey),
        contentDescription = null,
        tint = DimoColors.green,
        modifier = Modifier.size(26.dp),
      )
    }
    Spacer(modifier = Modifier.height(24.dp))
    Text(
      text = page.title,
      style = DimoFont.display(26f, FontWeight.Bold),
      color = DimoColors.ink,
      textAlign = TextAlign.Center,
    )
    Spacer(modifier = Modifier.height(10.dp))
    Text(
      text = page.body,
      style = DimoFont.body(15f),
      color = DimoColors.body,
      textAlign = TextAlign.Center,
    )
  }
}

private fun iconFor(key: String): ImageVector = when (key) {
  "wallet" -> Icons.Filled.AccountBalanceWallet
  "home" -> Icons.Filled.Home
  "chart" -> Icons.Filled.BarChart
  "budget" -> Icons.Filled.TrackChanges
  "people" -> Icons.Filled.People
  "bell" -> Icons.Filled.Notifications
  else -> Icons.Filled.Home
}
