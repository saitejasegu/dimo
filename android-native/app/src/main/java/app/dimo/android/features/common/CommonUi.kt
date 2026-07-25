package app.dimo.android.features.common

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.Placeable
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.domain.DateHelpers
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Shared building blocks for the Compose feature screens. These are the Android
 * analogues of the small SwiftUI helpers that live next to the iOS screens
 * (`CategoryTintView`, `CardRowModifier`, `StatBarTrack`, section headers …).
 *
 * Anything reused by more than one screen belongs here rather than in
 * `design/Components.kt`, which stays a strict port of the iOS design system.
 */

// MARK: - Surfaces

@Composable
fun Modifier.cardSurface(
  radius: Dp = 14.dp,
  background: Color = DimoColors.surface,
  borderColor: Color = DimoColors.line,
): Modifier = this
  .clip(RoundedCornerShape(radius))
  .background(background)
  .border(1.dp, borderColor, RoundedCornerShape(radius))

@Composable
fun DimoCard(
  modifier: Modifier = Modifier,
  radius: Dp = 16.dp,
  padding: Dp = 16.dp,
  verticalSpacing: Dp = 12.dp,
  content: @Composable ColumnScope.() -> Unit,
) {
  Column(
    modifier = modifier
      .fillMaxWidth()
      .cardSurface(radius)
      .padding(padding),
    verticalArrangement = Arrangement.spacedBy(verticalSpacing),
    content = content,
  )
}

/** Dark "hero" block used at the top of Home, Stats, Budgets and Lending. */
@Composable
fun HeroCard(
  modifier: Modifier = Modifier,
  content: @Composable ColumnScope.() -> Unit,
) {
  Column(
    modifier = modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(20.dp))
      .background(DimoColors.inverse)
      .padding(horizontal = 22.dp, vertical = 20.dp),
    verticalArrangement = Arrangement.spacedBy(6.dp),
    content = content,
  )
}

@Composable
fun HeroLabel(text: String, modifier: Modifier = Modifier) {
  Text(
    text = text.uppercase(Locale.getDefault()),
    style = DimoFont.body(11f, FontWeight.Medium).copy(letterSpacing = 0.9.sp),
    color = DimoColors.sideMuted,
    modifier = modifier,
  )
}

@Composable
fun HeroAmount(text: String, modifier: Modifier = Modifier, size: Float = 34f) {
  Text(
    text = text,
    style = DimoFont.display(size, FontWeight.Bold),
    color = DimoColors.sideText,
    modifier = modifier,
  )
}

@Composable
fun HeroCaption(text: String, modifier: Modifier = Modifier) {
  Text(
    text = text,
    style = DimoFont.body(13f),
    color = DimoColors.sideSub,
    modifier = modifier,
  )
}

// MARK: - Text

@Composable
fun SectionLabel(text: String, modifier: Modifier = Modifier) {
  Text(
    text = text.uppercase(Locale.getDefault()),
    style = DimoFont.body(11f, FontWeight.Medium).copy(letterSpacing = 0.9.sp),
    color = DimoColors.muted,
    modifier = modifier,
  )
}

@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier) {
  Text(
    text = text,
    style = DimoFont.display(16f, FontWeight.SemiBold),
    color = DimoColors.ink,
    modifier = modifier,
  )
}

@Composable
fun FieldLabel(text: String, modifier: Modifier = Modifier) {
  Text(
    text = text,
    style = DimoFont.body(12f),
    color = DimoColors.muted,
    modifier = modifier,
  )
}

@Composable
fun EmptyState(
  title: String,
  message: String? = null,
  modifier: Modifier = Modifier,
) {
  Column(
    modifier = modifier
      .fillMaxWidth()
      .padding(vertical = 32.dp),
    horizontalAlignment = Alignment.CenterHorizontally,
    verticalArrangement = Arrangement.spacedBy(6.dp),
  ) {
    Text(
      text = title,
      style = DimoFont.body(15f, FontWeight.Medium),
      color = DimoColors.ink,
      textAlign = TextAlign.Center,
    )
    if (message != null) {
      Text(
        text = message,
        style = DimoFont.body(13f),
        color = DimoColors.muted,
        textAlign = TextAlign.Center,
      )
    }
  }
}

