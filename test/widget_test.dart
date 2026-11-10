import 'package:flutter_test/flutter_test.dart';
import 'package:napominator/ui/format.dart';

void main() {
  test('склонение дней', () {
    expect(daysWord(1), '1 день');
    expect(daysWord(3), '3 дня');
    expect(daysWord(5), '5 дней');
    expect(daysWord(11), '11 дней');
    expect(daysWord(22), '22 дня');
  });

  test('время', () {
    expect(formatTime(9 * 60 + 5), '09:05');
  });
}
