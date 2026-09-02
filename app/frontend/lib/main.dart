import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'data/app_state.dart';
import 'theme/app_theme.dart';
import 'widgets/app_shell.dart';

void main() {
  runApp(const ArchangelApp());
}

/// No Android-style stretch/glow overscroll — it clashes with this design's
/// own motion language and the dark cockpit aesthetic's custom scrollbar.
class _NoOverscrollBehavior extends MaterialScrollBehavior {
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}

class ArchangelApp extends StatelessWidget {
  const ArchangelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: Consumer<AppState>(
        builder: (context, app, _) => MaterialApp(
          title: 'Archangel',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(accent: app.accent),
          scrollBehavior: _NoOverscrollBehavior(),
          home: const AppShell(),
        ),
      ),
    );
  }
}
