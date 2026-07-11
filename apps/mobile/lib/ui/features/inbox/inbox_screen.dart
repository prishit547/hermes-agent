import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/services/notification_service.dart';
import '../../core/atl_theme.dart';

/// Unified feed: live ntfy pushes plus sample activity items. Reads
/// [NotificationService.inbox] so real reminders/briefings appear as they land.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    final notifications = context.watch<NotificationService>().inbox;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Text('Inbox', style: atlSerif(size: 30, color: atl.text)),
        const SizedBox(height: 14),
        Row(
          children: [
            _filter(atl, 'All', active: true),
            const SizedBox(width: 8),
            _filter(atl, 'Actionable'),
            const SizedBox(width: 8),
            _filter(atl, 'Activity'),
          ],
        ),
        const SizedBox(height: 20),

        if (notifications.isNotEmpty) ...[
          _label(atl, 'Today'),
          for (final n in notifications)
            _card(
              atl,
              icon: Icons.notifications_none,
              iconColor: atl.accent,
              iconBg: atl.accentSoft,
              title: n.title,
              body: n.message,
              unread: true,
            ),
          const SizedBox(height: 8),
        ] else ...[
          _label(atl, 'Today'),
          _actionableCard(atl),
          _card(
            atl,
            icon: Icons.brightness_2_outlined,
            iconColor: atl.accent,
            iconBg: atl.accentSoft,
            title: 'Ran your morning briefing',
            body: 'Summarised 3 events and the weather · 7:00 AM',
          ),
          const SizedBox(height: 8),
          _label(atl, 'Earlier'),
          _card(
            atl,
            icon: Icons.event_available_outlined,
            iconColor: const Color(0xFF1EA88A),
            iconBg: const Color(0x247FEBD0),
            title: 'Created event "Dentist"',
            body: 'From your voice note · yesterday',
          ),
        ],
      ],
    );
  }

  Widget _label(AtlColors atl, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Text(text.toUpperCase(),
            style: atlSans(
                size: 12, color: atl.text2, weight: FontWeight.w600, letterSpacing: 1)),
      );

  Widget _filter(AtlColors atl, String label, {bool active = false}) => Container(
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
      );

  Widget _card(
    AtlColors atl, {
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String body,
    bool unread = false,
  }) =>
      Container(
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
                color: iconBg,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: atlSans(size: 15, color: atl.text, weight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(body, style: atlSans(size: 13, color: atl.text2, height: 1.4)),
                ],
              ),
            ),
            if (unread) ...[
              const SizedBox(width: 8),
              Container(
                margin: const EdgeInsets.only(top: 5),
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: atl.accent),
              ),
            ],
          ],
        ),
      );

  Widget _actionableCard(AtlColors atl) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: atl.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: atl.hairline),
          boxShadow: atl.cardShadow,
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0x29F4A9D6),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.schedule, size: 18, color: Color(0xFFE86FB0)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Leave in 15 min for the dentist',
                          style: atlSans(size: 15, color: atl.text, weight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text('Traffic is light — 8 min drive.',
                          style: atlSans(size: 13, color: atl.text2)),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 5),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: atl.accent),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: atl.accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('Navigate',
                        style: atlSans(size: 13, color: atl.accentInk, weight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: atl.surface2,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: atl.hairline),
                    ),
                    child: Text('Snooze',
                        style: atlSans(size: 13, color: atl.text, weight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}
