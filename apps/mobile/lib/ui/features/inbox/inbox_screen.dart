import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/email_repository.dart';
import '../../../data/services/notification_service.dart';
import '../../../domain/models/email_message.dart';
import '../../core/animations.dart';
import '../../core/atl_theme.dart';
import '../chat/view_models/chat_view_model.dart';
import '../email/email_detail_screen.dart';
import '../email/email_view_model.dart';
import '../shell/shell_controller.dart';

/// Unified inbox: unread email (tap → read + AI reply) plus live activity
/// (ntfy pushes: reminders, new-mail alerts, briefings). The filter chips are
/// functional and the whole feed pull-to-refreshes.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

enum _Filter { all, unread, read, alerts }

class _InboxScreenState extends State<InboxScreen> {
  _Filter _filterSel = _Filter.all;
  NotificationService? _notifications;
  int _lastInboxLength = 0;
  final TextEditingController _searchCtrl = TextEditingController();
  bool _digestMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<EmailViewModel>().loadIfNeeded();
        _notifications = context.read<NotificationService>();
        _lastInboxLength = _notifications?.inbox.length ?? 0;
        _notifications?.addListener(_onNotificationsChanged);
      }
    });
  }

  void _onNotificationsChanged() {
    if (!mounted) return;
    final count = _notifications?.inbox.length ?? 0;
    if (count > _lastInboxLength) {
      _lastInboxLength = count;
      context.read<EmailViewModel>().load();
    }
  }

  @override
  void dispose() {
    _notifications?.removeListener(_onNotificationsChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() => context.read<EmailViewModel>().load();

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    final email = context.watch<EmailViewModel>();
    final alerts = context.watch<NotificationService>().inbox;

    final showEmail = _filterSel == _Filter.all || _filterSel == _Filter.unread || _filterSel == _Filter.read;
    final showAlerts = _filterSel == _Filter.all || _filterSel == _Filter.alerts;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Inbox', style: atlSerif(size: 30, color: atl.text)),
              Row(
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _digestMode = !_digestMode),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _digestMode ? atl.accentSoft : atl.surface2,
                        borderRadius: BorderRadius.circular(20),
                        border: _digestMode ? Border.all(color: atl.accent) : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _digestMode ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                            size: 13,
                            color: _digestMode ? atl.accent : atl.text2,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Smart Digest',
                            style: atlSans(
                              size: 12,
                              color: _digestMode ? atl.accent : atl.text2,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_filterSel != _Filter.read && email.unreadCount > 0)
                    GestureDetector(
                      onTap: () {
                        email.markAllRead();
                      },
                      child: Container(
                         margin: const EdgeInsets.only(right: 8),
                         padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                         decoration: BoxDecoration(
                           color: atl.accentSoft,
                           borderRadius: BorderRadius.circular(20),
                           border: Border.all(color: atl.accent),
                         ),
                         child: Text('Mark all read',
                             style: atlSans(size: 12, color: atl.accent, weight: FontWeight.w600)),
                      ),
                    ),
                  if (email.unreadCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: atl.surface2,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('${email.unreadCount} unread',
                          style: atlSans(size: 12, color: atl.text2, weight: FontWeight.w600)),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _filterChip(atl, 'All', _Filter.all),
              const SizedBox(width: 8),
              _filterChip(atl, 'Unread Mails', _Filter.unread),
              const SizedBox(width: 8),
              _filterChip(atl, 'Read Mails', _Filter.read),
              const SizedBox(width: 8),
              _filterChip(atl, 'Alerts', _Filter.alerts),
            ],
          ),
          const SizedBox(height: 20),

          // Search Bar
          if (showEmail && !email.notConnected) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: atl.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: atl.hairline),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(Icons.search, size: 20, color: atl.text3),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      style: atlSans(size: 14, color: atl.text),
                      decoration: InputDecoration(
                        hintText: _filterSel == _Filter.read ? 'Search read email...' : 'Search unread email...',
                        hintStyle: atlSans(size: 14, color: atl.text3),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onChanged: (val) {
                        setState(() {});
                        context.read<EmailViewModel>().setSearchQuery(val);
                      },
                    ),
                  ),
                  if (_searchCtrl.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _searchCtrl.clear();
                        setState(() {});
                        context.read<EmailViewModel>().setSearchQuery('');
                      },
                      child: Icon(Icons.clear, size: 18, color: atl.text2),
                    ),
                ],
              ),
            ),
          ],

          // Email section
          if (showEmail) ...[
            if (email.loading && email.messages.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (email.notConnected)
              _connectEmailCard(atl)
            else if (email.messages.isNotEmpty) ...[
              if (_digestMode) ...[
                _label(atl, 'Smart Category Digests'),
                for (final entry in email.categoryDigests.entries)
                  _categoryCard(atl, entry.key, entry.value),
              ] else ...[
                _label(atl, _filterSel == _Filter.read
                    ? 'Read Mails'
                    : _filterSel == _Filter.unread
                        ? 'Unread Mails'
                        : 'All Mails'),
                for (final m in email.messages)
                  FadeInUp(
                    key: ValueKey(m.id),
                    duration: const Duration(milliseconds: 260),
                    child: _emailCard(atl, m),
                  ),
              ],
              const SizedBox(height: 8),
            ] else if (_filterSel == _Filter.unread)
              _emptyHint(atl, 'No unread email. You’re all caught up.')
            else if (_filterSel == _Filter.read)
              _emptyHint(atl, 'No read email found.'),
          ],

          // Alerts section (ntfy activity)
          if (showAlerts) ...[
            if (alerts.isNotEmpty) ...[
              _label(atl, 'Activity'),
              for (final n in alerts) _alertCard(atl, n),
            ] else if (_filterSel == _Filter.alerts)
              _emptyHint(atl, 'No activity yet. Reminders and alerts land here.'),
          ],
        ],
      ),
    );
  }

  Widget _filterChip(AtlColors atl, String label, _Filter value) {
    final active = _filterSel == value;
    return GestureDetector(
      onTap: () {
        if (_filterSel != value) {
          setState(() {
            _filterSel = value;
            _searchCtrl.clear();
          });
          final emailVM = context.read<EmailViewModel>();
          emailVM.setSearchQuery('');
          if (value == _Filter.all) {
            emailVM.setTabIndex(0);
          } else if (value == _Filter.unread) {
            emailVM.setTabIndex(1);
          } else if (value == _Filter.read) {
            emailVM.setTabIndex(2);
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? atl.accent : atl.surface2,
          borderRadius: BorderRadius.circular(20),
          border: active ? null : Border.all(color: atl.hairline),
        ),
        child: Text(label,
            style: atlSans(
                size: 12,
                color: active ? atl.accentInk : atl.text2,
                weight: active ? FontWeight.w600 : FontWeight.w500)),
      ),
    );
  }

  Widget _label(AtlColors atl, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Text(text.toUpperCase(),
            style: atlSans(
                size: 12, color: atl.text2, weight: FontWeight.w600, letterSpacing: 1)),
      );

  Widget _emailCard(AtlColors atl, EmailMessage m) => Pressable(
        onTap: () => openEmail(context, m),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: atl.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: atl.hairline),
            boxShadow: atl.cardShadow,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: atl.accentSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  (m.from.display.isNotEmpty ? m.from.display[0] : '?').toUpperCase(),
                  style: atlSans(size: 15, color: atl.accent, weight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(m.from.display,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: atlSans(
                                  size: 14,
                                  color: atl.text,
                                  weight: m.unread ? FontWeight.w700 : FontWeight.w500)),
                        ),
                        if (m.unread)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: atl.accent),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(m.subjectOrNoSubject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: atlSans(
                            size: 14,
                            color: atl.text,
                            weight: m.unread ? FontWeight.w600 : FontWeight.w400)),
                    const SizedBox(height: 3),
                    Text(m.snippet,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: atlSans(size: 13, color: atl.text2, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _alertCard(AtlColors atl, InboxItem n) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: atl.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: atl.hairline),
          boxShadow: atl.cardShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: atl.accentSoft,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(Icons.notifications_none, size: 18, color: atl.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.title,
                      style: atlSans(size: 15, color: atl.text, weight: FontWeight.w600)),
                  if (n.message.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(n.message, style: atlSans(size: 13, color: atl.text2, height: 1.4)),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  Widget _connectEmailCard(AtlColors atl) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: atl.surface2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: atl.hairline),
        ),
        child: Row(
          children: [
            Icon(Icons.mark_email_unread_outlined, size: 22, color: atl.text3),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Email not connected',
                      style: atlSans(size: 14, color: atl.text, weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('Add EMAIL_ADDRESS + an App Password to ~/.hermes/.env on your Mac to see mail here.',
                      style: atlSans(size: 12, color: atl.text3)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _emptyHint(AtlColors atl, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(text,
              textAlign: TextAlign.center, style: atlSans(size: 14, color: atl.text3)),
        ),
      );

  Widget _categoryCard(AtlColors atl, String categoryName, List<EmailMessage> list) {
    final email = context.read<EmailViewModel>();
    final unreadCount = list.where((m) => m.unread).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: atl.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: atl.hairline),
        boxShadow: atl.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      categoryName,
                      style: atlSans(size: 15, color: atl.text, weight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: unreadCount > 0 ? atl.accentSoft : atl.surface2,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${list.length} mail${list.length > 1 ? 's' : ''}',
                        style: atlSans(
                          size: 11,
                          color: unreadCount > 0 ? atl.accent : atl.text3,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  if (unreadCount > 0)
                    GestureDetector(
                      onTap: () => email.markCategoryRead(list),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: atl.accentSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Mark Read',
                          style: atlSans(size: 11, color: atl.accent, weight: FontWeight.w600),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _requestCategoryDigest(categoryName, list),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: atl.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: atl.hairline),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, size: 10, color: atl.text2),
                          const SizedBox(width: 4),
                          Text(
                            'AI Digest',
                            style: atlSans(size: 11, color: atl.text2, weight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: list.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: atl.divider),
            itemBuilder: (context, idx) {
              final m = list[idx];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    if (m.unread)
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(shape: BoxShape.circle, color: atl.accent),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  m.from.display,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: atlSans(
                                    size: 13,
                                    color: atl.text,
                                    weight: m.unread ? FontWeight.w600 : FontWeight.w400,
                                  ),
                                ),
                              ),
                              Text(
                                m.date,
                                style: atlSans(size: 11, color: atl.text3),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            m.subjectOrNoSubject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: atlSans(
                              size: 13,
                              color: atl.text2,
                              weight: m.unread ? FontWeight.w500 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            m.unread ? Icons.check_circle_outline : Icons.check_circle,
                            size: 18,
                            color: m.unread ? atl.text3 : atl.accent,
                          ),
                          onPressed: () {
                            if (m.unread) {
                              email.markReadLocally(m.id);
                              context.read<EmailRepository>().markRead(m.id);
                            }
                          },
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                        IconButton(
                          icon: Icon(Icons.arrow_forward_ios, size: 12, color: atl.text3),
                          onPressed: () => openEmail(context, m),
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _requestCategoryDigest(String category, List<EmailMessage> emails) {
    final emailSummaryLines = emails.map((m) => "- From: ${m.from.display}, Subject: ${m.subjectOrNoSubject}, Snippet: ${m.snippet}").join('\n');
    final prompt = "Summarize my '$category' emails into a clean digest brief:\n$emailSummaryLines";
    context.read<ShellController>().go(AtlTab.chat);
    context.read<ChatViewModel>().sendText(prompt);
  }
}