/** Non-blocking sync failure banner. Shown wherever `syncMeta.error` is set. */
@Composable
fun SyncErrorBanner(message: String?, modifier: Modifier = Modifier) {
  if (message.isNullOrBlank()) return
  Column(
    modifier = modifier
      .fillMaxWidth()
      .cardSurface(12.dp, DimoColors.dangerSoft, DimoColors.dangerLine)
      .padding(horizontal = 14.dp, vertical = 12.dp),
    verticalArrangement = Arrangement.spacedBy(3.dp),
  ) {
    Text(
      text = "Sync problem",
      style = DimoFont.body(13f, FontWeight.SemiBold),
      color = DimoColors.danger,
    )
    Text(text = message, style = DimoFont.body(12f), color = DimoColors.danger)
  }
}

// MARK: - Rows and bars

/** Rounded emoji tile in front of a transaction / bill / category row. */
@Composable
fun CategoryTintView(
  emoji: String,
  green: Boolean?,
  modifier: Modifier = Modifier,
  size: Dp = 38.dp,
  radius: Dp = 11.dp,
  fontSize: Float = 17f,
) {
  Box(
    modifier = modifier
      .size(size)
      .clip(RoundedCornerShape(radius))
      .background(if (green == true) DimoColors.greenSoft else DimoColors.canvasDeep),
    contentAlignment = Alignment.Center,
  ) {
    Text(text = emoji, style = DimoFont.body(fontSize))
  }
}

/** Thin horizontal meter used by the stats category / merchant lists. */
@Composable
fun StatBarTrack(
  relative: Int,
  modifier: Modifier = Modifier,
  primary: Boolean = false,
  height: Dp = 6.dp,
) {
  Box(
    modifier = modifier
      .fillMaxWidth()
      .height(height)
      .clip(RoundedCornerShape(50))
      .background(DimoColors.bar),
  ) {
    Box(
      modifier = Modifier
        .fillMaxWidth((relative.coerceIn(0, 100)) / 100f)
        .fillMaxHeight()
        .clip(RoundedCornerShape(50))
        .background(if (primary) DimoColors.green else DimoColors.barSoft),
    )
  }
}

@Composable
fun DimoDivider(modifier: Modifier = Modifier) {
  Spacer(
    modifier = modifier
      .fillMaxWidth()
      .height(1.dp)
      .background(DimoColors.lineSoft),
  )
}

/** Settings-style row: label on the left, muted value plus optional tap target. */
@Composable
fun SettingsRow(
  label: String,
  modifier: Modifier = Modifier,
  value: String? = null,
  destructive: Boolean = false,
  enabled: Boolean = true,
  onClick: (() -> Unit)? = null,
  trailing: @Composable (RowScope.() -> Unit)? = null,
) {
  Row(
    modifier = modifier
      .fillMaxWidth()
      .heightIn(min = 46.dp)
      .then(
        if (onClick != null && enabled) Modifier.clickable(onClick = onClick) else Modifier,
      ),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    Text(
      text = label,
      style = DimoFont.body(15f, FontWeight.Medium),
      color = when {
        !enabled -> DimoColors.disabled
        destructive -> DimoColors.danger
        else -> DimoColors.ink
      },
      modifier = Modifier.weight(1f),
    )
    if (value != null) {
      Text(
        text = value,
        style = DimoFont.body(14f),
        color = DimoColors.muted,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
    }
    if (trailing != null) trailing()
  }
}

@Composable
fun SettingsToggleRow(
  label: String,
  checked: Boolean,
  onCheckedChange: (Boolean) -> Unit,
  modifier: Modifier = Modifier,
  caption: String? = null,
) {
  Row(
    modifier = modifier.fillMaxWidth().heightIn(min = 46.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
      Text(
        text = label,
        style = DimoFont.body(15f, FontWeight.Medium),
        color = DimoColors.ink,
      )
      if (caption != null) {
        Text(text = caption, style = DimoFont.body(12f), color = DimoColors.muted)
      }
    }
    Switch(
      checked = checked,
      onCheckedChange = onCheckedChange,
      colors = SwitchDefaults.colors(
        checkedThumbColor = DimoColors.onGreen,
        checkedTrackColor = DimoColors.green,
        checkedBorderColor = DimoColors.green,
        uncheckedThumbColor = DimoColors.surface,
        uncheckedTrackColor = DimoColors.toggleOff,
        uncheckedBorderColor = DimoColors.toggleOff,
      ),
    )
  }
}

// MARK: - Controls

@Composable
fun <T> SegmentedControl(
  options: List<T>,
  selected: T,
  label: (T) -> String,
  onSelect: (T) -> Unit,
  modifier: Modifier = Modifier,
) {
  Row(
    modifier = modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(12.dp))
      .background(DimoColors.canvasDeep)
      .padding(3.dp),
    horizontalArrangement = Arrangement.spacedBy(3.dp),
  ) {
    options.forEach { option ->
      val isSelected = option == selected
      Text(
        text = label(option),
        style = DimoFont.body(13f, if (isSelected) FontWeight.SemiBold else FontWeight.Medium),
        color = if (isSelected) DimoColors.ink else DimoColors.muted,
        textAlign = TextAlign.Center,
        maxLines = 1,
        modifier = Modifier
          .weight(1f)
          .clip(RoundedCornerShape(10.dp))
          .background(if (isSelected) DimoColors.surface else Color.Transparent)
          .clickable { onSelect(option) }
          .padding(vertical = 9.dp),
      )
    }
  }
}

