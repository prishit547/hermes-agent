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

  final Map<AtlTab, DateTime> _lastTabVisits = {
    AtlTab.today: DateTime.now(),
    AtlTab.chat: DateTime.now(),
    AtlTab.calendar: DateTime.now(),
    AtlTab.inbox: DateTime.now(),
  };

  DateTime lastVisit(AtlTab t) => _lastTabVisits[t] ?? DateTime.fromMillisecondsSinceEpoch(0);

  void go(AtlTab t) {
    _tab = t;
    _lastTabVisits[t] = DateTime.now();
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
