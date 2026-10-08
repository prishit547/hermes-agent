import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/ui/features/automations/schedule_parser.dart';

void main() {
  group('parseSchedule', () {
    ParsedSchedule need(String input) {
      final r = parseSchedule(input);
      expect(r, isNotNull, reason: 'expected "$input" to parse');
      return r!;
    }

    test('daily with named period', () {
      expect(need('every morning at 8').cron, '0 8 * * *');
      expect(need('remind me each evening').cron, '0 18 * * *');
    });

    test('explicit clock times with am/pm', () {
      expect(need('daily at 8:30am').cron, '30 8 * * *');
      expect(need('every day at 9pm').cron, '0 21 * * *');
      expect(need('at 21:00').cron, '0 21 * * *');
      expect(need('at noon').cron, '0 12 * * *');
      expect(need('at midnight').cron, '0 0 * * *');
    });

    test('weekday / weekend anchors', () {
      expect(need('weekdays at 9am').cron, '0 9 * * 1-5');
      expect(need('every weekend at 10').cron, '0 10 * * 0,6');
    });

    test('single day of week', () {
      expect(need('every monday at 9am').cron, '0 9 * * 1');
      expect(need('sundays at 7pm').cron, '0 19 * * 0');
    });

    test('interval phrases need no time', () {
      expect(need('every hour').cron, '0 * * * *');
      expect(need('hourly').cron, '0 * * * *');
      expect(need('every 2 hours').cron, '0 */2 * * *');
      expect(need('every 15 minutes').cron, '*/15 * * * *');
      expect(need('every half hour').cron, '*/30 * * * *');
    });

    test('returns null when nothing anchors a schedule', () {
      expect(parseSchedule(''), isNull);
      expect(parseSchedule('do something nice'), isNull);
    });

    test('rejects out-of-range bare hour', () {
      expect(parseSchedule('at 30'), isNull);
    });
  });
}