@Composable
fun PrimaryButton(
  title: String,
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
  enabled: Boolean = true,
) {
  Text(
    text = title,
    style = DimoFont.display(16f, FontWeight.SemiBold),
    color = if (enabled) DimoColors.onGreen else DimoColors.muted,
    textAlign = TextAlign.Center,
    modifier = modifier
      .fillMaxWidth()
      .height(52.dp)
      .clip(RoundedCornerShape(14.dp))
      .background(if (enabled) DimoColors.green else DimoColors.canvasDeep)
      .clickable(enabled = enabled, onClick = onClick)
      .padding(vertical = 15.dp),
  )
}

@Composable
fun BackButton(onClick: () -> Unit, modifier: Modifier = Modifier) {
  Box(
    modifier = modifier
      .size(38.dp)
      .clip(RoundedCornerShape(12.dp))
      .background(DimoColors.surface)
      .border(1.dp, DimoColors.line, RoundedCornerShape(12.dp))
      .clickable(onClick = onClick),
    contentAlignment = Alignment.Center,
  ) {
    Icon(
      imageVector = Icons.AutoMirrored.Filled.ArrowBack,
      contentDescription = "Back",
      tint = DimoColors.ink,
      modifier = Modifier.size(18.dp),
    )
  }
}

@Composable
fun DangerIconButton(
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
  contentDescription: String = "Delete",
) {
  Box(
    modifier = modifier
      .size(36.dp)
      .clip(RoundedCornerShape(11.dp))
      .background(DimoColors.dangerSoft)
      .border(1.dp, DimoColors.dangerLine, RoundedCornerShape(11.dp))
      .clickable(onClick = onClick),
    contentAlignment = Alignment.Center,
  ) {
    Icon(
      imageVector = Icons.Filled.DeleteOutline,
      contentDescription = contentDescription,
      tint = DimoColors.danger,
      modifier = Modifier.size(18.dp),
    )
  }
}

/** Screen title bar with an optional back affordance and trailing accessories. */
@Composable
fun ScreenHeader(
  title: String,
  modifier: Modifier = Modifier,
  subtitle: String? = null,
  onBack: (() -> Unit)? = null,
  trailing: @Composable (RowScope.() -> Unit)? = null,
) {
  Row(
    modifier = modifier.fillMaxWidth(),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    if (onBack != null) BackButton(onClick = onBack)
    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
      Text(
        text = title,
        style = DimoFont.display(22f, FontWeight.Bold),
        color = DimoColors.ink,
      )
      if (subtitle != null) {
        Text(text = subtitle, style = DimoFont.body(13f), color = DimoColors.muted)
      }
    }
    if (trailing != null) trailing()
  }
}

