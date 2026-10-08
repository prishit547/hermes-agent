import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/code_repository.dart';
import '../../../domain/models/code_project.dart';
import '../../../domain/models/code_session.dart';
import '../../../domain/models/code_stream_event.dart';
import '../../../domain/models/code_usage.dart';

/// A rendered line in the session transcript. Kept deliberately simple — the
/// stream is mapped onto a flat, append-only list the UI renders top-to-bottom.
sealed class CodeItem {
  CodeItem();
}

class UserItem extends CodeItem {
  UserItem(this.text);
  final String text;
}

class AssistantItem extends CodeItem {
  AssistantItem(this.text);
  String text; // accumulates across assistant.text chunks in a turn
}

class ToolItem extends CodeItem {
  ToolItem({required this.tool, this.input});
  final String tool;
  final String? input;
  bool done = false;
  bool isError = false;
  String? preview;
}

class SummaryItem extends CodeItem {
  SummaryItem(this.text);
  final String text;
}

class ResultItem extends CodeItem {
  ResultItem({required this.isError, required this.denials});
  final bool isError;
  final List<CodeDenial> denials;
}

class ErrorItem extends CodeItem {
  ErrorItem(this.message);
  final String message;
}

/// A plan the model produced in plan mode. Until [approved], the card offers
/// "Approve & build" actions that kick off the implementation.
class PlanItem extends CodeItem {
  PlanItem(this.plan);
  final String plan;
  bool approved = false;
}

/// A pending per-action approval (approve mode). [resolved] is null while
/// awaiting the user, then true (allowed) or false (denied).
class PermissionItem extends CodeItem {
  PermissionItem({
    required this.toolUseId,
    required this.tool,
    required this.summary,
    this.input,
  });
  final String toolUseId;
  final String tool;
  final String summary;
  final String? input;
  bool? resolved;
  bool sending = false;
}

/// Drives one Claude Code session: project selection, the live turn stream, and
/// the diff/commit review loop. Created per open of the Code surface.
class CodeViewModel extends ChangeNotifier {
  CodeViewModel(this._repo);

  final CodeRepository _repo;

  // -- projects ----------------------------------------------------------
  List<CodeProject> projects = const [];
  bool loadingProjects = false;
  String? projectsError;

  Future<void> loadProjects() async {
    loadingProjects = true;
    projectsError = null;
    notifyListeners();
    try {
      projects = await _repo.projects();
    } catch (e) {
      projectsError = '$e';
    } finally {
      loadingProjects = false;
      notifyListeners();
    }
  }

  // -- usage ---------------------------------------------------------------
  CodeUsage? usage;
  bool loadingUsage = false;

  Future<void> loadUsage() async {
    loadingUsage = true;
    notifyListeners();
    try {
      usage = await _repo.usage();
    } catch (_) {
      // Usage is a nice-to-have summary; a failed fetch shouldn't block the
      // project picker, so fail silently and just leave it unset.
    } finally {
      loadingUsage = false;
      notifyListeners();
    }
  }

  /// Force an immediate `/usage` check. Zero-cost (no model call), so this is
  /// safe to expose as a manual refresh the user can tap anytime.
  bool checkingUsage = false;

  Future<void> checkUsageNow() async {
    if (checkingUsage) return;
    checkingUsage = true;
    notifyListeners();
    try {
      usage = await _repo.refreshUsage();
    } catch (_) {
      // leave the last-known usage in place on failure
    } finally {
      checkingUsage = false;
      notifyListeners();
    }
  }

  /// The live rate-limit snapshot observed on the CURRENT turn, if any
  /// (distinct from [usage]'s point-in-time fetch — this updates as a turn
  /// streams in).
  CodeRateLimit? liveRateLimit;

  // -- active session ----------------------------------------------------
  CodeSession? session;

  /// Permission mode for the next turn. `default` = safe (reads, no writes);
  /// `acceptEdits` = writes land in the working tree.
  String permissionMode = 'default';

  final List<CodeItem> transcript = [];
  bool streaming = false;
  StreamSubscription<CodeStreamEvent>? _sub;
  final Map<String, ToolItem> _pendingTools = {};

  bool get editMode => permissionMode == 'acceptEdits';

  /// Whether the current mode can change files (so we refresh the diff after a turn).
  bool get canEdit => permissionMode == 'acceptEdits' || permissionMode == 'approve';

  /// The approval currently awaiting the user, if any.
  PermissionItem? pendingPermission;

  /// The plan awaiting approval, if any (plan mode).
  PlanItem? pendingPlan;
  bool _planCapturedThisTurn = false;
  String _turnMode = 'default';
  String _lastPlanText = '';

  Future<CodeSession> startSession(CodeProject project, {required String mode}) async {
    permissionMode = mode;
    final s = await _repo.createSession(project: project.name, permissionMode: mode);
    session = s;
    permissionMode = s.permissionMode;
    transcript.clear();
    _pendingTools.clear();
    notifyListeners();
    return s;
  }

  void setPermissionMode(String mode) {
    permissionMode = mode;
    notifyListeners();
  }

