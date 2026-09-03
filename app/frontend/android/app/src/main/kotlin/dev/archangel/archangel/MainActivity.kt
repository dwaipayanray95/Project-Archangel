package dev.archangel.archangel

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not the default FlutterActivity) because
// local_auth_android's biometric/PIN prompt requires a FragmentActivity
// - see lib/services/local_auth_service.dart.
class MainActivity : FlutterFragmentActivity()
