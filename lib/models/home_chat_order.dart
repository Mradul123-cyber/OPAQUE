/// A deleted row returns only when its latest message is newer than the
/// message visible when the user deleted it. Null dates use the same sentinel.
bool isHomeChatHidden(DateTime? latestMessage, int? deletedThrough) =>
    deletedThrough != null &&
    (latestMessage?.millisecondsSinceEpoch ?? 0) <= deletedThrough;

/// Pinned chats lead, followed by recent activity and a stable ID tie-breaker.
int compareHomeChats({
  required int aId,
  required int bId,
  required DateTime? aTime,
  required DateTime? bTime,
  required bool aPinned,
  required bool bPinned,
}) {
  if (aPinned != bPinned) return aPinned ? -1 : 1;
  final timeOrder = (bTime?.millisecondsSinceEpoch ?? 0).compareTo(
    aTime?.millisecondsSinceEpoch ?? 0,
  );
  return timeOrder != 0 ? timeOrder : bId.compareTo(aId);
}
