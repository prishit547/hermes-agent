import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/email_repository.dart';
import '../email/email_view_model.dart';

/// Opens the email-credentials screen.
Future<void> openEmailSettings(BuildContext context) {
  final repo = context.read<EmailRepository>();
  final email = context.read<EmailViewModel>();
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MultiProvider(
        providers: [
          Provider.value(value: repo),
          ChangeNotifierProvider.value(value: email),
        ],
        child: const EmailSettingsScreen(),
      ),
    ),
  );
}

/// Enter the Gmail address + App Password. The password is typed here by the
/// user and stored on the backend (`~/.hermes/.env`); it is never shown back.
class EmailSettingsScreen extends StatefulWidget {
  const EmailSettingsScreen({super.key});

  @override
  State<EmailSettingsScreen> createState() => _EmailSettingsScreenState();
}

class _EmailSettingsScreenState extends State<EmailSettingsScreen> {
  final _address = TextEditingController();
  final _password = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _configured = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _address.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final cfg = await context.read<EmailRepository>().getConfig();
      if (!mounted) return;
      setState(() {
        _address.text = (cfg['address'] ?? '').toString();
        _configured = cfg['configured'] == true;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final addr = _address.text.trim();
    final pw = _password.text.trim();
    if (addr.isEmpty || pw.isEmpty) {
      _snack('Enter your email and App Password');
      return;
    }
    setState(() => _saving = true);
    final repo = context.read<EmailRepository>();
    final emailVm = context.read<EmailViewModel>();
    try {
      await repo.setConfig(address: addr, appPassword: pw);
      await emailVm.load(); // refresh the inbox now that email is connected
      if (!mounted) return;
      _snack('Email connected');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Could not connect: $e');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Email')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  _configured
                      ? 'Email is connected. Re-enter to update the credentials.'
                      : 'Connect your Gmail with an App Password (needs 2-Step Verification). '
                          'IMAP for reading, SMTP for sending — no OAuth needed.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _address,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Email address',
                    hintText: 'you@gmail.com',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'App Password (16 characters)',
                    hintText: _configured ? 'Enter to change' : 'xxxx xxxx xxxx xxxx',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.info_outline, size: 18),
                    label: const Text('Create one at myaccount.google.com/apppasswords'),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.link),
                  label: Text(_saving ? 'Connecting…' : 'Connect email'),
                ),
              ],
            ),
    );
  }
}