@Composable
fun DimoTextField(
  value: String,
  onValueChange: (String) -> Unit,
  modifier: Modifier = Modifier,
  placeholder: String = "",
  keyboardType: KeyboardType = KeyboardType.Text,
  imeAction: ImeAction = ImeAction.Done,
  singleLine: Boolean = true,
  height: Dp = 50.dp,
  textStyle: TextStyle? = null,
  textAlign: TextAlign = TextAlign.Start,
  enabled: Boolean = true,
  leading: @Composable (() -> Unit)? = null,
  trailing: @Composable (() -> Unit)? = null,
) {
  val resolvedStyle = (textStyle ?: DimoFont.body(15f)).copy(
    color = if (enabled) DimoColors.ink else DimoColors.muted,
    textAlign = textAlign,
  )
  BasicTextField(
    value = value,
    onValueChange = onValueChange,
    enabled = enabled,
    singleLine = singleLine,
    textStyle = resolvedStyle,
    cursorBrush = SolidColor(DimoColors.green),
    keyboardOptions = KeyboardOptions(keyboardType = keyboardType, imeAction = imeAction),
    modifier = modifier
      .fillMaxWidth()
      .heightIn(min = height),
    decorationBox = { innerTextField ->
      Row(
        modifier = Modifier
          .fillMaxWidth()
          .heightIn(min = height)
          .cardSurface(12.dp, DimoColors.canvas)
          .padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
      ) {
        if (leading != null) leading()
        Box(modifier = Modifier.weight(1f)) {
          if (value.isEmpty() && placeholder.isNotEmpty()) {
            Text(
              text = placeholder,
              style = resolvedStyle.copy(color = DimoColors.faint),
              maxLines = 1,
              overflow = TextOverflow.Ellipsis,
              modifier = Modifier.fillMaxWidth(),
            )
          }
          innerTextField()
        }
        if (trailing != null) trailing()
      }
    },
  )
}

/** Labelled text field, the shape used by every editor sheet. */
@Composable
fun LabeledTextField(
  label: String,
  value: String,
  onValueChange: (String) -> Unit,
  modifier: Modifier = Modifier,
  placeholder: String = "",
  keyboardType: KeyboardType = KeyboardType.Text,
  imeAction: ImeAction = ImeAction.Done,
  enabled: Boolean = true,
  trailing: @Composable (() -> Unit)? = null,
) {
  Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
    FieldLabel(label)
    DimoTextField(
      value = value,
      onValueChange = onValueChange,
      placeholder = placeholder,
      keyboardType = keyboardType,
      imeAction = imeAction,
      enabled = enabled,
      trailing = trailing,
    )
  }
}

/** Generic labelled dropdown used for categories, currencies and frequencies. */
@Composable
fun <T> LabeledDropdown(
  label: String,
  options: List<T>,
  selected: T?,
  optionLabel: (T) -> String,
  onSelect: (T) -> Unit,
  modifier: Modifier = Modifier,
  placeholder: String = "Select",
) {
  var expanded by remember { mutableStateOf(false) }
  Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
    if (label.isNotEmpty()) FieldLabel(label)
    Row(
      modifier = Modifier
        .fillMaxWidth()
        .height(50.dp)
        .cardSurface(12.dp, DimoColors.canvas, if (expanded) DimoColors.green else DimoColors.line)
        .clickable { expanded = !expanded }
        .padding(horizontal = 14.dp),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Text(
        text = selected?.let(optionLabel) ?: placeholder,
        style = DimoFont.body(15f),
        color = if (selected == null) DimoColors.faint else DimoColors.ink,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier.weight(1f),
      )
      Icon(
        imageVector = Icons.Filled.KeyboardArrowDown,
        contentDescription = null,
        tint = DimoColors.muted,
        modifier = Modifier
          .size(18.dp)
          .rotate(if (expanded) 180f else 0f),
      )
    }
    if (expanded) {
      Column(
        modifier = Modifier
          .fillMaxWidth()
          .cardSurface(12.dp, DimoColors.popup)
          .padding(6.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp),
      ) {
        options.forEach { option ->
          val isSelected = option == selected
          Row(
            modifier = Modifier
              .fillMaxWidth()
              .height(44.dp)
              .clip(RoundedCornerShape(10.dp))
              .background(if (isSelected) DimoColors.greenSoft else Color.Transparent)
              .clickable {
                onSelect(option)
                expanded = false
              }
              .padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
          ) {
            Text(
              text = optionLabel(option),
              style = DimoFont.body(14f, if (isSelected) FontWeight.SemiBold else FontWeight.Normal),
              color = if (isSelected) DimoColors.greenDeep else DimoColors.ink,
              maxLines = 1,
              overflow = TextOverflow.Ellipsis,
              modifier = Modifier.weight(1f),
            )
            if (isSelected) {
              Icon(
                imageVector = Icons.Filled.Check,
                contentDescription = null,
                tint = DimoColors.green,
                modifier = Modifier.size(16.dp),
              )
            }
          }
        }
      }
    }
  }
}

