import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/services/api/base_web_adapter.dart';

class _Harness with BaseWebAdapterMixin {}

void main() {
  group('BaseWebAdapterMixin selector extensions', () {
    late _Harness harness;
    late BeautifulSoup soup;

    setUp(() {
      harness = _Harness();
      soup = BeautifulSoup('''
        <html>
          <body>
            <div id="root">
              <table class="items">
                <tbody>
                  <tr data-row="1">
                    <td class="name"><a href="details.php?id=10"><b>Alpha</b></a></td>
                    <td class="meta"><span title="Tag">Tag</span><em>Desc</em></td>
                  </tr>
                  <tr data-row="2">
                    <td class="name"><a href="/details.php?id=11"><b>Beta</b></a></td>
                    <td class="meta"><img class="pro_free" title="Free"><span>After</span></td>
                  </tr>
                </tbody>
              </table>
              <p class="copy">Passkey: abc</p>
              <p class="copy">Other text</p>
            </div>
          </body>
        </html>
      ''');
    });

    test('supports next, prev, and parent hops', () {
      final next = harness.findElementBySelector(
        soup,
        'img[class^="pro_"] > next',
      );
      expect(next.single.text.trim(), 'After');

      final prev = harness.findElementBySelector(
        soup,
        'span:contains("After") > prev',
      );
      expect(prev.single.attributes['title'], 'Free');

      final parent = harness.findElementBySelector(
        soup,
        'a[href^="details.php?id="] > parent',
      );
      expect(parent.single.attributes['class'], contains('name'));
    });

    test('supports nth-child and nth-node', () {
      final secondCell = harness.findElementBySelector(
        soup,
        'table.items > tbody > tr:nth-child(1) > td:nth-child(2)',
      );
      expect(secondCell.single.attributes['class'], contains('meta'));

      final firstNode = harness.findElementBySelector(
        soup,
        'table.items > tbody > tr:nth-child(1) > td:nth-child(2) > *:nth-node(1)',
      );
      expect(firstNode.single.text.trim(), 'Tag');
      expect(firstNode.single.attributes['title'], 'Tag');
    });

    test('supports attribute prefix, equals, and regexp operators', () {
      expect(
        harness.findElementBySelector(soup, 'a[href^="details.php?id="]'),
        hasLength(1),
      );
      expect(
        harness.findElementBySelector(soup, 'img[title=="Free"]'),
        hasLength(1),
      );
      expect(
        harness.findElementBySelector(soup, 'a[href~="id=1[01]"]'),
        hasLength(2),
      );
    });

    test('supports contains and css selector passthrough', () {
      final contains = harness.findElementBySelector(
        soup,
        'p:contains("Passkey")',
      );
      expect(contains.single.text.trim(), 'Passkey: abc');

      final css = harness.findElementBySelector(
        soup,
        '@@table.items tr[data-row="2"] td.name b',
      );
      expect(css.single.text.trim(), 'Beta');
    });
  });
}
