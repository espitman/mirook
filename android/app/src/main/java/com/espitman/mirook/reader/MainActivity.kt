package com.espitman.mirook.reader

import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Book
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.fontResource
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.espitman.mirook.reader.domain.EpubBlock
import com.espitman.mirook.reader.domain.ReaderMode
import com.espitman.mirook.reader.domain.RecentBook
import com.espitman.mirook.reader.presentation.ReaderUiState
import com.espitman.mirook.reader.presentation.ReaderViewModel

class MainActivity : ComponentActivity() {
    private val readerViewModel by viewModels<ReaderViewModel>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        readerViewModel.openFromIntent(intent)
        setContent {
            MirookReaderApp(readerViewModel)
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readerViewModel.openFromIntent(intent)
    }
}

@Composable
private fun MirookReaderApp(viewModel: ReaderViewModel = viewModel()) {
    val state by viewModel.state
    val openLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri != null) viewModel.open(uri)
    }

    MirookTheme {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = MirookColors.background
        ) {
            if (state.book == null) {
                HomeScreen(
                    state = state,
                    onOpen = { openLauncher.launch(arrayOf("*/*")) },
                    onRecent = viewModel::openRecent
                )
            } else {
                ReaderScreen(
                    state = state,
                    onOpen = { openLauncher.launch(arrayOf("*/*")) },
                    onMode = viewModel::setMode,
                    onPrevious = viewModel::previousPage,
                    onNext = viewModel::nextPage,
                    onFontDelta = viewModel::adjustFontSize
                )
            }

            if (state.isLoading) {
                LoadingOverlay()
            }

            state.pendingPasswordUri?.let {
                PasswordDialog(
                    onDismiss = viewModel::dismissPassword,
                    onSubmit = viewModel::submitPassword
                )
            }

            state.errorMessage?.let { message ->
                AlertDialog(
                    onDismissRequest = viewModel::clearError,
                    confirmButton = {
                        TextButton(onClick = viewModel::clearError) { Text("OK") }
                    },
                    title = { Text("Could not open book") },
                    text = { Text(message) }
                )
            }
        }
    }
}

@Composable
private fun HomeScreen(
    state: ReaderUiState,
    onOpen: () -> Unit,
    onRecent: (RecentBook) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(22.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        BrandHeader()

        Button(
            onClick = onOpen,
            modifier = Modifier
                .fillMaxWidth()
                .height(56.dp),
            colors = ButtonDefaults.buttonColors(containerColor = MirookColors.ink),
            shape = RoundedCornerShape(9.dp)
        ) {
            Icon(Icons.Rounded.Add, contentDescription = null)
            Spacer(Modifier.width(8.dp))
            Text("Open MRBK", fontWeight = FontWeight.Bold)
        }

        MirookPanel(backgroundColor = MirookColors.paper) {
            HomeRow("Library", "Books stored locally", "›")
            DividerLine()
            HomeRow("Recents", "${state.recents.size} books", "›")
        }

        Text(
            "Recent Books",
            style = MaterialTheme.typography.labelLarge,
            color = MirookColors.muted
        )

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            state.recents.forEach { recent ->
                RecentBookRow(recent, onClick = { onRecent(recent) })
            }
            if (state.recents.isEmpty()) {
                Text(
                    "Open a Mirook Book to start reading.",
                    color = MirookColors.muted,
                    modifier = Modifier.padding(top = 12.dp)
                )
            }
        }
    }
}

@Composable
private fun ReaderScreen(
    state: ReaderUiState,
    onOpen: () -> Unit,
    onMode: (ReaderMode) -> Unit,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    onFontDelta: (Int) -> Unit
) {
    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        val isWide = maxWidth >= 720.dp
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
        ) {
            ReaderTopBar(state, onOpen = onOpen, onFontDelta = onFontDelta)

            if (isWide && state.mode == ReaderMode.Split) {
                SplitContent(state, Modifier.weight(1f))
            } else {
                SingleContent(state, Modifier.weight(1f))
            }

            ReaderBottomBar(
                state = state,
                showSplit = isWide,
                onMode = onMode,
                onPrevious = onPrevious,
                onNext = onNext
            )
        }
    }
}