// MARK: - Wrapping row

/**
 * Minimal flow layout so chip groups wrap without depending on the experimental
 * `FlowRow` overloads, which move between Compose releases.
 */
@Composable
fun WrapRow(
  modifier: Modifier = Modifier,
  horizontalSpacing: Dp = 8.dp,
  verticalSpacing: Dp = 8.dp,
  content: @Composable () -> Unit,
) {
  Layout(modifier = modifier, content = content) { measurables, constraints ->
    val hGap = horizontalSpacing.roundToPx()
    val vGap = verticalSpacing.roundToPx()
    val maxRowWidth = if (constraints.maxWidth == Constraints.Infinity) {
      Int.MAX_VALUE
    } else {
      constraints.maxWidth
    }
    val childConstraints = constraints.copy(minWidth = 0, minHeight = 0)
    val rows = mutableListOf<MutableList<Placeable>>()
    var currentRow = mutableListOf<Placeable>()
    var currentWidth = 0
    measurables.forEach { measurable ->
      val placeable = measurable.measure(childConstraints)
      val addedWidth = if (currentRow.isEmpty()) placeable.width else placeable.width + hGap
      if (currentRow.isNotEmpty() && currentWidth + addedWidth > maxRowWidth) {
        rows.add(currentRow)
        currentRow = mutableListOf()
        currentWidth = 0
      }
      currentWidth += if (currentRow.isEmpty()) placeable.width else placeable.width + hGap
      currentRow.add(placeable)
    }
    if (currentRow.isNotEmpty()) rows.add(currentRow)

    val width = if (constraints.maxWidth == Constraints.Infinity) {
      rows.maxOfOrNull { row -> row.sumOf { it.width } + hGap * (row.size - 1) } ?: 0
    } else {
      constraints.maxWidth
    }
    val height = rows.sumOf { row -> row.maxOf { it.height } } +
      vGap * (rows.size - 1).coerceAtLeast(0)

    layout(width, height.coerceAtLeast(0)) {
      var y = 0
      rows.forEach { row ->
        var x = 0
        row.forEach { placeable ->
          placeable.placeRelative(x, y)
          x += placeable.width + hGap
        }
        y += row.maxOf { it.height } + vGap
      }
    }
  }
}

// MARK: - Sheets and dialogs

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DimoBottomSheet(
  onDismiss: () -> Unit,
  modifier: Modifier = Modifier,
  content: @Composable ColumnScope.() -> Unit,
) {
  val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
  ModalBottomSheet(
    onDismissRequest = onDismiss,
    sheetState = sheetState,
    containerColor = DimoColors.surface,
    contentColor = DimoColors.ink,
    dragHandle = { BottomSheetDefaults.DragHandle(color = DimoColors.line) },
    modifier = modifier,
  ) {
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .imePadding(),
      content = content,
    )
  }
}