  Future<void> send(String message) async {
    final s = session;
    if (s == null || streaming || message.trim().isEmpty) return;
    transcript.add(UserItem(message.trim()));
    streaming = true;
    _pendingTools.clear();
    _planCapturedThisTurn = false;
    _turnMode = permissionMode;
    _lastPlanText = '';
    notifyListeners();

    _sub = _repo
        .streamTurn(sessionId: s.id, message: message.trim(), permissionMode: permissionMode)
        .listen(
      _onEvent,
      onError: (Object e) {
        transcript.add(ErrorItem('$e'));
        streaming = false;
        notifyListeners();
      },
      onDone: () {
        streaming = false;
        pendingPermission = null;
        // Plan-mode fallback: some plan turns present the plan as prose without
        // an ExitPlanMode call, so no plan.ready arrived. Treat the completed
        // plan turn's final text as the plan and offer the approve CTA.
        if (_turnMode == 'plan' && !_planCapturedThisTurn && _lastPlanText.trim().isNotEmpty) {
          final item = PlanItem(_lastPlanText.trim());
          pendingPlan = item;
          transcript.add(item);
        }
        notifyListeners();
        // Refresh the working-tree diff after any turn that could edit files.
        if (canEdit) unawaited(loadDiff());
        unawaited(loadUsage());
      },
    );
  }

  void _onEvent(CodeStreamEvent ev) {
    switch (ev) {
      case CodeSessionInit(:final claudeSessionId):
        if (claudeSessionId != null && session != null && !session!.hasStarted) {
          // Reflect that the CLI session id is now known (for the header).
          session = CodeSession(
            id: session!.id,
            project: session!.project,
            cwd: session!.cwd,
            permissionMode: session!.permissionMode,
            title: session!.title,
            status: 'running',
            turns: session!.turns,
            claudeSessionId: claudeSessionId,
            lastResult: session!.lastResult,
          );
        }
      case CodeAssistantText(:final text):
        if (transcript.isNotEmpty && transcript.last is AssistantItem) {
          (transcript.last as AssistantItem).text += text;
        } else {
          transcript.add(AssistantItem(text));
        }
        _lastPlanText += text; // used as the plan fallback in plan mode
      case CodePlanReady(:final plan):
        final item = PlanItem(plan);
        pendingPlan = item;
        _planCapturedThisTurn = true;
        transcript.add(item);
      case CodeThinking():
        break; // no visible artifact; the spinner already conveys activity
      case CodeToolStarted(:final tool, :final toolId, :final input):
        final item = ToolItem(tool: tool, input: input);
        if (toolId != null) _pendingTools[toolId] = item;
        transcript.add(item);
      case CodeToolResult(:final toolId, :final isError, :final preview):
        final item = toolId != null ? _pendingTools.remove(toolId) : null;
        if (item != null) {
          item.done = true;
          item.isError = isError;
          item.preview = preview;
        }
      case CodePermissionRequest(:final toolUseId, :final tool, :final summary, :final input):
        final item = PermissionItem(
            toolUseId: toolUseId, tool: tool, summary: summary, input: input);
        pendingPermission = item;
        transcript.add(item);
      case CodeRateLimitStatus(:final status, :final resetsAt, :final rateLimitType):
        liveRateLimit = CodeRateLimit(status: status, resetsAt: resetsAt, rateLimitType: rateLimitType);
      case CodeTurnSummary(:final text):
        transcript.add(SummaryItem(text));
      case CodeTurnResult(:final isError, :final result, :final denials):
        // Prefer the clean consolidated final message as the plan fallback.
        if (result.trim().isNotEmpty) _lastPlanText = result;
        transcript.add(ResultItem(isError: isError, denials: denials));
      case CodeErrored(:final message):
        transcript.add(ErrorItem(message));
      case CodeStreamDone():
        break;
    }
    notifyListeners();
  }

  Future<void> interrupt() async {
    final s = session;
    if (s == null) return;
    try {
      await _repo.interrupt(s.id);
    } catch (_) {}
  }

  /// Approve or deny a pending per-action request. The turn's SSE stream stays
  /// open and resumes once the gateway relays the decision to the CLI.
  Future<void> respondPermission(PermissionItem item, bool allow) async {
    final s = session;
    if (s == null || item.resolved != null || item.sending) return;
    item.sending = true;
    notifyListeners();
    try {
      await _repo.respondPermission(s.id, item.toolUseId, allow);
      item.resolved = allow;
    } catch (_) {
      // leave unresolved so the user can retry
    } finally {
      item.sending = false;
      if (identical(pendingPermission, item)) pendingPermission = null;
      notifyListeners();
    }
  }

  /// Approve a plan and immediately kick off the implementation. Switches the
  /// session into a build mode (`acceptEdits` = Auto, or `approve` = per-action)
  /// and resumes — the CLI already has the plan in context.
  Future<void> approvePlanAndBuild(PlanItem item, {required String mode}) async {
    if (item.approved || streaming) return;
    item.approved = true;
    if (identical(pendingPlan, item)) pendingPlan = null;
    permissionMode = mode;
    notifyListeners();
    await send('Go ahead and implement the plan you outlined above. '
        'Proceed with the full implementation now.');
  }

  Future<Map<String, dynamic>> openPr({String? title, String? body}) async {
    final s = session;
    if (s == null) return {'ok': false, 'error': 'no session'};
    return _repo.openPr(id: s.id, title: title, body: body);
  }

  // -- diff / commit -----------------------------------------------------
  Map<String, dynamic>? diff;
  bool loadingDiff = false;

  Future<void> loadDiff() async {
    final s = session;
    if (s == null) return;
    loadingDiff = true;
    notifyListeners();
    try {
      diff = await _repo.diff(s.id);
    } catch (e) {
      diff = {'diff': 'Failed to load diff: $e', 'stat': '', 'untracked': <String>[]};
    } finally {
      loadingDiff = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> commit(String message, {bool push = false}) async {
    final s = session;
    if (s == null) return {'ok': false, 'error': 'no session'};
    final result = await _repo.commit(id: s.id, message: message, push: push);
    await loadDiff();
    return result;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
