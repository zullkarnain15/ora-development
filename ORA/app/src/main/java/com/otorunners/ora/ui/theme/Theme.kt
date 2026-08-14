package com.otorunners.ora.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable

private val OraColorScheme = darkColorScheme(
    primary = OraGold,
    onPrimary = OraForestDeep,
    secondary = OraMoss,
    onSecondary = OraForestDeep,
    tertiary = OraOrange,
    background = OraForestDeep,
    onBackground = OraCream,
    surface = OraForest,
    onSurface = OraCream,
    surfaceVariant = OraPanel,
    onSurfaceVariant = OraCreamMuted,
    outline = OraOutline
)

@Composable
fun ORATheme(
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = OraColorScheme,
        typography = Typography,
        content = content
    )
}
