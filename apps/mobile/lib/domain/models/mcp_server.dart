/// One configured MCP server (from `GET /api/mcp/servers`). Secret env values
/// are already masked by the server.
class McpServer {
  const McpServer({
    required this.name,
    this.transport = 'unknown',
    this.url,
    this.command,
    this.args = const [],
    this.env = const {},
    this.auth,
    this.enabled = true,
  });

  final String name;
  final String transport; // http | stdio | unknown
  final String? url;
  final String? command;
  final List<String> args;
  final Map<String, String> env;
  final String? auth;
  final bool enabled;

  /// Short one-line descriptor of how this server connects.
  String get target {
    if (url != null && url!.isNotEmpty) return url!;
    if (command != null && command!.isNotEmpty) {
      return [command!, ...args].join(' ');
    }
    return transport;
  }

  factory McpServer.fromJson(Map<String, dynamic> json) => McpServer(
        name: (json['name'] ?? '').toString(),
        transport: (json['transport'] as String?) ?? 'unknown',
        url: json['url'] as String?,
        command: json['command'] as String?,
        args: (json['args'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        env: (json['env'] as Map<String, dynamic>? ?? const {})
            .map((k, v) => MapEntry(k, v.toString())),
        auth: json['auth'] as String?,
        enabled: json['enabled'] != false,
      );
}
