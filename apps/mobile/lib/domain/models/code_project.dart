/// A whitelisted local repository the phone may drive Claude Code against
/// (`GET /api/code/projects`). The allow-list is configured server-side in
/// `~/.hermes/config.yaml` under `claude_code.projects` — the phone can only
/// ever touch these directories.
class CodeProject {
  const CodeProject({
    required this.name,
    required this.path,
    required this.isRepo,
    this.branch,
    this.dirty = 0,
  });

  final String name;
  final String path;
  final bool isRepo;
  final String? branch;

  /// Number of changed entries in the working tree (porcelain lines).
  final int dirty;

  bool get isDirty => dirty > 0;

  factory CodeProject.fromJson(Map<String, dynamic> json) {
    final git = (json['git'] as Map<String, dynamic>?) ?? const {};
    return CodeProject(
      name: (json['name'] as String?) ?? '(unnamed)',
      path: (json['path'] as String?) ?? '',
      isRepo: (git['is_repo'] as bool?) ?? false,
      branch: git['branch'] as String?,
      dirty: (git['dirty'] as num?)?.toInt() ?? 0,
    );
  }
}
