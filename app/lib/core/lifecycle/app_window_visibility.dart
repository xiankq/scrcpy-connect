/// A Scene going into the background cannot suspend an active sibling Scene.
final class AppWindowVisibility {
  AppWindowVisibility(this.apply);
  final Future<void> Function(bool) apply;
  final _visible = <Object>{};

  Future<void> set(Object window, bool visible) async {
    final before = _visible.isNotEmpty;
    if (visible) {
      _visible.add(window);
    } else {
      _visible.remove(window);
    }
    final after = _visible.isNotEmpty;
    if (before != after) await apply(after);
  }
}
