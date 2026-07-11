/// Immutable connection configuration for reaching the Hermes api_server.
///
/// The mobile app talks to a single endpoint — the OpenAI-compatible
/// `api_server` (default port 8642) that runs in-process inside the Hermes
/// gateway. Over Tailscale, [baseUrl] is the Mac's tailnet address, e.g.
/// `http://100.101.102.103:8642`. [apiKey] is the gateway's `API_SERVER_KEY`.
class ConnectionSettings {
  const ConnectionSettings({
    required this.baseUrl,
    required this.apiKey,
    this.ntfyServer = 'https://ntfy.sh',
    this.ntfyTopic = '',
  });

  final String baseUrl;
  final String apiKey;

  /// ntfy server + topic for proactive push (reminders, briefings). Must match
  /// the gateway's `NTFY_SERVER_URL` / `NTFY_HOME_CHANNEL`.
  final String ntfyServer;
  final String ntfyTopic;

  /// True once the user has entered a non-empty server URL and key.
  bool get isConfigured => baseUrl.trim().isNotEmpty && apiKey.trim().isNotEmpty;

  /// True when a topic is set, so the notification subscription can start.
  bool get hasNtfy =>
      ntfyServer.trim().isNotEmpty && ntfyTopic.trim().isNotEmpty;

  /// ntfy JSON stream endpoint for the configured topic.
  Uri get ntfyStreamUrl {
    final base = ntfyServer.trim().endsWith('/')
        ? ntfyServer.trim().substring(0, ntfyServer.trim().length - 1)
        : ntfyServer.trim();
    return Uri.parse('$base/${ntfyTopic.trim()}/json');
  }

  /// [baseUrl] with any trailing slash removed, so path joins are clean.
  String get normalizedBaseUrl {
    final trimmed = baseUrl.trim();
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  Uri resolve(String path) => Uri.parse('$normalizedBaseUrl$path');

  /// WebSocket URL for [path], converting the http(s) base to ws(s) and adding
  /// [query] params (e.g. the auth token, which WS handshakes can't put in a
  /// header on mobile).
  Uri resolveWs(String path, {Map<String, String>? query}) {
    final http = Uri.parse('$normalizedBaseUrl$path');
    return http.replace(
      scheme: http.scheme == 'https' ? 'wss' : 'ws',
      queryParameters: {...http.queryParameters, ...?query},
    );
  }

  ConnectionSettings copyWith({
    String? baseUrl,
    String? apiKey,
    String? ntfyServer,
    String? ntfyTopic,
  }) =>
      ConnectionSettings(
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        ntfyServer: ntfyServer ?? this.ntfyServer,
        ntfyTopic: ntfyTopic ?? this.ntfyTopic,
      );

  static const empty = ConnectionSettings(baseUrl: '', apiKey: '');
}
