import 'package:flutter_test/flutter_test.dart';
import 'package:zarq_messenger/models/home_chat_order.dart';

void main() {
  final earlier = DateTime.utc(2026, 9, 19);
  final later = DateTime.utc(2026, 9, 20);
  test(
    'Deleted rows stay hidden through refresh and return for newer messages',
    () {
      final cutoff = earlier.millisecondsSinceEpoch;
      expect(isHomeChatHidden(earlier, null), isFalse);
      expect(isHomeChatHidden(earlier, cutoff), isTrue);
      expect(
        isHomeChatHidden(earlier.subtract(const Duration(days: 1)), cutoff),
        isTrue,
      );
      expect(isHomeChatHidden(later, cutoff), isFalse);
      expect(isHomeChatHidden(null, 0), isTrue);
      expect(isHomeChatHidden(later, 0), isFalse);
    },
  );
  test('Pin outranks activity; unpinned and pinned peers use newest first', () {
    int compare(bool aPinned, bool bPinned) => compareHomeChats(
      aId: 1,
      bId: 2,
      aTime: earlier,
      bTime: later,
      aPinned: aPinned,
      bPinned: bPinned,
    );
    expect(compare(true, false), lessThan(0));
    expect(compare(false, true), greaterThan(0));
    expect(compare(true, true), greaterThan(0));
    expect(compare(false, false), greaterThan(0));
  });
  test('Missing and equal timestamps have deterministic ordering', () {
    expect(
      compareHomeChats(
        aId: 3,
        bId: 2,
        aTime: null,
        bTime: null,
        aPinned: false,
        bPinned: false,
      ),
      lessThan(0),
    );
    expect(
      compareHomeChats(
        aId: 3,
        bId: 2,
        aTime: null,
        bTime: later,
        aPinned: false,
        bPinned: false,
      ),
      greaterThan(0),
    );
  });
}
