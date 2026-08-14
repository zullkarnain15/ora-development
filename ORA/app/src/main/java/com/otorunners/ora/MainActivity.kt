package com.otorunners.ora

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.ui.tooling.preview.Preview
import com.otorunners.ora.ui.OraApp
import com.otorunners.ora.ui.theme.ORATheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT)
        )
        setContent {
            ORATheme {
                OraApp()
            }
        }
    }
}

@Preview(showBackground = true)
@androidx.compose.runtime.Composable
fun GreetingPreview() {
    ORATheme {
        OraApp()
    }
}
