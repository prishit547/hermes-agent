import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/services/notification_service.dart';
import '../../mcp/mcp_screen.dart';
import '../email_settings_screen.dart';
import '../model_switcher.dart';
import '../view_models/settings_view_model.dart';

/// Connection settings / onboarding. Collects the Tailscale server URL and the
/// gateway `API_SERVER_KEY`, and can test `/health` before saving.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.isOnboarding = false});

  /// When true (first launch, nothing configured) the back button is hidden
  /// and the copy nudges the user to enter a server.
  final bool isOnboarding;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();
    final notificationService = context.watch<NotificationService>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !isOnboarding,
        title: Text(isOnboarding ? 'Connect to Hermes' : 'Settings'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (isOnboarding) ...[
              Text(
                'Point the app at your Hermes gateway. Over Tailscale this is '
                'your Mac’s tailnet address and the gateway API port.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
            ],
            TextField(
              controller:
                  TextEditingController.fromValue(_valueOf(vm.userName)),
              onChanged: vm.setUserName,
              autocorrect: false,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Your name',
                hintText: 'Shown in the Today greeting',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller:
                  TextEditingController.fromValue(_valueOf(vm.baseUrl)),
              onChanged: vm.setBaseUrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Server URL',
                hintText: 'http://100.x.y.z:8642',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller:
                  TextEditingController.fromValue(_valueOf(vm.apiKey)),
              onChanged: vm.setApiKey,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'API key (API_SERVER_KEY)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 28),
            Text('Notifications (ntfy)',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'For reminders and briefings. Must match the gateway’s '
              'NTFY_SERVER_URL and NTFY_HOME_CHANNEL.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller:
                  TextEditingController.fromValue(_valueOf(vm.ntfyServer)),
              onChanged: vm.setNtfyServer,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'ntfy server',
                hintText: 'https://ntfy.sh',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller:
                  TextEditingController.fromValue(_valueOf(vm.ntfyTopic)),
              onChanged: vm.setNtfyTopic,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'ntfy topic',
                hintText: 'hermes-xxxxxxxx',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _NtfyConnectionStatus(
              hasNtfy: vm.ntfyServer.isNotEmpty && vm.ntfyTopic.isNotEmpty,
              isConnected: notificationService.isConnected,
            ),
            const SizedBox(height: 8),
            _ProbeBanner(probe: vm.probe),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: vm.probe == ConnectionProbe.testing
                        ? null
                        : vm.testConnection,
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Test'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      await vm.save();
                      if (context.mounted && !isOnboarding) {
                        Navigator.of(context).pop();
                      }
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save'),
                  ),
                ),
              ],
            ),
            if (!isOnboarding) ...[
              const SizedBox(height: 28),
              Text('Agent', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.memory),
                      title: const Text('Model'),
                      subtitle: const Text('Switch the AI model'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => openModelSwitcher(context),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.extension_outlined),
                      title: const Text('MCP Servers'),
                      subtitle: const Text('Add and manage tool servers'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => openMcpScreen(context),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.mail_outline),
                      title: const Text('Email'),
                      subtitle: const Text('Connect Gmail (App Password)'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => openEmailSettings(context),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Keeps the cursor at the end while the field reflects the VM value.
  TextEditingValue _valueOf(String text) => TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
}

class _ProbeBanner extends StatelessWidget {
  const _ProbeBanner({required this.probe});
  final ConnectionProbe probe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (probe) {
      ConnectionProbe.idle => const SizedBox.shrink(),
      ConnectionProbe.testing => Row(
          children: const [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Testing connection…'),
          ],
        ),
      ConnectionProbe.ok => _StatusRow(
          icon: Icons.check_circle,
          color: scheme.primary,
          text: 'Connected — gateway reachable.',
        ),
      ConnectionProbe.failed => _StatusRow(
          icon: Icons.error_outline,
          color: scheme.error,
          text: 'Could not reach the gateway. Check URL, key, and Tailscale.',
        ),
    };
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.color,
    required this.text,
  });
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: color))),
      ],
    );
  }
}

class _NtfyConnectionStatus extends StatelessWidget {
  const _NtfyConnectionStatus({required this.hasNtfy, required this.isConnected});
  final bool hasNtfy;
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    if (!hasNtfy) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final color = isConnected ? const Color(0xFF1EA88A) : scheme.error;
    final text = isConnected
        ? 'ntfy: Connected'
        : 'ntfy: Disconnected (waiting for connection or settings save)';
    final icon = isConnected ? Icons.cloud_done_outlined : Icons.cloud_off_outlined;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isConnected ? const Color(0x1F7FEBD0) : scheme.errorContainer.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isConnected ? const Color(0x4D7FEBD0) : scheme.error.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: isConnected ? color : scheme.onErrorContainer,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
