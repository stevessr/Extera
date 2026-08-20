import 'package:flutter_test/flutter_test.dart';

import 'package:extera_next/utils/content_warning.dart';

void main() {
  group('content warning', () {
    test('reads the type of an event', () {
      expect(
        contentWarningOf({
          'msgtype': 'm.image',
          contentWarningKey: {'type': 'town.robin.msc3725.nsfw'},
        }),
        'town.robin.msc3725.nsfw',
      );
      expect(contentWarningOf({'msgtype': 'm.image'}), null);
    });

    test('writes both the MSC3725 object and the MSC4193 flag', () {
      final content = <String, dynamic>{'msgtype': 'm.image'};
      applyContentWarning(content, ContentWarningType.graphic.value);

      expect(content[contentWarningKey], {
        'type': 'town.robin.msc3725.graphic',
      });
      expect(content[contentWarningSpoilerKey], true);
      expect(contentWarningOf(content), 'town.robin.msc3725.graphic');
    });

    test('removes both keys again', () {
      final content = <String, dynamic>{'msgtype': 'm.image'};
      applyContentWarning(content, ContentWarningType.spoiler.value);
      applyContentWarning(content, null);

      expect(content.containsKey(contentWarningKey), false);
      expect(content.containsKey(contentWarningSpoilerKey), false);
      expect(contentWarningOf(content), null);
    });

    test('replaces a previous warning instead of merging', () {
      final content = <String, dynamic>{};
      applyContentWarning(content, ContentWarningType.spoiler.value);
      applyContentWarning(content, ContentWarningType.medical.value);

      expect(contentWarningOf(content), 'town.robin.msc3725.medical');
    });
  });
}
