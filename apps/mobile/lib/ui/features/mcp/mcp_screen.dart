import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/system_repository.dart';
import '../../../domain/models/mcp_server.dart';
import '../../core/animations.dart';
import '../../core/atl_theme.dart';

/// Opens the MCP management page.
Future<void> openMcpScreen(BuildContext context) {
  final repo = context.read<SystemRepository>();
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => Provider.value(value: repo, child: const McpScreen()),
    ),
  );
}

/// Manage MCP servers: list, enable/disable, test connection, delete, and add.
/// Changes are written to config.yaml and apply to new sessions (restart the
/// gateway to reload a running server).
class McpScreen extends StatefulWidget {
  const McpScreen({super.key});

  @override
  State<McpScreen> createState() => _McpScreenState();
}

class _McpScreenState extends State<McpScreen> {
  late Future<List<McpServer>> _future;
  final Map<String, String> _testResult = {}; // name -> status line
  String? _busy;

  @override
  void initState() {
    super.initState();
    _future = context.read<SystemRepository>().listMcp();
  }

  void _reload() {
    setState(() => _future = context.read<SystemRepository>().listMcp());
  }

  Future<void> _toggle(McpServer s) async {
    setState(() => _busy = s.name);
    try {
      await context.read<SystemRepository>().setMcpEnabled(s.name, !s.enabled);
      _reload();
    } catch (e) {
      _snack('Toggle failed: $e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _test(McpServer s) async {
    setState(() {
      _busy = s.name;
      _testResult[s.name] = 'Testing…';
    });
    try {
      final res = await context.read<SystemRepository>().testMcp(s.name);
      final ok = res['ok'] == true;
      final tools = (res['tools'] as List?)?.length ?? 0;
      setState(() => _testResult[s.name] =
          ok ? '✓ Connected · $tools tools' : '✗ ${res['error'] ?? 'Failed'}');
    } catch (e) {
      setState(() => _testResult[s.name] = '✗ $e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _delete(McpServer s) async {
    final repo = context.read<SystemRepository>();
    final ok = await _confirm('Remove "${s.name}"?');
    if (!ok || !mounted) return;
    try {
      await repo.deleteMcp(s.name);
      _reload();
    } catch (e) {
      _snack('Delete failed: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _confirm(String message) async {
    final atl = context.atl;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: atl.surface,
            content: Text(message, style: atlSans(size: 15, color: atl.text)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    return Container(
      decoration: BoxDecoration(gradient: atl.appBg),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: atl.text,
          title: Text('MCP Servers', style: atlSans(size: 18, color: atl.text, weight: FontWeight.w600)),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showAddSheet(atl),
          backgroundColor: atl.accent,
          foregroundColor: atl.accentInk,
          icon: const Icon(Icons.add),
          label: Text('Add', style: atlSans(size: 14, color: atl.accentInk, weight: FontWeight.w600)),
        ),
        body: SafeArea(
          top: false,
          child: FutureBuilder<List<McpServer>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(strokeWidth: 2));
              }
              if (snap.hasError) {
                return _errorState(atl, '${snap.error}');
              }
              final servers = snap.data ?? const [];
              if (servers.isEmpty) return _emptyState(atl);
              return ListView(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 90),
                children: [
                  Text('Applies to new sessions · restart the gateway to reload a running server',
                      style: atlSans(size: 12, color: atl.text3)),
                  const SizedBox(height: 12),
                  for (final s in servers) _serverCard(atl, s),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _serverCard(AtlColors atl, McpServer s) {
    final busy = _busy == s.name;
    final result = _testResult[s.name];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: atl.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: atl.hairline),
        boxShadow: atl.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: atl.surface2,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(s.transport,
                    style: atlSans(size: 10, color: atl.text2, weight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s.name,
                    style: atlSans(size: 16, color: atl.text, weight: FontWeight.w600)),
              ),
              Switch.adaptive(
                value: s.enabled,
                onChanged: busy ? null : (_) => _toggle(s),
                activeThumbColor: atl.accent,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(s.target,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: atlMono(size: 12, color: atl.text3)),
          if (result != null) ...[
            const SizedBox(height: 8),
            Text(result,
                style: atlSans(
                    size: 12,
                    color: result.startsWith('✓') ? const Color(0xFF1EA88A) : atl.text2)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              _actionBtn(atl, Icons.wifi_tethering, 'Test', busy ? null : () => _test(s)),
              const SizedBox(width: 10),
              _actionBtn(atl, Icons.delete_outline, 'Remove', () => _delete(s), danger: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(AtlColors atl, IconData icon, String label, VoidCallback? onTap,
          {bool danger = false}) =>
      Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: atl.surface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: atl.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: danger ? AtlColors.danger : atl.text2),
              const SizedBox(width: 5),
              Text(label,
                  style: atlSans(
                      size: 12, color: danger ? AtlColors.danger : atl.text2, weight: FontWeight.w500)),
            ],
          ),
        ),
      );

  void _showAddSheet(AtlColors atl) {
    final nameC = TextEditingController();
    final urlC = TextEditingController();
    bool submitting = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: atl.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              border: Border(top: BorderSide(color: atl.divider)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add HTTP MCP server',
                    style: atlSerif(size: 22, color: atl.text)),
                const SizedBox(height: 4),
                Text('Adds an HTTP/SSE server. stdio (command) servers are best added from the desktop.',
                    style: atlSans(size: 12, color: atl.text3)),
                const SizedBox(height: 16),
                _field(atl, nameC, 'Name', 'e.g. github'),
                const SizedBox(height: 12),
                _field(atl, urlC, 'URL', 'https://mcp.example.com/mcp'),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: Pressable(
                    onTap: submitting
                        ? null
                        : () async {
                            final name = nameC.text.trim();
                            final url = urlC.text.trim();
                            if (name.isEmpty || url.isEmpty) return;
                            setSheet(() => submitting = true);
                            try {
                              await context.read<SystemRepository>().addMcp(name: name, url: url);
                              if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                              _reload();
                            } catch (e) {
                              setSheet(() => submitting = false);
                              _snack('Add failed: $e');
                            }
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AtlColors.halo1, AtlColors.halo2, AtlColors.halo3],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: submitting
                          ? const SizedBox(
                              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text('Add server',
                              style: atlSans(
                                  size: 15, color: const Color(0xFF0A0A14), weight: FontWeight.w600)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(AtlColors atl, TextEditingController c, String label, String hint) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: atlSans(size: 12, color: atl.text2, weight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: c,
            style: atlSans(size: 15, color: atl.text),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: atlSans(size: 14, color: atl.text3),
              filled: true,
              fillColor: atl.surface2,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: atl.fieldBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: atl.fieldBorder),
              ),
            ),
          ),
        ],
      );

  Widget _emptyState(AtlColors atl) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.extension_outlined, size: 42, color: atl.text3),
              const SizedBox(height: 12),
              Text('No MCP servers', style: atlSans(size: 16, color: atl.text, weight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('Add one with the button below.',
                  textAlign: TextAlign.center, style: atlSans(size: 13, color: atl.text3)),
            ],
          ),
        ),
      );

  Widget _errorState(AtlColors atl, String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 38, color: atl.text3),
              const SizedBox(height: 12),
              Text('Could not load MCP servers',
                  style: atlSans(size: 15, color: atl.text, weight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(msg, textAlign: TextAlign.center, style: atlSans(size: 12, color: atl.text3)),
            ],
          ),
        ),
      );
}
