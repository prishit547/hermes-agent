import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/services/notification_service.dart';
import '../../../core/animations.dart';
import '../../../core/atl_theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../automations/automations_screen.dart';
import '../../code/code_screen.dart';
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
                  AtlField(
                    label: 'Your Name',
                    hint: 'Shown in the Today greeting',
                    value: vm.userName,
                    onChanged: vm.setUserName,
                    autofillHints: const [AutofillHints.name],
                  ),
                ],
              ),

              // Section 2: Gateway Connection
              _settingsSection(
                title: 'Gateway Connection',
                subtitle: 'Connection details for your Hermes server.',
                atl: atl,
                children: [
                  AtlField(
                    label: 'Server URL',
                    hint: 'http://100.x.y.z:8642',
                    value: vm.baseUrl,
                    onChanged: vm.setBaseUrl,
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: AtlSpace.lg),
                  AtlField(
                    label: 'API Key (API_SERVER_KEY)',
                    hint: 'Enter API Server Key',
                    value: vm.apiKey,
                    onChanged: vm.setApiKey,
                    obscure: true,
                  ),
                ],
              ),

              // Section 3: Notifications
              _settingsSection(
                title: 'Real-time Notifications (ntfy)',
                subtitle: 'Used for reminders, briefings, and push messages.',
                atl: atl,
                children: [
                  AtlField(
                    label: 'ntfy Server',
                    hint: 'https://ntfy.sh',
                    value: vm.ntfyServer,
                    onChanged: vm.setNtfyServer,
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: AtlSpace.lg),
                  AtlField(
                    label: 'ntfy Topic',
                    hint: 'hermes-xxxxxxxx',
                    value: vm.ntfyTopic,
                    onChanged: vm.setNtfyTopic,
                  ),
                  const SizedBox(height: AtlSpace.lg),
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

              if (!isOnboarding && Platform.isAndroid) ...[
                const SizedBox(height: 4),
                const _SystemAssistantSection(),
              ],

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
                        icon: Icons.auto_awesome_outlined,
                        title: 'Automations',
                        subtitle: 'Scheduled routines that run on their own',
                        onTap: () => openAutomationsScreen(context),
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
                        icon: Icons.terminal_rounded,
                        title: 'Atlantic Dev',
                        subtitle: 'Drive Claude Code on your projects',
                        onTap: () => openCodeScreen(context),
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
            border: Border.all(color: atl.accent.withValues(alpha: 0.2)),
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
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
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

/// "System Assistant" card: shows whether Hermes is the phone's default
/// assistant and lets the user set it. Refreshes when the app returns to the
/// foreground (e.g. after the system role dialog / settings screen).
class _SystemAssistantSection extends StatefulWidget {
  const _SystemAssistantSection();

  @override
  State<_SystemAssistantSection> createState() => _SystemAssistantSectionState();
}

class _SystemAssistantSectionState extends State<_SystemAssistantSection>
    with WidgetsBindingObserver {
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<SettingsViewModel>().refreshAssistantStatus();
    }
  }

  Future<void> _setDefault() async {
    setState(() => _requesting = true);
    final vm = context.read<SettingsViewModel>();
    await vm.setAsDefaultAssistant();
    if (mounted) {
      setState(() => _requesting = false);
      if (vm.assistantOpenedSettings && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Choose "Hermes Assistant" in the list, then come back.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();
    final atl = context.atl;
    final isDefault = vm.assistantIsDefault;

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
            'System Assistant',
            style: atlSans(size: 15, color: atl.text, weight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Make Hermes your phone’s default assistant so a long-press of the '
            'home button or the assist gesture opens it anywhere.',
            style: atlSans(size: 12, color: atl.text3),
          ),
          const SizedBox(height: 16),
          _assistantStatusRow(atl, isDefault),
          if (isDefault != true) ...[
            const SizedBox(height: 14),
            Pressable(
              onTap: _requesting ? null : _setDefault,
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
                child: _requesting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF0A0A14),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.assistant_outlined,
                              size: 18, color: Color(0xFF0A0A14)),
                          const SizedBox(width: 8),
                          Text(
                            'Set as default assistant',
                            style: atlSans(
                                size: 14,
                                color: const Color(0xFF0A0A14),
                                weight: FontWeight.w600),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _assistantStatusRow(AtlColors atl, bool? isDefault) {
    if (isDefault == null) {
      return Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: atl.accent),
          ),
          const SizedBox(width: 9),
          Text('Checking assistant status…',
              style: atlSans(size: 13, color: atl.text2, weight: FontWeight.w500)),
        ],
      );
    }
    final color = isDefault ? AtlColors.positive : atl.text2;
    final icon = isDefault ? Icons.check_circle : Icons.info_outline;
    final text = isDefault
        ? 'Hermes is your default assistant.'
        : 'Hermes is not set as the default assistant.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDefault
            ? AtlColors.positive.withValues(alpha: 0.08)
            : atl.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDefault
              ? AtlColors.positive.withValues(alpha: 0.2)
              : atl.hairline,
        ),
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
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
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