@Composable
fun SheetHeader(
  title: String,
  modifier: Modifier = Modifier,
  onDelete: (() -> Unit)? = null,
) {
  Box(
    modifier = modifier
      .fillMaxWidth()
      .padding(horizontal = 20.dp)
      .padding(bottom = 6.dp),
    contentAlignment = Alignment.Center,
  ) {
    Text(
      text = title,
      style = DimoFont.display(18f, FontWeight.SemiBold),
      color = DimoColors.ink,
      textAlign = TextAlign.Center,
    )
    if (onDelete != null) {
      DangerIconButton(
        onClick = onDelete,
        modifier = Modifier.align(Alignment.CenterEnd),
      )
    }
  }
}

@Composable
fun ConfirmDialog(
  title: String,
  confirmLabel: String,
  onConfirm: () -> Unit,
  onDismiss: () -> Unit,
  message: String? = null,
  destructive: Boolean = true,
) {
  AlertDialog(
    onDismissRequest = onDismiss,
    containerColor = DimoColors.surface,
    titleContentColor = DimoColors.ink,
    textContentColor = DimoColors.body,
    title = {
      Text(text = title, style = DimoFont.display(18f, FontWeight.SemiBold), color = DimoColors.ink)
    },
    text = if (message == null) {
      null
    } else {
      { Text(text = message, style = DimoFont.body(14f), color = DimoColors.body) }
    },
    confirmButton = {
      TextButton(
        onClick = {
          onDismiss()
          onConfirm()
        },
      ) {
        Text(
          text = confirmLabel,
          style = DimoFont.body(15f, FontWeight.SemiBold),
          color = if (destructive) DimoColors.danger else DimoColors.green,
        )
      }
    },
    dismissButton = {
      TextButton(onClick = onDismiss) {
        Text(text = "Cancel", style = DimoFont.body(15f), color = DimoColors.muted)
      }
    },
  )
}

// MARK: - Date pickers

@OptIn(ExperimentalMaterial3Api::class)
private object PastOrPresentSelectableDates : SelectableDates {
  override fun isSelectableDate(utcTimeMillis: Long): Boolean =
    !utcMillisToLocalDate(utcTimeMillis).isAfter(LocalDate.now(DateHelpers.zone()))

  override fun isSelectableYear(year: Int): Boolean =
    year <= LocalDate.now(DateHelpers.zone()).year
}

private fun utcMillisToLocalDate(millis: Long): LocalDate =
  Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate()

private fun localDateToUtcMillis(date: LocalDate): Long =
  date.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()

