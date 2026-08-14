package com.otorunners.ora.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.Image
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.otorunners.ora.ui.theme.OraCreamMuted
import com.otorunners.ora.ui.theme.OraDisplayLarge
import com.otorunners.ora.ui.theme.OraDisplaySmall
import com.otorunners.ora.ui.theme.OraGold
import com.otorunners.ora.ui.theme.OraOutline
import com.otorunners.ora.ui.theme.OraPanel
import com.otorunners.ora.ui.theme.OraPanelAlt

@Composable
fun OraIcon(
    drawableRes: Int,
    contentDescription: String,
    modifier: Modifier = Modifier
) {
    Image(
        painter = painterResource(id = drawableRes),
        contentDescription = contentDescription,
        modifier = modifier,
        contentScale = ContentScale.Fit
    )
}

@Composable
fun OraScreenTitle(
    title: String,
    subtitle: String? = null,
    modifier: Modifier = Modifier,
    iconRes: Int? = null,
    iconDescription: String = title
) {
    Column(modifier = modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (iconRes != null) {
                OraIcon(
                    drawableRes = iconRes,
                    contentDescription = iconDescription,
                    modifier = Modifier.size(36.dp)
                )
            }
            Text(
                text = title,
                style = OraDisplayLarge,
                color = MaterialTheme.colorScheme.onBackground
            )
        }
        if (subtitle != null) {
            Text(
                text = subtitle,
                style = MaterialTheme.typography.labelSmall,
                color = OraCreamMuted
            )
        }
    }
}

@Composable
fun OraCard(
    title: String,
    modifier: Modifier = Modifier,
    iconRes: Int? = null,
    iconDescription: String = title,
    containerColor: Color = OraPanel,
    borderColor: Color = OraOutline,
    borderWidth: Dp = 1.5.dp,
    titleColor: Color = OraGold,
    content: @Composable ColumnScope.() -> Unit
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(5.dp),
        colors = CardDefaults.cardColors(containerColor = containerColor),
        border = BorderStroke(borderWidth, borderColor)
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (iconRes != null) {
                    OraIcon(
                        drawableRes = iconRes,
                        contentDescription = iconDescription,
                        modifier = Modifier.size(24.dp)
                    )
                }
                Text(
                    text = title,
                    style = OraDisplaySmall,
                    fontWeight = FontWeight.Bold,
                    color = titleColor
                )
            }
            content()
        }
    }
}

@Composable
fun StatLine(label: String, value: String, modifier: Modifier = Modifier, iconRes: Int? = null) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.weight(1f)
        ) {
            if (iconRes != null) {
                OraIcon(drawableRes = iconRes, contentDescription = label, modifier = Modifier.size(20.dp))
            }
            Text(text = label, color = OraCreamMuted, style = MaterialTheme.typography.bodyMedium)
        }
        Text(
            text = value,
            color = MaterialTheme.colorScheme.onSurface,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.End
        )
    }
}

@Composable
fun XpProgress(current: String, target: String, progress: Float, modifier: Modifier = Modifier, iconRes: Int? = null) {
    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        StatLine(label = "XP", value = "$current / $target", iconRes = iconRes)
        LinearProgressIndicator(
            progress = { progress },
            modifier = Modifier
                .fillMaxWidth()
                .height(10.dp)
                .clip(RoundedCornerShape(2.dp)),
            color = OraGold,
            trackColor = OraPanelAlt
        )
    }
}

@Composable
fun PixelBadge(text: String, modifier: Modifier = Modifier, color: Color = OraGold) {
    Box(
        modifier = modifier
            .border(1.dp, color, RoundedCornerShape(3.dp))
            .background(color.copy(alpha = 0.12f), RoundedCornerShape(3.dp))
            .padding(horizontal = 8.dp, vertical = 4.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(text = text, color = color, style = OraDisplaySmall, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun CompactStat(value: String, label: String, modifier: Modifier = Modifier, iconRes: Int? = null) {
    Column(
        modifier = modifier
            .background(OraPanelAlt, RoundedCornerShape(6.dp))
            .padding(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        if (iconRes != null) {
            OraIcon(drawableRes = iconRes, contentDescription = label, modifier = Modifier.size(24.dp))
            Spacer(modifier = Modifier.height(6.dp))
        }
        Text(text = value, color = MaterialTheme.colorScheme.onSurface, fontWeight = FontWeight.Bold)
        Spacer(modifier = Modifier.height(2.dp))
        Text(text = label, color = OraCreamMuted, style = MaterialTheme.typography.labelSmall, textAlign = TextAlign.Center)
    }
}

@Composable
fun AchievementSlot(label: String, modifier: Modifier = Modifier, iconRes: Int? = null) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = modifier.width(72.dp)) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .background(OraPanelAlt, RoundedCornerShape(6.dp))
                .border(1.dp, OraOutline, RoundedCornerShape(6.dp)),
            contentAlignment = Alignment.Center
        ) {
            if (iconRes != null) {
                OraIcon(drawableRes = iconRes, contentDescription = label, modifier = Modifier.size(30.dp))
            } else {
                Text(text = label.take(1), color = OraGold, fontWeight = FontWeight.Bold)
            }
        }
        Spacer(modifier = Modifier.height(6.dp))
        Text(text = label, color = OraCreamMuted, style = MaterialTheme.typography.labelSmall, textAlign = TextAlign.Center)
    }
}
