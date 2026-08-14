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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.otorunners.ora.R
import com.otorunners.ora.ui.components.OraIcon
import com.otorunners.ora.ui.components.PixelBadge
import com.otorunners.ora.ui.theme.OraCreamMuted
import com.otorunners.ora.ui.theme.OraDisplayLarge
import com.otorunners.ora.ui.theme.OraDisplayMedium
import com.otorunners.ora.ui.theme.OraForestDeep
import com.otorunners.ora.ui.theme.OraGold
import com.otorunners.ora.ui.theme.OraOutline
import com.otorunners.ora.ui.theme.OraPanel

@Composable
fun LoginScreen(
    errorMessage: String?,
    isLoading: Boolean,
    onClearError: () -> Unit,
    onLogin: (nik: String, pin: String) -> Unit,
    modifier: Modifier = Modifier
) {
    var nik by remember { mutableStateOf("") }
    var pin by remember { mutableStateOf("") }
    val submit = { if (!isLoading) onLogin(nik, pin) }

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
                drawableRes = R.drawable.run,
                contentDescription = "OTO Runners Adventure",
                modifier = Modifier.size(64.dp)
            )
            Spacer(modifier = Modifier.height(12.dp))
            Text(text = "ORA", style = OraDisplayLarge, color = OraGold, textAlign = TextAlign.Center)
            Text(
                text = "OTO RUNNERS ADVENTURE",
                style = MaterialTheme.typography.labelMedium,
                color = OraCreamMuted,
                textAlign = TextAlign.Center
            )
            Spacer(modifier = Modifier.height(12.dp))
            PixelBadge(text = "RPG - RUN PLAYING GAME")
            Spacer(modifier = Modifier.height(26.dp))

            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(5.dp),
                color = OraPanel,
                border = BorderStroke(1.5.dp, OraOutline)
            ) {
                Column(
                    modifier = Modifier.padding(18.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        OraIcon(
                            drawableRes = R.drawable.lock,
                            contentDescription = "Login",
                            modifier = Modifier.size(26.dp)
                        )
                        Text(text = "ENTER ORA", style = OraDisplayMedium, color = OraGold)
                    }

                    OutlinedTextField(
                        value = nik,
                        onValueChange = {
                            nik = it.take(24)
                            onClearError()
                        },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("NIK") },
                        enabled = !isLoading,
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Number,
                            imeAction = ImeAction.Next
                        )
                    )
                    OutlinedTextField(
                        value = pin,
                        onValueChange = {
                            pin = it.take(8)
                            onClearError()
                        },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("PIN") },
                        enabled = !isLoading,
                        singleLine = true,
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.NumberPassword,
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
                                Text(text = "CONNECTING...", style = OraDisplayMedium)
                            } else {
                                OraIcon(
                                    drawableRes = R.drawable.run,
                                    contentDescription = "Enter Adventure",
                                    modifier = Modifier.size(28.dp)
                                )
                                Text(text = "ENTER ADVENTURE", style = OraDisplayMedium)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
internal fun AuthError(text: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        OraIcon(
            drawableRes = R.drawable.warning,
            contentDescription = "Validation warning",
            modifier = Modifier.size(22.dp)
        )
        Text(
            text = text,
            color = MaterialTheme.colorScheme.error,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.SemiBold
        )
    }
}