/**
 * Date (and optionally time) field. Values are epoch millis in the device zone;
 * `maxToday` mirrors the iOS pickers which never allow future expenses.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DateField(
  label: String,
  millis: Long,
  onChange: (Long) -> Unit,
  modifier: Modifier = Modifier,
  includeTime: Boolean = false,
  maxToday: Boolean = true,
) {
  var showDate by remember { mutableStateOf(false) }
  var showTime by remember { mutableStateOf(false) }
  val zone = DateHelpers.zone()
  val zoned = remember(millis) { Instant.ofEpochMilli(millis).atZone(zone) }
  val text = remember(millis, includeTime) {
    val pattern = if (includeTime) "EEE, d MMM yyyy · h:mm a" else "EEE, d MMM yyyy"
    zoned.format(DateTimeFormatter.ofPattern(pattern, Locale.getDefault()))
  }

  Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
    if (label.isNotEmpty()) FieldLabel(label)
    Row(
      modifier = Modifier
        .fillMaxWidth()
        .height(50.dp)
        .cardSurface(12.dp, DimoColors.canvas)
        .clickable { showDate = true }
        .padding(horizontal = 14.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
      Icon(
        imageVector = Icons.Filled.CalendarToday,
        contentDescription = null,
        tint = DimoColors.muted,
        modifier = Modifier.size(16.dp),
      )
      Text(
        text = text,
        style = DimoFont.body(15f),
        color = DimoColors.ink,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
    }
  }

  if (showDate) {
    val state = rememberDatePickerState(
      initialSelectedDateMillis = localDateToUtcMillis(zoned.toLocalDate()),
      selectableDates = if (maxToday) PastOrPresentSelectableDates else DatePickerDefaults.AllDates,
    )
    DatePickerDialog(
      onDismissRequest = { showDate = false },
      colors = DatePickerDefaults.colors(containerColor = DimoColors.surface),
      confirmButton = {
        TextButton(
          onClick = {
            val picked = state.selectedDateMillis
            showDate = false
            if (picked != null) {
              val date = utcMillisToLocalDate(picked)
              var next = date
                .atTime(zoned.toLocalTime())
                .atZone(zone)
                .toInstant()
                .toEpochMilli()
              if (maxToday) next = minOf(next, System.currentTimeMillis())
              onChange(next)
              if (includeTime) showTime = true
            }
          },
        ) {
          Text(text = "Done", style = DimoFont.body(15f, FontWeight.SemiBold), color = DimoColors.green)
        }
      },
      dismissButton = {
        TextButton(onClick = { showDate = false }) {
          Text(text = "Cancel", style = DimoFont.body(15f), color = DimoColors.muted)
        }
      },
    ) {
      DatePicker(state = state, title = null, headline = null, showModeToggle = false)
    }
  }

  if (showTime) {
    val timeState = rememberTimePickerState(
      initialHour = zoned.hour,
      initialMinute = zoned.minute,
      is24Hour = false,
    )
    AlertDialog(
      onDismissRequest = { showTime = false },
      containerColor = DimoColors.surface,
      title = {
        Text(
          text = "Time",
          style = DimoFont.display(18f, FontWeight.SemiBold),
          color = DimoColors.ink,
        )
      },
      text = {
        Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
          TimePicker(state = timeState)
        }
      },
      confirmButton = {
        TextButton(
          onClick = {
            showTime = false
            var next = Instant.ofEpochMilli(millis)
              .atZone(zone)
              .toLocalDate()
              .atTime(timeState.hour, timeState.minute)
              .atZone(zone)
              .toInstant()
              .toEpochMilli()
            if (maxToday) next = minOf(next, System.currentTimeMillis())
            onChange(next)
          },
        ) {
          Text(text = "Done", style = DimoFont.body(15f, FontWeight.SemiBold), color = DimoColors.green)
        }
      },
      dismissButton = {
        TextButton(onClick = { showTime = false }) {
          Text(text = "Cancel", style = DimoFont.body(15f), color = DimoColors.muted)
        }
      },
    )
  }
}

/** Optional day picker (used by the Home filter sheet's start / end fields). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OptionalDateField(
  label: String,
  date: LocalDate?,
  onChange: (LocalDate?) -> Unit,
  modifier: Modifier = Modifier,
) {
  var showDate by remember { mutableStateOf(false) }
  Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
    FieldLabel(label)
    Row(
      modifier = Modifier
        .fillMaxWidth()
        .height(46.dp)
        .cardSurface(12.dp, DimoColors.canvas)
        .clickable { showDate = true }
        .padding(horizontal = 12.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
      Text(
        text = date?.format(DateTimeFormatter.ofPattern("d MMM yyyy", Locale.getDefault()))
          ?: "Any",
        style = DimoFont.body(14f),
        color = if (date == null) DimoColors.faint else DimoColors.ink,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier.weight(1f),
      )
      if (date != null) {
        Text(
          text = "Clear",
          style = DimoFont.body(12f, FontWeight.Medium),
          color = DimoColors.green,
          modifier = Modifier.clickable { onChange(null) },
        )
      }
    }
  }

  if (showDate) {
    val state = rememberDatePickerState(
      initialSelectedDateMillis = localDateToUtcMillis(date ?: LocalDate.now(DateHelpers.zone())),
    )
    DatePickerDialog(
      onDismissRequest = { showDate = false },
      colors = DatePickerDefaults.colors(containerColor = DimoColors.surface),
      confirmButton = {
        TextButton(
          onClick = {
            val picked = state.selectedDateMillis
            showDate = false
            if (picked != null) onChange(utcMillisToLocalDate(picked))
          },
        ) {
          Text(text = "Done", style = DimoFont.body(15f, FontWeight.SemiBold), color = DimoColors.green)
        }
      },
      dismissButton = {
        TextButton(onClick = { showDate = false }) {
          Text(text = "Cancel", style = DimoFont.body(15f), color = DimoColors.muted)
        }
      },
    ) {
      DatePicker(state = state, title = null, headline = null, showModeToggle = false)
    }
  }
}