@Composable
private fun ReaderTopBar(
    state: ReaderUiState,
    onOpen: () -> Unit,
    onFontDelta: (Int) -> Unit
) {
    Column {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(58.dp)
                .padding(horizontal = 18.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                painter = painterResource(R.drawable.ic_mirook_mark),
                contentDescription = null,
                modifier = Modifier.size(34.dp),
                tint = MirookColors.ink
            )
            Spacer(Modifier.width(8.dp))
            Text("Mirook", fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.weight(1f))
            TextButton(onClick = { onFontDelta(-1) }) { Text("A-") }
            Text("${state.fontSize}", color = MirookColors.muted)
            TextButton(onClick = { onFontDelta(1) }) { Text("A+") }
            IconButton(onClick = onOpen) {
                Icon(Icons.Rounded.Book, contentDescription = "Open book")
            }
            IconButton(onClick = {}) {
                Icon(Icons.Rounded.Settings, contentDescription = "Settings")
            }
            IconButton(onClick = {}) {
                Icon(Icons.Rounded.MoreVert, contentDescription = "More")
            }
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(42.dp)
                .padding(horizontal = 18.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                state.book?.manifest?.displayName.orEmpty(),
                modifier = Modifier.weight(1f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                color = MirookColors.ink
            )
            Text("Page ${state.pageNumber}", color = MirookColors.muted)
        }
        DividerLine()
    }
}

@Composable
private fun SingleContent(state: ReaderUiState, modifier: Modifier = Modifier) {
    Box(modifier = modifier.fillMaxWidth()) {
        when (state.mode) {
            ReaderMode.Original -> OriginalPane(state)
            ReaderMode.Split -> TranslationPane(state)
            ReaderMode.Translation -> TranslationPane(state)
        }
    }
}

@Composable
private fun SplitContent(state: ReaderUiState, modifier: Modifier = Modifier) {
    Row(modifier = modifier.fillMaxWidth()) {
        OriginalPane(state, modifier = Modifier.weight(1f))
        Box(
            Modifier
                .fillMaxHeight()
                .width(1.dp)
                .background(MirookColors.border)
        )
        TranslationPane(state, modifier = Modifier.weight(1f))
    }
}

