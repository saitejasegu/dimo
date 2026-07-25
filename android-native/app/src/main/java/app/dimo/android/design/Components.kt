package app.dimo.android.design

import android.graphics.BitmapFactory
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.dimo.android.data.model.PaymentMethodOption

/** Compose ports of `ios-native/Dimo/DesignSystem/Components/Components.swift`. */

@Composable
fun FabButton(
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
  contentDescription: String = "Add",
) {
  Box(
    modifier = modifier
      .size(58.dp)
      .shadow(12.dp, CircleShape, ambientColor = DimoColors.green.copy(alpha = 0.35f))
      .clip(CircleShape)
      .background(DimoColors.green)
      .clickable(onClick = onClick)
      .semantics { this.contentDescription = contentDescription },
    contentAlignment = Alignment.Center,
  ) {
    Icon(
      imageVector = Icons.Filled.Add,
      contentDescription = null,
      tint = DimoColors.onGreen,
      modifier = Modifier.size(22.dp),
    )
  }
}

@Composable
fun AvatarView(
  name: String,
  modifier: Modifier = Modifier,
  photoUrl: String? = null,
  photoBytes: ByteArray? = null,
  size: Dp = 40.dp,
  radius: Dp = 13.dp,
  fontSize: Float = 16f,
) {
  val shape = RoundedCornerShape(radius)
  val localBitmap = remember(photoBytes) {
    photoBytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() }
  }
  Box(
    modifier = modifier
      .size(size)
      .clip(shape)
      .background(DimoColors.greenSoft),
    contentAlignment = Alignment.Center,
  ) {
    Text(
      text = name.firstOrNull()?.uppercaseChar()?.toString().orEmpty(),
      style = DimoFont.display(fontSize, FontWeight.SemiBold),
      color = DimoColors.green,
    )
    if (localBitmap != null) {
      Image(
        bitmap = localBitmap,
        contentDescription = null,
        modifier = Modifier.matchParentSize(),
        contentScale = ContentScale.Crop,
      )
    }
    // Remote photoUrl loading is left to the full store / Coil wiring.
    @Suppress("UNUSED_VARIABLE")
    val unusedUrl = photoUrl
  }
}

@Composable
fun <T> PillDropdown(
  options: List<T>,
  selected: T,
  label: (T) -> String,
  onSelect: (T) -> Unit,
  modifier: Modifier = Modifier,
) {
  var expanded by remember { mutableStateOf(false) }
  Box(modifier = modifier) {
    Row(
      modifier = Modifier
        .widthIn(min = 112.dp)
        .height(36.dp)
        .clip(RoundedCornerShape(50))
        .background(DimoColors.surface)
        .border(1.dp, DimoColors.line, RoundedCornerShape(50))
        .clickable { expanded = true }
        .padding(horizontal = 14.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
      Text(
        text = label(selected),
        style = DimoFont.body(12f, FontWeight.SemiBold),
        color = DimoColors.ink,
      )
      Icon(
        imageVector = Icons.Filled.KeyboardArrowDown,
        contentDescription = null,
        tint = DimoColors.muted,
        modifier = Modifier.size(14.dp),
      )
    }
    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
      options.forEach { option ->
        DropdownMenuItem(
          text = {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
              if (option == selected) {
                Icon(Icons.Filled.Check, contentDescription = null, tint = DimoColors.green)
              }
              Text(label(option), style = DimoFont.body(14f), color = DimoColors.ink)
            }
          },
          onClick = {
            onSelect(option)
            expanded = false
          },
        )
      }
    }
  }
}

