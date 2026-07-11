import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the active theme mode. The Atlantic design defaults to **dark** and
/// exposes an in-app light/dark toggle; the choice is persisted.
class ThemeController extends ChangeNotifier {
  ThemeController({ThemeMode initial = ThemeMode.dark}) : _mode = initial;

  static const _key = 'hermes.theme_mode';

  ThemeMode _mode;
  ThemeMode get mode => _mode;

  bool get isDark => _mode == ThemeMode.dark;

  static Future<ThemeController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    final mode = switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.dark,
    };
    return ThemeController(initial: mode);
  }

  Future<void> setDark(bool dark) async {
    _mode = dark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, dark ? 'dark' : 'light');
  }

  Future<void> toggle() => setDark(!isDark);
}
