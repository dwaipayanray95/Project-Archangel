import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../data/app_state.dart';
import '../theme/tokens.dart';
import '../screens/overview_screen.dart';
import '../screens/monitoring_screen.dart';
import '../screens/files_screen.dart';
import '../screens/containers_screen.dart';
import '../screens/devops_screen.dart';
import '../screens/terminal_screen.dart';
import '../screens/settings_screen.dart';
import 'command_palette.dart';
import 'notif_panel.dart';
import 'sidebar.dart';
import 'top_bar.dart';

const _kOpenPalette = SingleActivator(LogicalKeyboardKey.keyK, meta: true);
const _kOpenPaletteCtrl = SingleActivator(LogicalKeyboardKey.keyK, control: true);

/// Root shell: persistent top bar + sidebar/bottom-tabs + section content,
/// with the command palette and notification panel as overlays. Each
/// section keeps its own state alive via IndexedStack so switching feels
/// like OS-style app-switching rather than a page reload.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;

        return CallbackShortcuts(
          bindings: {
            _kOpenPalette: app.openPalette,
            _kOpenPaletteCtrl: app.openPalette,
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              backgroundColor: AxColors.bg,
              body: Stack(
                fit: StackFit.expand,
                children: [
                  Column(
                    children: [
                      TopBar(wide: wide),
                      Expanded(
                        child: Row(
                          children: [
                            if (wide) const Sidebar(),
                            Expanded(
                              child: GestureDetector(
                                onTap: app.closeNotif,
                                behavior: HitTestBehavior.translucent,
                                child: IndexedStack(
                                  index: AxSection.values.indexOf(app.section),
                                  children: const [
                                    OverviewScreen(),
                                    MonitoringScreen(),
                                    FilesScreen(),
                                    ContainersScreen(),
                                    DevopsScreen(),
                                    TerminalScreen(),
                                    SettingsScreen(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!wide) const BottomTabs(),
                    ],
                  ),
                  if (app.notifOpen) const NotifPanel(),
                  if (app.paletteOpen) const Positioned.fill(child: CommandPalette()),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