@Composable
private fun TranslationPane(state: ReaderUiState, modifier: Modifier = Modifier) {
    val scroll = rememberScrollState()
    LaunchedEffect(state.pageIndex, state.mode) { scroll.scrollTo(0) }

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(scroll)
            .padding(18.dp)
    ) {
        MirookPanel(backgroundColor = MirookColors.paper) {
            if (state.isCurrentPageBlank) {
                EmptyPage("Blank page")
            } else if (state.isCurrentPageMissing) {
                EmptyPage("This page has not been translated yet.")
            } else {
                CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                    val epubPage = state.currentEpubPage
                    if (epubPage != null) {
                        TranslatedEpubPageView(
                            page = epubPage,
                            translatedText = state.currentTranslation,
                            fontSize = state.fontSize
                        )
                    } else {
                        SelectionContainer {
                            TranslatedParagraphText(
                                text = state.currentTranslation.normalizedParagraphs(),
                                fontSize = state.fontSize
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun OriginalPane(state: ReaderUiState, modifier: Modifier = Modifier) {
    val scroll = rememberScrollState()
    LaunchedEffect(state.pageIndex, state.mode) { scroll.scrollTo(0) }

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(scroll)
            .padding(18.dp)
    ) {
        MirookPanel {
            if (state.sourceBitmap != null) {
                Image(
                    bitmap = state.sourceBitmap.asImageBitmap(),
                    contentDescription = null,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(6.dp)),
                    contentScale = ContentScale.FillWidth
                )
            } else if (state.currentEpubPage != null) {
                EpubPageView(state.currentEpubPage, state.fontSize)
            } else {
                SelectionContainer {
                    Text(
                        state.currentSourceText.ifBlank { "Original page is not available." },
                        style = TextStyle(
                            fontSize = 19.sp,
                            lineHeight = 31.sp,
                            fontFamily = FontFamily.Serif,
                            color = MirookColors.ink
                        )
                    )
                }
            }
        }
    }
}

@Composable
private fun EpubPageView(page: com.espitman.mirook.reader.domain.EpubPage, fontSize: Int) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        page.blocks.forEach { block ->
            when (block) {
                is EpubBlock.Text -> SelectionContainer {
                    Text(
                        block.text,
                        style = TextStyle(
                            fontSize = (fontSize - 2).coerceAtLeast(14).sp,
                            lineHeight = (fontSize * 1.55).sp,
                            fontFamily = FontFamily.Serif,
                            color = MirookColors.ink
                        )
                    )
                }
                is EpubBlock.Link -> SelectionContainer {
                    Text(
                        block.title,
                        style = TextStyle(
                            fontSize = (fontSize - 2).coerceAtLeast(14).sp,
                            lineHeight = (fontSize * 1.55).sp,
                            fontFamily = FontFamily.Serif,
                            color = Color(0xFF0B57D0)
                        )
                    )
                }
                is EpubBlock.Image -> {
                    EpubImage(block)
                }
            }
        }
    }
}

@Composable
private fun TranslatedEpubPageView(
    page: com.espitman.mirook.reader.domain.EpubPage,
    translatedText: String,
    fontSize: Int
) {
    val paragraphs = remember(translatedText) { translatedText.paragraphList() }
    var textIndex = 0
    var previousSourceText = ""

    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        page.blocks.displayBlocks().forEach { block ->
            when (block) {
                is EpubBlock.Text -> {
                    val text = paragraphs.getOrNull(textIndex)
                    textIndex += 1
                    if (!text.isNullOrBlank()) {
                        SelectionContainer {
                            TranslatedParagraphText(text = text, fontSize = fontSize)
                        }
                    }
                    previousSourceText = block.text
                }
                is EpubBlock.Link -> {
                    val text = paragraphs.getOrNull(textIndex)
                    textIndex += 1
                    if (!text.isNullOrBlank()) {
                        SelectionContainer {
                            TranslatedParagraphText(text = text, fontSize = fontSize)
                        }
                    }
                    previousSourceText = block.title
                }
                is EpubBlock.Image -> {
                    val nextText = paragraphs.getOrNull(textIndex)
                    if (!nextText.isNullOrBlank() && shouldPlaceBeforeImage(nextText, previousSourceText)) {
                        textIndex += 1
                        SelectionContainer {
                            TranslatedParagraphText(text = nextText, fontSize = fontSize)
                        }
                    }
                    EpubImage(block)
                }
            }
        }

        paragraphs.drop(textIndex).forEach { text ->
            if (text.isNotBlank()) {
                SelectionContainer {
                    TranslatedParagraphText(text = text, fontSize = fontSize)
                }
            }
        }
    }
}

@Composable
private fun TranslatedParagraphText(text: String, fontSize: Int, modifier: Modifier = Modifier) {
    Text(
        text = text,
        modifier = modifier.fillMaxWidth(),
        style = TextStyle(
            fontFamily = vazirmatnFamily(),
            fontSize = fontSize.sp,
            lineHeight = (fontSize * 1.75).sp,
            textAlign = TextAlign.Right,
            color = MirookColors.ink
        )
    )
}

@Composable
private fun EpubImage(block: EpubBlock.Image) {
    val bitmap = remember(block.bytes) {
        BitmapFactory.decodeByteArray(block.bytes, 0, block.bytes.size)
    }
    if (bitmap != null) {
        Image(
            bitmap = bitmap.asImageBitmap(),
            contentDescription = block.altText,
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(6.dp)),
            contentScale = ContentScale.FillWidth
        )
    }
}

@Composable
private fun ReaderBottomBar(
    state: ReaderUiState,
    showSplit: Boolean,
    onMode: (ReaderMode) -> Unit,
    onPrevious: () -> Unit,
    onNext: () -> Unit
) {
    BoxWithConstraints(
        modifier = Modifier
            .fillMaxWidth()
            .padding(12.dp)
            .clip(RoundedCornerShape(18.dp))
            .border(1.dp, MirookColors.border, RoundedCornerShape(18.dp))
            .background(MirookColors.panel)
            .padding(8.dp)
    ) {
        val compact = maxWidth < 430.dp
        val modes = if (showSplit) listOf(ReaderMode.Original, ReaderMode.Split, ReaderMode.Translation)
        else listOf(ReaderMode.Original, ReaderMode.Translation)

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            TextButton(
                onClick = onPrevious,
                enabled = state.canGoPrevious,
                modifier = Modifier
                    .width(if (compact) 44.dp else 108.dp)
                    .defaultMinSize(minWidth = 1.dp, minHeight = 44.dp),
                contentPadding = ButtonDefaults.TextButtonContentPadding
            ) {
                Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "Previous")
                if (!compact) {
                    Text("Previous", maxLines = 1, overflow = TextOverflow.Clip)
                }
            }

            SingleChoiceSegmentedButtonRow(modifier = Modifier.weight(1f)) {
                modes.forEachIndexed { index, mode ->
                    SegmentedButton(
                        selected = state.mode == mode,
                        onClick = { onMode(mode) },
                        shape = SegmentedButtonDefaults.itemShape(index, modes.size),
                        label = {
                            Text(
                                when (mode) {
                                    ReaderMode.Original -> "Original"
                                    ReaderMode.Split -> "Split"
                                    ReaderMode.Translation -> "Translation"
                                },
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                fontSize = if (compact) 13.sp else 14.sp
                            )
                        }
                    )
                }
            }

            TextButton(
                onClick = onNext,
                enabled = state.canGoNext,
                modifier = Modifier
                    .width(if (compact) 44.dp else 76.dp)
                    .defaultMinSize(minWidth = 1.dp, minHeight = 44.dp),
                contentPadding = ButtonDefaults.TextButtonContentPadding
            ) {
                if (!compact) {
                    Text("Next", maxLines = 1, overflow = TextOverflow.Clip)
                }
                Icon(Icons.AutoMirrored.Rounded.ArrowForward, contentDescription = "Next")
            }
        }
    }
}

