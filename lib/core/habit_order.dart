/// Applies a drag made in a grouped list to the saved habit order.
///
/// "Up Next" shows pending habits first and finished ones after, but the
/// saved order (which also drives the grid) must not depend on what happened
/// to be finished at the moment of the drag. So only the habits in [group]
/// trade places, and they trade only the slots the group already occupied in
/// [persisted]; every other habit keeps its slot.
///
/// [persisted] is the saved order, [displayedAfterMove] is the displayed order
/// after the drag, and [group] is the set of ids in the same group as the habit
/// that was dragged.
List<int> reorderWithinGroup({
  required List<int> persisted,
  required List<int> displayedAfterMove,
  required Set<int> group,
}) {
  final groupOrder = [
    for (final id in displayedAfterMove)
      if (group.contains(id)) id,
  ];
  var next = 0;
  return [
    for (final id in persisted) group.contains(id) ? groupOrder[next++] : id,
  ];
}
