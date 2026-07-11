import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/services/notification_service.dart';
import '../../../domain/models/email_message.dart';
import '../../core/animations.dart';
import '../../core/atl_theme.dart';
import '../email/email_detail_screen.dart';
import '../email/email_view_model.dart';

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
}