@Composable
private fun PasswordDialog(onDismiss: () -> Unit, onSubmit: (String) -> Unit) {
    var password by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Unlock Book") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("This Mirook book is password protected.")
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    singleLine = true,
                    label = { Text("Password") }
                )
            }
        },
        confirmButton = {
            Button(onClick = { onSubmit(password) }, enabled = password.isNotEmpty()) {
                Text("Unlock")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        }
    )
}

@Composable
private fun RecentBookRow(recent: RecentBook, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(14.dp),
        color = MirookColors.panel,
        tonalElevation = 0.dp,
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, MirookColors.border, RoundedCornerShape(14.dp))
    ) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier
                    .size(width = 46.dp, height = 64.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .background(Color.White)
                    .border(1.dp, MirookColors.border, RoundedCornerShape(6.dp)),
                contentAlignment = Alignment.Center
            ) {
                Icon(painterResource(R.drawable.ic_mirook_mark), contentDescription = null, tint = MirookColors.ink)
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(recent.displayName, maxLines = 2, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.SemiBold)
                Text("${recent.pageCount} pages • ${recent.kind.displayName}", color = MirookColors.muted, fontSize = 13.sp)
            }
            Text(".mrbk", color = MirookColors.muted, fontSize = 12.sp)
        }
    }
}

@Composable
private fun BrandHeader() {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(
            painter = painterResource(R.drawable.ic_mirook_mark),
            contentDescription = null,
            tint = MirookColors.ink,
            modifier = Modifier.size(42.dp)
        )
        Spacer(Modifier.width(8.dp))
        Text("Mirook", fontSize = 24.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun HomeRow(title: String, subtitle: String, trailing: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(title, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
        Text(subtitle, color = MirookColors.muted, fontSize = 12.sp)
        Spacer(Modifier.width(10.dp))
        Text(trailing, color = MirookColors.ink, fontSize = 22.sp)
    }
}

@Composable
private fun MirookPanel(
    backgroundColor: Color = MirookColors.panel,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(backgroundColor)
            .border(1.dp, MirookColors.border, RoundedCornerShape(14.dp))
            .padding(16.dp),
        content = content
    )
}

@Composable
private fun DividerLine() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(1.dp)
            .background(MirookColors.border)
    )
}

@Composable
private fun EmptyPage(text: String) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(320.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(text, color = MirookColors.muted, textAlign = TextAlign.Center)
    }
}

@Composable
private fun LoadingOverlay() {
    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.12f)),
        contentAlignment = Alignment.Center
    ) {
        CircularProgressIndicator(color = MirookColors.ink)
    }
}

@Composable
private fun MirookTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = androidx.compose.material3.lightColorScheme(
            background = MirookColors.background,
            surface = MirookColors.panel,
            primary = MirookColors.ink
        ),
        typography = MaterialTheme.typography.copy(
            bodyLarge = MaterialTheme.typography.bodyLarge.copy(fontFamily = vazirmatnFamily()),
            bodyMedium = MaterialTheme.typography.bodyMedium.copy(fontFamily = vazirmatnFamily()),
            labelLarge = MaterialTheme.typography.labelLarge.copy(fontFamily = vazirmatnFamily())
        ),
        content = content
    )
}

