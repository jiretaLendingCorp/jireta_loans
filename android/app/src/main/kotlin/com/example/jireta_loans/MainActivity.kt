package com.example.jireta_loans

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Prevent screenshots / screen recording in the app switcher preview
        // (README "Mobile Security: Prevent Screenshots").
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
