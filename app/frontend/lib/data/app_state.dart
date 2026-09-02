import 'package:flutter/material.dart';
import '../theme/tokens.dart';

enum AxSection { overview, monitoring, files, containers, devops, terminal, settings }

const axSectionLabels = <AxSection, String>{
  AxSection.overview: 'Overview',
  AxSection.monitoring: 'Monitoring',
  AxSection.files: 'Files',
  AxSection.containers: 'Containers',
  AxSection.devops: 'DevOps',
  AxSection.terminal: 'Terminal',
  AxSection.settings: 'Settings',
};

/// Root app state: active section, accent color, palette/notif overlays.
/// Kept deliberately simple (ChangeNotifier) — this is a single-user app
/// with no need for a heavier state management layer yet.
class AppState extends ChangeNotifier {
  AxSection _section = AxSection.overview;
  AxSection get section => _section;
  set section(AxSection s) {
    if (_section == s) return;
    _section = s;
    notifyListeners();
  }

  Color _accent = AxColors.accent;
  Color get accent => _accent;
  set accent(Color c) {
    _accent = c;
    notifyListeners();
  }

  bool _paletteOpen = false;
  bool get paletteOpen => _paletteOpen;
  void openPalette() {
    _paletteOpen = true;
    notifyListeners();
  }

  void closePalette() {
    _paletteOpen = false;
    notifyListeners();
  }

  bool _notifOpen = false;
  bool get notifOpen => _notifOpen;
  void toggleNotif() {
    _notifOpen = !_notifOpen;
    notifyListeners();
  }

  void closeNotif() {
    if (!_notifOpen) return;
    _notifOpen = false;
    notifyListeners();
  }

  void go(AxSection s) {
    section = s;
    _paletteOpen = false;
    _notifOpen = false;
    notifyListeners();
  }
}