@Composable
private fun vazirmatnFamily(): FontFamily =
    FontFamily(
        Font(R.font.vazirmatn_regular, FontWeight.Normal),
        Font(R.font.vazirmatn_bold, FontWeight.Bold)
    )

private object MirookColors {
    val background = Color(0xFFF6F1E8)
    val panel = Color(0xFFFBF8F1)
    val paper = Color(0xFFFFFEFB)
    val ink = Color(0xFF151515)
    val muted = Color(0xFF706B63)
    val border = Color(0xFFE2DCD2)
}

private fun String.normalizedParagraphs(): String =
    replace("\r\n", "\n")
        .replace("\r", "\n")
        .lines()
        .map { it.trim() }
        .filter { it.isNotEmpty() }
        .joinToString("\n\n")

private fun String.paragraphList(): List<String> =
    normalizedParagraphs()
        .split(Regex("\\n{2,}"))
        .map { it.trim() }
        .filter { it.isNotEmpty() }

private fun List<EpubBlock>.displayBlocks(): List<EpubBlock> {
    val result = mutableListOf<EpubBlock>()
    var index = 0
    while (index < size) {
        val block = this[index]
        if (block !is EpubBlock.Text) {
            result.add(block)
            index += 1
            continue
        }

        var mergedText = block.text
        var nextIndex = index + 1
        while (nextIndex < size) {
            val next = this[nextIndex] as? EpubBlock.Text ?: break
            if (!shouldMergeTextFragment(mergedText, next.text)) break
            mergedText += "\n${next.text}"
            nextIndex += 1
        }

        result.add(EpubBlock.Text(mergedText))
        index = nextIndex
    }
    return result
}

private fun shouldPlaceBeforeImage(translatedParagraph: String, previousSourceText: String): Boolean {
    val translated = translatedParagraph.trim()
    val source = previousSourceText.trim()
    if (translated.isEmpty() || source.isEmpty()) return false

    val sourceMentionsFigure = Regex("""(?i)\b(fig\.?|figure|illustration)\b""").containsMatchIn(source)
    val translationMentionsFigure = translated.contains("شکل") ||
        Regex("""(?i)\b(fig\.?|figure)\b""").containsMatchIn(translated)
    return sourceMentionsFigure && translationMentionsFigure
}

private fun shouldMergeTextFragment(current: String, next: String): Boolean {
    if (shouldMergeTitleFragment(current, next)) return true

    val currentTrimmed = current.trim()
    val nextTrimmed = next.trim()
    if (currentTrimmed.isEmpty() || nextTrimmed.isEmpty()) return false
    if (endsSentence(currentTrimmed) || isHeadingLike(currentTrimmed) || startsNewListItem(nextTrimmed)) {
        return false
    }

    return currentTrimmed.length >= 45 || startsWithContinuation(nextTrimmed)
}

private fun shouldMergeTitleFragment(current: String, next: String): Boolean {
    val currentTrimmed = current.trim()
    val nextTrimmed = next.trim()
    if (currentTrimmed.length > 90 || nextTrimmed.length > 60) return false
    return isTitleLike(currentTrimmed) && isTitleLike(nextTrimmed)
}

private fun isTitleLike(text: String): Boolean {
    val letters = text.filter { it.isLetter() }
    if (letters.isEmpty()) return false
    val uppercaseLetters = letters.count { it.isUpperCase() }
    if (uppercaseLetters.toDouble() / letters.length.toDouble() >= 0.75) return true
    return Regex("""(?i)^\s*(chapter|part|section)\b""").containsMatchIn(text)
}

private fun isHeadingLike(text: String): Boolean {
    if (text.length > 72 || endsSentence(text) || startsNewListItem(text)) return false
    return text.split(Regex("\\s+")).filter { it.isNotBlank() }.size <= 8
}

private fun endsSentence(text: String): Boolean {
    val last = text.trim().lastOrNull() ?: return false
    return ".!?:;،؛؟。)»”]".contains(last)
}

private fun startsNewListItem(text: String): Boolean =
    Regex("""^\s*(?:[\u2022\-*•]|\d+[\.)])\s+""").containsMatchIn(text)

private fun startsWithContinuation(text: String): Boolean {
    val first = text.trim().firstOrNull() ?: return false
    return first.isLowerCase() || "،؛:;)]}»”".contains(first)
}
