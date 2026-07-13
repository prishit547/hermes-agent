import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/services/notification_service.dart';
import '../../../core/animations.dart';
import '../../../core/atl_theme.dart';
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
    final atl = context.atl;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !isOnboarding,
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          isOnboarding ? 'Connect to Hermes' : 'Settings',
          style: atlSerif(size: 26, color: atl.text),
        ),
        iconTheme: IconThemeData(color: atl.text),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: atl.appBg),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            children: [
              if (isOnboarding) ...[
                Text(
                  'Point the app at your Hermes gateway. Over Tailscale this is '
                  'your Mac’s tailnet address and the gateway API port.',
                  style: atlSans(size: 14, color: atl.text2, height: 1.4),
                ),
                const SizedBox(height: 24),
              ],

              // Section 1: User Profile
              _settingsSection(
                title: 'User Profile',
                atl: atl,
                children: [
                  _settingsTextField(
                    label: 'Your Name',
                    hintText: 'Shown in the Today greeting',
                    controller: TextEditingController.fromValue(_valueOf(vm.userName)),
                    onChanged: vm.setUserName,
                    atl: atl,
                  ),
                ],
              ),

              // Section 2: Gateway Connection
              _settingsSection(
                title: 'Gateway Connection',
                subtitle: 'Connection details for your Hermes server.',
                atl: atl,
                children: [
                  _settingsTextField(
                    label: 'Server URL',
                    hintText: 'http://100.x.y.z:8642',
                    controller: TextEditingController.fromValue(_valueOf(vm.baseUrl)),
                    onChanged: vm.setBaseUrl,
                    keyboardType: TextInputType.url,
                    atl: atl,
                  ),
                  const SizedBox(height: 16),
                  _settingsTextField(
                    label: 'API Key (API_SERVER_KEY)',
                    hintText: 'Enter API Server Key',
                    controller: TextEditingController.fromValue(_valueOf(vm.apiKey)),
                    onChanged: vm.setApiKey,
                    obscureText: true,
                    atl: atl,
                  ),
                ],
              ),

              // Section 3: Notifications
              _settingsSection(
                title: 'Real-time Notifications (ntfy)',
                subtitle: 'Used for reminders, briefings, and push messages.',
                atl: atl,
                children: [
                  _settingsTextField(
                    label: 'ntfy Server',
                    hintText: 'https://ntfy.sh',
                    controller: TextEditingController.fromValue(_valueOf(vm.ntfyServer)),
                    onChanged: vm.setNtfyServer,
                    keyboardType: TextInputType.url,
                    atl: atl,
                  ),
                  const SizedBox(height: 16),
                  _settingsTextField(
                    label: 'ntfy Topic',
                    hintText: 'hermes-xxxxxxxx',
                    controller: TextEditingController.fromValue(_valueOf(vm.ntfyTopic)),
                    onChanged: vm.setNtfyTopic,
                    atl: atl,
                  ),
                  const SizedBox(height: 16),
                  _NtfyConnectionStatus(
                    hasNtfy: vm.ntfyServer.isNotEmpty && vm.ntfyTopic.isNotEmpty,
                    isConnected: notificationService.isConnected,
                  ),
                ],
              ),

              // Status and actions
              if (vm.probe != ConnectionProbe.idle) ...[
                _ProbeBanner(probe: vm.probe),
                const SizedBox(height: 16),
              ],

              Row(
                children: [
                  Expanded(
                    child: Pressable(
                      onTap: vm.probe == ConnectionProbe.testing
                          ? null
                          : vm.testConnection,
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: atl.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: atl.hairline),
                          boxShadow: atl.cardShadow,
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.wifi_tethering, size: 18, color: atl.text),
                            const SizedBox(width: 8),
                            Text(
                              'Test Connection',
                              style: atlSans(size: 14, color: atl.text, weight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Pressable(
                      onTap: () async {
                        await vm.save();
                        if (context.mounted && !isOnboarding) {
                          Navigator.of(context).pop();
                        }
                      },
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AtlColors.halo1, AtlColors.halo2, AtlColors.halo3],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: atl.cardShadow,
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.save_outlined, size: 18, color: Color(0xFF0A0A14)),
                            const SizedBox(width: 8),
                            Text(
                              'Save Settings',
                              style: atlSans(size: 14, color: const Color(0xFF0A0A14), weight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              if (!isOnboarding) ...[
                const SizedBox(height: 28),
                Text(
                  'AGENT CONFIGURATION',
                  style: atlSans(size: 12, color: atl.text2, weight: FontWeight.w600, letterSpacing: 1),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: atl.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: atl.hairline),
                    boxShadow: atl.cardShadow,
                  ),
                  child: Column(
                    children: [
                      _agentTile(
                        icon: Icons.memory,
                        title: 'Model',
                        subtitle: 'Switch the active AI model',
                        onTap: () => openModelSwitcher(context),
                        atl: atl,
                      ),
                      Divider(color: atl.hairline, height: 1),
                      _agentTile(
                        icon: Icons.extension_outlined,
                        title: 'MCP Servers',
                        subtitle: 'Add and manage tool servers',
                        onTap: () => openMcpScreen(context),
                        atl: atl,
                      ),
                      Divider(color: atl.hairline, height: 1),
                      _agentTile(
                        icon: Icons.mail_outline,
                        title: 'Email Settings',
                        subtitle: 'Connect Gmail (App Password)',
                        onTap: () => openEmailSettings(context),
                        atl: atl,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Keeps the cursor at the end while the field reflects the VM value.
  TextEditingValue _valueOf(String text) => TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );

  Widget _settingsSection({
    required String title,
    String? subtitle,
    required List<Widget> children,
    required AtlColors atl,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: atl.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: atl.hairline),
        boxShadow: atl.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: atlSans(size: 15, color: atl.text, weight: FontWeight.w700),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: atlSans(size: 12, color: atl.text3),
            ),
          ],
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }

  Widget _settingsTextField({
    required String label,
    required String hintText,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    required AtlColors atl,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: atlSans(size: 13, color: atl.text2, weight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: atl.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: atl.hairline),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            obscureText: obscureText,
            keyboardType: keyboardType,
            style: atlSans(size: 15, color: atl.text),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: hintText,
              hintStyle: atlSans(size: 15, color: atl.text3),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _agentTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required AtlColors atl,
  }) {
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: atl.surface2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: atl.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: atlSans(size: 15, color: atl.text, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: atlSans(size: 12, color: atl.text2),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: atl.text3),
          ],
        ),
      ),
    );
  }
}

class _ProbeBanner extends StatelessWidget {
  const _ProbeBanner({required this.probe});
  final ConnectionProbe probe;

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    return switch (probe) {
      ConnectionProbe.idle => const SizedBox.shrink(),
      ConnectionProbe.testing => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: atl.accentSoft,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: atl.accent.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: atl.accent),
              ),
              const SizedBox(width: 9),
              Text(
                'Testing connection…',
                style: atlSans(size: 13, color: atl.text2, weight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ConnectionProbe.ok => _StatusRow(
          icon: Icons.check_circle,
          color: AtlColors.positive,
          text: 'Connected — gateway reachable.',
        ),
      ConnectionProbe.failed => _StatusRow(
          icon: Icons.error_outline,
          color: AtlColors.danger,
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: atlSans(size: 13, color: color, weight: FontWeight.w500),
            ),
          ),
        ],
      ),
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
    final color = isConnected ? AtlColors.positive : AtlColors.danger;
    final text = isConnected
        ? 'ntfy: Connected'
        : 'ntfy: Disconnected (waiting for connection or settings save)';
    final icon = isConnected ? Icons.cloud_done_outlined : Icons.cloud_off_outlined;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: atlSans(
                color: color,
                size: 13,
                weight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
