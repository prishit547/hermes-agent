import 'package:flutter/foundation.dart';

import '../../../data/repositories/jobs_repository.dart';
import '../../../domain/models/cron_job.dart';

/// Presentation logic for the Automations screen: lists server-side scheduled
/// agent routines (cron jobs) and creates / pauses / runs / deletes them through
/// [JobsRepository]. These run on the gateway even when the app is closed.
class AutomationsViewModel extends ChangeNotifier {
  AutomationsViewModel(this._repo);

  final JobsRepository _repo;

  List<CronJob> _jobs = const [];
  List<CronJob> get jobs => _jobs;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _jobs = await _repo.list();
    } catch (e) {
      _error = '$e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Creates a routine. Returns null on success, or an error message to surface.
  Future<String?> create({
    required String name,
    required String schedule,
    required String prompt,
    String deliver = 'local',
  }) async {
    try {
      await _repo.create(
        name: name,
        schedule: schedule,
        prompt: prompt,
        deliver: deliver,
      );
      await load();
      return null;
    } catch (e) {
      return '$e';
    }
  }

  Future<void> setPaused(CronJob job, bool paused) async {
    try {
      paused ? await _repo.pause(job.id) : await _repo.resume(job.id);
      await load();
    } catch (e) {
      _error = '$e';
      notifyListeners();
    }
  }

  /// Fires a routine now. Returns null on success or an error message.
  Future<String?> runNow(CronJob job) async {
    try {
      await _repo.run(job.id);
      return null;
    } catch (e) {
      return '$e';
    }
  }

  Future<void> delete(CronJob job) async {
    try {
      await _repo.delete(job.id);
      await load();
    } catch (e) {
      _error = '$e';
      notifyListeners();
    }
  }
}
