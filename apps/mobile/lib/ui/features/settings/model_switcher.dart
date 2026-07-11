import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/system_repository.dart';
import '../../core/animations.dart';
import '../../core/atl_theme.dart';

/// Opens the model switcher as a full-screen page.
Future<void> openModelSwitcher(BuildContext context) {
  final repo = context.read<SystemRepository>();
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => Provider.value(value: repo, child: const ModelSwitcherScreen()),
    ),
  );
}

/// Lists authenticated providers and their models, and switches the main model
/// via `POST /api/model/set`. Config is shared, so the change also affects the
/// CLI/dashboard; a running gateway must restart to pick it up.
class ModelSwitcherScreen extends StatefulWidget {
  const ModelSwitcherScreen({super.key});

  @override
  State<ModelSwitcherScreen> createState() => _ModelSwitcherScreenState();
}

class _ModelSwitcherScreenState extends State<ModelSwitcherScreen> {
  late Future<Map<String, dynamic>> _future;
  String? _currentModel;
  String? _currentProvider;
  String? _busyModel;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final repo = context.read<SystemRepository>();
    final payload = await repo.modelOptions();
    _currentModel = payload['model'] as String?;
    _currentProvider = payload['provider'] as String?;
    return payload;
  }

  Future<void> _apply(String provider, String model) async {
    setState(() {
      _busyModel = '$provider/$model';
      _error = null;
    });
    final repo = context.read<SystemRepository>();
    try {
      final res = await repo.setModel(provider: provider, model: model);
      if (res['confirm_required'] == true) {
        final ok = await _confirmExpensive(res['confirm_message'] as String? ?? 'This model may be costly.');
        if (ok) {
          await repo.setModel(provider: provider, model: model, confirmExpensive: true);
        } else {
          setState(() => _busyModel = null);
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _currentModel = model;
        _currentProvider = provider;
        _busyModel = null;
      });
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
            content: Text('Model set to $model — restart the gateway to apply to a running server.')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busyModel = null;
        _error = 'Could not set model: $e';
      });
    }
  }

  Future<bool> _confirmExpensive(String message) async {
    final atl = context.atl;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: atl.surface,
            title: Text('Confirm model', style: atlSans(size: 17, color: atl.text, weight: FontWeight.w700)),
            content: Text(message, style: atlSans(size: 14, color: atl.text2)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Use it')),
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
          title: Text('Model', style: atlSans(size: 18, color: atl.text, weight: FontWeight.w600)),
        ),
        body: SafeArea(
          top: false,
          child: FutureBuilder<Map<String, dynamic>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(strokeWidth: 2));
              }
              if (snap.hasError) {
                return _errorState(atl, '${snap.error}');
              }
              final providers = (snap.data?['providers'] as List<dynamic>? ?? const [])
                  .whereType<Map<String, dynamic>>()
                  .where((p) => p['authenticated'] == true && ((p['models'] as List?)?.isNotEmpty ?? false))
                  .toList();
              return ListView(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
                children: [
                  if (_currentModel != null)
                    _currentCard(atl),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: atlSans(size: 13, color: AtlColors.danger)),
                  ],
                  const SizedBox(height: 8),
                  for (final p in providers) _providerBlock(atl, p),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _currentCard(AtlColors atl) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: atl.accentSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: atl.accent),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: atl.accent, size: 20),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Current model', style: atlSans(size: 12, color: atl.text2)),
                  const SizedBox(height: 2),
                  Text(_currentModel ?? '',
                      style: atlSans(size: 15, color: atl.text, weight: FontWeight.w600)),
                  Text(_currentProvider ?? '', style: atlSans(size: 12, color: atl.text3)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _providerBlock(AtlColors atl, Map<String, dynamic> p) {
    final slug = (p['slug'] ?? '').toString();
    final name = (p['name'] ?? slug).toString();
    final models = (p['models'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList();
    final caps = (p['capabilities'] as Map<String, dynamic>? ?? const {});
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name.toUpperCase(),
              style: atlSans(size: 12, color: atl.text3, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final m in models) _modelTile(atl, slug, m, caps[m] as Map<String, dynamic>?),
        ],
      ),
    );
  }

  Widget _modelTile(AtlColors atl, String provider, String model, Map<String, dynamic>? cap) {
    final active = model == _currentModel && provider == _currentProvider;
    final busy = _busyModel == '$provider/$model';
    final reasoning = cap?['reasoning'] == true;
    return Pressable(
      onTap: busy ? null : () => _apply(provider, model),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: active ? atl.accentSoft : atl.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? atl.accent : atl.hairline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(model,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: atlSans(
                      size: 14,
                      color: atl.text,
                      weight: active ? FontWeight.w600 : FontWeight.w500)),
            ),
            if (reasoning)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.psychology_outlined, size: 16, color: atl.text3),
              ),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (active)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.check, size: 17, color: atl.accent),
              ),
          ],
        ),
      ),
    );
  }

  Widget _errorState(AtlColors atl, String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 38, color: atl.text3),
              const SizedBox(height: 12),
              Text('Could not load models',
                  style: atlSans(size: 15, color: atl.text, weight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(msg, textAlign: TextAlign.center, style: atlSans(size: 12, color: atl.text3)),
            ],
          ),
        ),
      );
}