@Composable
fun PaymentMethodField(
  methods: List<PaymentMethodOption>,
  selectedId: String?,
  onSelect: (String?) -> Unit,
  modifier: Modifier = Modifier,
  onManage: (() -> Unit)? = null,
) {
  var isOpen by remember { mutableStateOf(false) }
  val selected = methods.firstOrNull { it.id == selectedId } ?: methods.firstOrNull()

  Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
    Text(
      text = "Paid with",
      style = DimoFont.body(12f),
      color = DimoColors.muted,
    )
    Row(
      modifier = Modifier
        .fillMaxWidth()
        .height(48.dp)
        .clip(RoundedCornerShape(12.dp))
        .background(DimoColors.canvas)
        .border(
          1.dp,
          if (isOpen) DimoColors.green else DimoColors.line,
          RoundedCornerShape(12.dp),
        )
        .clickable { isOpen = !isOpen }
        .padding(horizontal = 14.dp),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Text(
        text = selected?.label ?: "—",
        style = DimoFont.body(15f),
        color = DimoColors.ink,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier.weight(1f),
      )
      Icon(
        imageVector = Icons.Filled.KeyboardArrowDown,
        contentDescription = null,
        tint = DimoColors.muted,
        modifier = Modifier.rotate(if (isOpen) 180f else 0f),
      )
    }
    AnimatedVisibility(visible = isOpen) {
      Column(
        modifier = Modifier
          .fillMaxWidth()
          .shadow(8.dp, RoundedCornerShape(12.dp))
          .clip(RoundedCornerShape(12.dp))
          .background(DimoColors.popup)
          .border(1.dp, DimoColors.line, RoundedCornerShape(12.dp))
          .padding(8.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
      ) {
        methods.forEach { method ->
          val isSelected = method.id == selected?.id
          Row(
            modifier = Modifier
              .fillMaxWidth()
              .height(58.dp)
              .clip(RoundedCornerShape(10.dp))
              .background(if (isSelected) DimoColors.greenSoft else Color.Transparent)
              .clickable {
                onSelect(method.id)
                isOpen = false
              }
              .padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
          ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
              Text(
                text = method.name,
                style = DimoFont.body(
                  14f,
                  if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                ),
                color = if (isSelected) DimoColors.greenDeep else DimoColors.ink,
              )
              Text(
                text = listOf(method.type.wire, method.detail)
                  .filter { it.isNotEmpty() }
                  .joinToString(" · "),
                style = DimoFont.body(12f),
                color = DimoColors.muted,
              )
            }
            if (isSelected) {
              Icon(Icons.Filled.Check, contentDescription = null, tint = DimoColors.green)
            }
          }
        }
        if (onManage != null) {
          Spacer(
            modifier = Modifier
              .fillMaxWidth()
              .height(1.dp)
              .background(DimoColors.lineSoft),
          )
          Text(
            text = "Manage payment methods…",
            style = DimoFont.body(14f, FontWeight.Medium),
            color = DimoColors.green,
            modifier = Modifier
              .fillMaxWidth()
              .height(42.dp)
              .clickable {
                isOpen = false
                onManage()
              }
              .padding(horizontal = 14.dp),
          )
        }
      }
    }
  }
}

enum class StatusBadgeTone { Green, Muted }

@Composable
fun StatusBadge(
  label: String,
  modifier: Modifier = Modifier,
  tone: StatusBadgeTone = StatusBadgeTone.Muted,
) {
  Text(
    text = label,
    style = DimoFont.body(11f, FontWeight.Medium),
    color = if (tone == StatusBadgeTone.Green) DimoColors.green else DimoColors.muted,
    modifier = modifier
      .clip(RoundedCornerShape(50))
      .background(
        if (tone == StatusBadgeTone.Green) DimoColors.greenSoft else DimoColors.canvasDeep,
      )
      .padding(horizontal = 10.dp, vertical = 3.dp),
  )
}

enum class ActionButtonVariant { Accent, Secondary, Danger }

@Composable
fun ActionButton(
  title: String,
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
  variant: ActionButtonVariant = ActionButtonVariant.Secondary,
  enabled: Boolean = true,
) {
  val foreground = when {
    !enabled -> DimoColors.muted
    variant == ActionButtonVariant.Accent -> DimoColors.onGreen
    variant == ActionButtonVariant.Danger -> DimoColors.danger
    else -> DimoColors.ink
  }
  val background = when {
    !enabled -> DimoColors.canvasDeep
    variant == ActionButtonVariant.Accent -> DimoColors.green
    variant == ActionButtonVariant.Danger -> DimoColors.dangerSoft
    else -> DimoColors.canvas
  }
  val border = when {
    !enabled -> DimoColors.line
    variant == ActionButtonVariant.Accent -> Color.Transparent
    variant == ActionButtonVariant.Danger -> DimoColors.dangerLine
    else -> DimoColors.line
  }
  Text(
    text = title,
    style = DimoFont.body(15f, FontWeight.SemiBold),
    color = foreground,
    textAlign = TextAlign.Center,
    modifier = modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(12.dp))
      .background(background)
      .border(1.dp, border, RoundedCornerShape(12.dp))
      .clickable(enabled = enabled, onClick = onClick)
      .padding(vertical = 14.dp),
  )
}

