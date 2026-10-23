import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';

void main() {
  group('TagType.matchTags', () {
    const aliases = <TagType, List<String>>{
      TagType.chinese: ['chinese_simplified'],
      TagType.chineseTraditional: ['chinese_traditional'],
      TagType.complete: ['全12集'],
      TagType.ep: ['EP', 'EP12', 'S01E01', 'E01-E02', '第12集'],
      TagType.fourK: ['4K', '2160p'],
      TagType.eightK: ['8K'],
      TagType.resolution1080: ['1080p', 'x1080', '1920x1080'],
      TagType.hdr: ['HDR', 'HDR10'],
      TagType.vr: ['VR'],
      TagType.h265: ['H265', 'H.265', 'HEVC', 'x265'],
      TagType.webDl: ['WEB-DL', 'WEBDL', 'WEB.DL'],
      TagType.dovi: ['DOVI', 'Dolby Vision', 'DV', '杜比', '杜比视界'],
      TagType.blueRay: ['blu-ray', 'bluray'],
    };

    for (final entry in aliases.entries) {
      for (final alias in entry.value) {
        test('${entry.key.name} matches standalone $alias', () {
          for (final text in [
            alias,
            alias.toLowerCase(),
            alias.toUpperCase(),
            'Movie $alias release',
            'Movie.$alias.release',
            'Movie [$alias]',
            'Movie ($alias)',
          ]) {
            expect(TagType.matchTags(text), contains(entry.key), reason: text);
          }
        });

        test('${entry.key.name} rejects hyphen-connected $alias', () {
          for (final text in [
            '$alias-123',
            'ABC-$alias',
            'ABC-$alias-123',
            'Movie $alias-HDR release',
            'Movie-$alias',
          ]) {
            expect(
              TagType.matchTags(text),
              isNot(contains(entry.key)),
              reason: text,
            );
          }
        });
      }
    }

    test('matches VR delimited by brackets, including next to hyphens', () {
      for (final label in ['【vr】', '[vR]', '［VR］']) {
        for (final text in [label, 'Movie-$label-123']) {
          expect(TagType.matchTags(text), contains(TagType.vr), reason: text);
        }
      }
    });

    test('does not match VR inside another word', () {
      for (final text in ['AVR', 'VR123', 'VRPlayer', 'VR_test', 'test_VR']) {
        expect(
          TagType.matchTags(text),
          isNot(contains(TagType.vr)),
          reason: text,
        );
      }
    });

    test('does not duplicate repeated or alternative labels', () {
      final tags = TagType.matchTags('VR vr 【vr】 [VR] ［vR］ DV DOVI');

      expect(tags.where((tag) => tag == TagType.vr), hasLength(1));
      expect(tags.where((tag) => tag == TagType.dovi), hasLength(1));
    });

    test('still finds a standalone label after a rejected occurrence', () {
      final tags = TagType.matchTags('DV-123 dv VR-123 vr 8K-UHD 8k');

      expect(tags, containsAll([TagType.dovi, TagType.vr, TagType.eightK]));
    });
  });
}
