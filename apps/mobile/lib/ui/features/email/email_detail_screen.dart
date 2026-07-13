import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/email_repository.dart';
import '../../../domain/models/email_message.dart';
import '../../core/animations.dart';
import '../../core/atl_theme.dart';
import 'email_view_model.dart';

/// Opens a full email: read it, generate an AI reply, edit, and send.
Future<void> openEmail(BuildContext context, EmailMessage summary) {
  final repo = context.read<EmailRepository>();
  final vm = context.read<EmailViewModel>();
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MultiProvider(
        providers: [
          Provider.value(value: repo),
          ChangeNotifierProvider.value(value: vm),
        ],
        child: EmailDetailScreen(summary: summary),
      ),
    ),
  );
}

class EmailDetailScreen extends StatefulWidget {
  const EmailDetailScreen({super.key, required this.summary});
  final EmailMessage summary;

  @override
  State<EmailDetailScreen> createState() => _EmailDetailScreenState();
}

class _EmailDetailScreenState extends State<EmailDetailScreen> {
  final _reply = TextEditingController();
  EmailMessage? _full;
  bool _loading = true;
  bool _drafting = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final repo = context.read<EmailRepository>();
    try {
      final msg = await repo.get(widget.summary.id);
      if (!mounted) return;
      setState(() {
        _full = msg;
        _loading = false;
      });
      // Mark read in the background + reflect in the list.
      repo.markRead(widget.summary.id).ignore();
      if (mounted) context.read<EmailViewModel>().markReadLocally(widget.summary.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _aiDraft() async {
    final note = _reply.text.trim();
    setState(() => _drafting = true);
    try {
      final text = await context.read<EmailRepository>().aiDraft(
            messageId: widget.summary.id,
            instructions: note.isNotEmpty ? note : null,
          );
      if (!mounted) return;
      setState(() {
        _reply.text = text;
        _drafting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _drafting = false);
      _snack('Could not draft: $e');
    }
  }

  Future<void> _send() async {
    final full = _full;
    if (full == null || _reply.text.trim().isEmpty) return;
    setState(() => _sending = true);
    final subject = full.subject.toLowerCase().startsWith('re:')
        ? full.subject
        : 'Re: ${full.subject}';
    try {
      await context.read<EmailRepository>().send(
            to: full.from.email,
            subject: subject,
            body: _reply.text.trim(),
            threadId: full.threadId,
            inReplyTo: full.messageIdHeader,
          );
      if (!mounted) return;
      _snack('Reply sent to ${full.from.display}');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      _snack('Send failed: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    final s = widget.summary;
    return Container(
      decoration: BoxDecoration(gradient: atl.appBg),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: atl.text,
          title: Text('Email', style: atlSans(size: 18, color: atl.text, weight: FontWeight.w600)),
        ),
        body: SafeArea(
          top: false,
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(30),
                        child: Text('Could not load: $_error',
                            textAlign: TextAlign.center,
                            style: atlSans(size: 14, color: atl.text2)),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
                      children: [
                        Text(_full?.subjectOrNoSubject ?? s.subjectOrNoSubject,
                            style: atlSerif(size: 24, color: atl.text)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: atl.surface2,
                              child: Text(
                                (s.from.display.isNotEmpty ? s.from.display[0] : '?').toUpperCase(),
                                style: atlSans(size: 14, color: atl.text),
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.from.display,
                                      style: atlSans(size: 14, color: atl.text, weight: FontWeight.w600)),
                                  Text(s.from.email,
                                      style: atlSans(size: 12, color: atl.text3)),
                                ],
                              ),
                            ),
                            Text(s.date.length > 16 ? s.date.substring(0, 16) : s.date,
                                style: atlSans(size: 11, color: atl.text3)),
                          ],
                        ),
                        const SizedBox(height: 18),
                        HtmlWidget(
                          _full?.body?.trim().isNotEmpty == true
                              ? _full!.body!.trim()
                              : s.snippet,
                          textStyle: atlSans(size: 15, color: atl.text, height: 1.5),
                        ),
                        const SizedBox(height: 24),
                        Divider(color: atl.divider),
                        const SizedBox(height: 14),
                        _replyComposer(atl),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _replyComposer(AtlColors atl) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Reply', style: atlSans(size: 15, color: atl.text, weight: FontWeight.w700)),
              const Spacer(),
              Pressable(
                onTap: _drafting ? null : _aiDraft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                  decoration: BoxDecoration(
                    color: atl.accentSoft,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: atl.accent),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_drafting)
                        const SizedBox(
                            width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        Icon(Icons.auto_awesome, size: 15, color: atl.accent),
                      const SizedBox(width: 6),
                      Text(_drafting ? 'Drafting…' : 'AI reply',
                          style: atlSans(size: 13, color: atl.accent, weight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: atl.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: atl.fieldBorder),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: TextField(
              controller: _reply,
              minLines: 4,
              maxLines: 12,
              style: atlSans(size: 15, color: atl.text, height: 1.45),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Write a reply, or tap “AI reply” to draft one…',
                hintStyle: atlSans(size: 14, color: atl.text3),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: Pressable(
              onTap: _sending ? null : _send,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AtlColors.halo1, AtlColors.halo2, AtlColors.halo3],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: _sending
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.send, size: 17, color: Color(0xFF0A0A14)),
                          const SizedBox(width: 8),
                          Text('Send reply',
                              style: atlSans(
                                  size: 15, color: const Color(0xFF0A0A14), weight: FontWeight.w600)),
                        ],
                      ),
              ),
            ),
          ),
        ],
      );
}