@Composable
fun Chip(
  label: String,
  selected: Boolean,
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
) {
  Text(
    text = label,
    style = DimoFont.body(13f, FontWeight.Medium),
    color = if (selected) DimoColors.canvas else DimoColors.ink,
    modifier = modifier
      .clip(RoundedCornerShape(50))
      .background(if (selected) DimoColors.ink else DimoColors.surface)
      .then(
        if (selected) Modifier else Modifier.border(1.dp, DimoColors.line, RoundedCornerShape(50)),
      )
      .clickable(onClick = onClick)
      .padding(horizontal = 14.dp, vertical = 8.dp),
  )
}

@Composable
fun ToastView(
  message: String,
  modifier: Modifier = Modifier,
) {
  Text(
    text = message,
    style = DimoFont.body(14f, FontWeight.Medium),
    color = DimoColors.canvas,
    modifier = modifier
      .shadow(10.dp, RoundedCornerShape(50))
      .clip(RoundedCornerShape(50))
      .background(DimoColors.ink.copy(alpha = 0.92f))
      .padding(horizontal = 16.dp, vertical = 12.dp),
  )
}

@Composable
fun AmountKeypad(
  onPress: (String) -> Unit,
  modifier: Modifier = Modifier,
) {
  val keys = listOf(
    listOf("1", "2", "3"),
    listOf("4", "5", "6"),
    listOf("7", "8", "9"),
    listOf(".", "0", "⌫"),
  )
  Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(10.dp)) {
    keys.forEach { row ->
      Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
      ) {
        row.forEach { key ->
          Text(
            text = key,
            style = DimoFont.display(22f, FontWeight.Medium),
            color = DimoColors.ink,
            textAlign = TextAlign.Center,
            modifier = Modifier
              .weight(1f)
              .height(52.dp)
              .clip(RoundedCornerShape(14.dp))
              .background(DimoColors.canvasDeep)
              .clickable { onPress(key) }
              .padding(vertical = 12.dp),
          )
        }
      }
    }
  }
}

@Composable
fun ProgressBar(
  progress: Double,
  modifier: Modifier = Modifier,
  over: Boolean = false,
) {
  val clamped = progress.coerceIn(0.0, 1.0)
  Box(
    modifier = modifier
      .fillMaxWidth()
      .height(8.dp)
      .clip(RoundedCornerShape(50))
      .background(DimoColors.bar),
  ) {
    Box(
      modifier = Modifier
        .fillMaxWidth(clamped.toFloat().coerceAtLeast(0.02f))
        .height(8.dp)
        .clip(RoundedCornerShape(50))
        .background(if (over) DimoColors.danger else DimoColors.green),
    )
  }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SheetContainer(
  title: String,
  onClose: () -> Unit,
  modifier: Modifier = Modifier,
  content: @Composable () -> Unit,
) {
  val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
  val focusManager = LocalFocusManager.current
  ModalBottomSheet(
    onDismissRequest = {
      focusManager.clearFocus()
      onClose()
    },
    sheetState = sheetState,
    containerColor = DimoColors.surface,
    modifier = modifier,
  ) {
    Column(modifier = Modifier.fillMaxWidth()) {
      Text(
        text = title,
        style = DimoFont.display(18f, FontWeight.SemiBold),
        color = DimoColors.ink,
        textAlign = TextAlign.Center,
        modifier = Modifier
          .fillMaxWidth()
          .padding(top = 8.dp, bottom = 10.dp, start = 20.dp, end = 20.dp),
      )
      content()
    }
  }
}

@Composable
fun ToastOverlay(
  message: String?,
  modifier: Modifier = Modifier,
) {
  Box(modifier = modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
    AnimatedVisibility(
      visible = message != null,
      enter = fadeIn() + slideInVertically(),
      exit = fadeOut(),
    ) {
      if (message != null) {
        ToastView(message = message, modifier = Modifier.padding(top = 12.dp))
      }
    }
  }
}
