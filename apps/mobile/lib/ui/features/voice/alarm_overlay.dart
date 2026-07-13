import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/services/reminder_service.dart';
import '../../../domain/models/local_reminder.dart';
import '../../core/atl_theme.dart';

class AlarmOverlay extends StatefulWidget {
  const AlarmOverlay({required this.reminder, super.key});

  final LocalReminder reminder;

  @override
  State<AlarmOverlay> createState() => _AlarmOverlayState();
}

class _AlarmOverlayState extends State<AlarmOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  String _fmtTime(DateTime t) {
    final hour = t.hour == 0
        ? 12
        : t.hour > 12
            ? t.hour - 12
            : t.hour;
    final min = t.minute.toString().padLeft(2, '0');
    final amPm = t.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:$min $amPm';
  }

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    final service = context.read<ReminderService>();

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Blurred backdrop
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.75),
                ),
              ),
            ),
          ),
          
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(height: 40),
                
                // Pulsing Alarm Orb & Time
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (context, child) {
                        final val = _pulseCtrl.value;
                        return Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AtlColors.danger.withValues(alpha: 0.15 + 0.1 * val),
                            border: Border.all(
                              color: AtlColors.danger.withValues(alpha: 0.4 + 0.6 * val),
                              width: 2 + 3 * val,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AtlColors.danger.withValues(alpha: 0.2 + 0.3 * val),
                                blurRadius: 30 + 20 * val,
                                spreadRadius: 2 + 6 * val,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.alarm,
                            size: 64,
                            color: Colors.white,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 48),
                    
                    // Alarm Title
                    Text(
                      widget.reminder.title.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: atlSans(
                        size: 14,
                        color: atl.text2,
                        weight: FontWeight.w600,
                        letterSpacing: 3.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Large Time
                    Text(
                      _fmtTime(widget.reminder.time),
                      style: atlMono(
                        size: 48,
                        color: Colors.white,
                        weight: FontWeight.w700,
                      ).copyWith(letterSpacing: -1.0),
                    ),
                  ],
                ),
                
                // Action Buttons
                Padding(
                  padding: const EdgeInsets.only(bottom: 50, left: 30, right: 30),
                  child: Row(
                    children: [
                      // Snooze Button
                      Expanded(
                        child: GestureDetector(
                          onTap: service.snoozeAlarm,
                          child: Container(
                            height: 60,
                            decoration: BoxDecoration(
                              color: atl.surface2,
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(color: atl.hairline),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Snooze (5m)',
                              style: atlSans(
                                size: 16,
                                color: atl.text,
                                weight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      // Dismiss Button
                      Expanded(
                        child: GestureDetector(
                          onTap: service.dismissAlarm,
                          child: Container(
                            height: 60,
                            decoration: BoxDecoration(
                              color: AtlColors.danger,
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [
                                BoxShadow(
                                  color: AtlColors.danger.withValues(alpha: 0.4),
                                  blurRadius: 15,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Dismiss',
                              style: atlSans(
                                size: 16,
                                color: Colors.white,
                                weight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
