package com.otorunners.ora.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.otorunners.ora.R
import com.otorunners.ora.auth.MAX_NICKNAME_LENGTH
import com.otorunners.ora.ui.components.OraIcon
import com.otorunners.ora.ui.theme.OraCreamMuted
import com.otorunners.ora.ui.theme.OraDisplayLarge
import com.otorunners.ora.ui.theme.OraDisplayMedium
import com.otorunners.ora.ui.theme.OraDisplaySmall
import com.otorunners.ora.ui.theme.OraForestDeep
import com.otorunners.ora.ui.theme.OraGold
import com.otorunners.ora.ui.theme.OraOutline
import com.otorunners.ora.ui.theme.OraPanel
import com.otorunners.ora.ui.theme.OraPanelAlt

@Composable
fun ActivationScreen(
    divisionGuild: String,
    errorMessage: String?,
    isLoading: Boolean,
    onClearError: () -> Unit,
    onActivate: (nickname: String) -> Unit,
    modifier: Modifier = Modifier
) {
    var nickname by remember { mutableStateOf("") }
    val submit = { if (!isLoading) onActivate(nickname) }

    Column(
        modifier = modifier
            .fillMaxSize()
            .safeDrawingPadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp, vertical = 30.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .widthIn(max = 440.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            OraIcon(
                drawableRes = R.drawable.you,
                contentDescription = "Create Your Adventurer",
                modifier = Modifier.size(60.dp)
            )
            Spacer(modifier = Modifier.height(14.dp))
            Text(
                text = "CREATE YOUR ADVENTURER",
                style = OraDisplayLarge,
                color = OraGold,
                textAlign = TextAlign.Center
            )
            Spacer(modifier = Modifier.height(24.dp))

            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(5.dp),
                color = OraPanel,
                border = BorderStroke(1.5.dp, OraOutline)
            ) {
                Column(
                    modifier = Modifier.padding(18.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    Surface(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(4.dp),
                        color = OraPanelAlt,
                        border = BorderStroke(1.dp, OraOutline)
                    ) {
                        Row(
                            modifier = Modifier.padding(14.dp),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            OraIcon(
                                drawableRes = R.drawable.guild,
                                contentDescription = "Guild",
                                modifier = Modifier.size(30.dp)
                            )
                            Column {
                                Text(text = "GUILD", style = OraDisplaySmall, color = OraCreamMuted)
                                Text(
                                    text = divisionGuild,
                                    style = MaterialTheme.typography.titleMedium,
                                    color = MaterialTheme.colorScheme.onSurface
                                )
                            }
                        }
                    }

                    OutlinedTextField(
                        value = nickname,
                        onValueChange = {
                            nickname = it.take(MAX_NICKNAME_LENGTH + 4)
                            onClearError()
                        },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Nickname") },
                        enabled = !isLoading,
                        supportingText = { Text("Up to 8 characters, letters and numbers") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(
                            capitalization = KeyboardCapitalization.Characters,
                            imeAction = ImeAction.Done
                        ),
                        keyboardActions = KeyboardActions(onDone = { submit() })
                    )

                    if (errorMessage != null) {
                        AuthError(text = errorMessage)
                    }

                    Button(
                        onClick = submit,
                        enabled = !isLoading,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(60.dp),
                        shape = RoundedCornerShape(6.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = OraGold,
                            contentColor = OraForestDeep
                        )
                    ) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            if (isLoading) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(24.dp),
                                    color = OraForestDeep,
                                    strokeWidth = 3.dp
                                )
                                Text(text = "ACTIVATING...", style = OraDisplayMedium)
                            } else {
                                OraIcon(
                                    drawableRes = R.drawable.success,
                                    contentDescription = "Activate Adventurer",
                                    modifier = Modifier.size(28.dp)
                                )
                                Text(text = "ACTIVATE ADVENTURER", style = OraDisplayMedium)
                            }
                        }
                    }
                }
            }
        }
    }
}
