import 'package:matrix/matrix.dart';

extension RoomSpaceChildrenCount on Room {
  /// Number of space children without the sort that [Room.spaceChildren]
  /// performs. Length-only call sites that rebuild every sync tick (e.g.
  /// room list subtitles) should use this instead of materializing and
  /// sorting the whole child list just to take its `.length`.
  int get spaceChildrenCount {
    if (!isSpace) return 0;
    return states[EventTypes.SpaceChild]?.values
            .where(
              (state) =>
                  (state.content.tryGetList<String>('via') ?? []).isNotEmpty,
            )
            .length ??
        0;
  }
}
