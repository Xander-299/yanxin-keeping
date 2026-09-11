import 'package:flutter_test/flutter_test.dart';
import 'package:yanxin/core/utils/date.dart';

const day = 24 * 60 * 60 * 1000;

void main() {
  group('monthRange / isInMonth', () {
    test('月份边界：8/31 23:59:59.999 不属于 9 月，9/1 00:00:00 属于 9 月', () {
      final aug31End = DateTime(2026, 8, 31, 23, 59, 59, 999).millisecondsSinceEpoch;
      final sep1 = DateTime(2026, 9, 1).millisecondsSinceEpoch;
      expect(isInMonth(aug31End, 2026, 9), isFalse);
      expect(isInMonth(sep1, 2026, 9), isTrue);
    });

    test('月末最后一刻属于当月，下月第一刻不属于当月', () {
      final sep30End = DateTime(2026, 9, 30, 23, 59, 59, 999).millisecondsSinceEpoch;
      final oct1 = DateTime(2026, 10, 1).millisecondsSinceEpoch;
      expect(isInMonth(sep30End, 2026, 9), isTrue);
      expect(isInMonth(oct1, 2026, 9), isFalse);
    });

    test('闰年 2 月为 29 天，平年 28 天', () {
      final leap = monthRange(2024, 2);
      final normal = monthRange(2025, 2);
      expect(leap.end - leap.start, 29 * day); // 2024 闰年
      expect(normal.end - normal.start, 28 * day); // 2025 平年
    });

    test('跨年：12 月结束于次年 1 月', () {
      expect(monthRange(2026, 12).end, DateTime(2027, 1, 1).millisecondsSinceEpoch);
    });
  });

  group('dayKey / formatDayLabel', () {
    test('本地日期 key', () {
      expect(dayKey(DateTime(2026, 9, 5, 10).millisecondsSinceEpoch), '2026-09-05');
    });
    test('今天 / 昨天', () {
      final now = DateTime(2026, 9, 10, 12).millisecondsSinceEpoch;
      final todayMs = DateTime(2026, 9, 10, 8).millisecondsSinceEpoch;
      final yestMs = DateTime(2026, 9, 9, 8).millisecondsSinceEpoch;
      expect(formatDayLabel(todayMs, now: now), '今天');
      expect(formatDayLabel(yestMs, now: now), '昨天');
      expect(formatDayLabel(DateTime(2026, 9, 1, 8).millisecondsSinceEpoch, now: now), '9月1日');
    });
    test('跨年日期带年份', () {
      final now = DateTime(2026, 1, 10, 12).millisecondsSinceEpoch;
      final lastYear = DateTime(2025, 12, 25, 8).millisecondsSinceEpoch;
      expect(formatDayLabel(lastYear, now: now), '2025年12月25日');
    });
  });

  group('groupByDay', () {
    test('按本地日期倒序分组', () {
      final list = [
        (id: '1', occurredAt: DateTime(2026, 9, 1, 9).millisecondsSinceEpoch),
        (id: '2', occurredAt: DateTime(2026, 9, 2, 9).millisecondsSinceEpoch),
        (id: '3', occurredAt: DateTime(2026, 9, 2, 18).millisecondsSinceEpoch),
      ];
      final groups = groupByDay(list, (e) => e.occurredAt);
      expect(groups.length, 2);
      expect(groups[0].key, '2026-09-02'); // 新日期在前
      expect(groups[0].items.length, 2);
      expect(groups[1].key, '2026-09-01');
    });
  });
}
