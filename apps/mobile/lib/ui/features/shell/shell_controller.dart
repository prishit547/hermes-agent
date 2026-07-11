import 'package:flutter/foundation.dart';

enum AtlTab { today, chat, calendar, inbox }

/// Owns primary navigation state: the active bottom tab and whether the Halo
/// voice overlay is open. Shared via provider so any screen (e.g. the Today
/// "Ask" bar) can open voice or jump tabs.
class ShellController extends ChangeNotifier {
  AtlTab _tab = AtlTab.today;
  AtlTab get tab => _tab;

  bool _voiceOpen = false;
  bool get voiceOpen => _voiceOpen;

  void go(AtlTab t) {
    _tab = t;
    _voiceOpen = false;
    notifyListeners();
  }

  void openVoice() {
    _voiceOpen = true;
    notifyListeners();
  }

  void closeVoice() {
    _voiceOpen = false;
    notifyListeners();
  }
}
