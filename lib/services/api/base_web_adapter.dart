import '../../utils/format.dart';

/// Web DOM 解析适配器的基础 Mixin
/// 提供通用的 DOM 元素选择和字段提取功能
mixin BaseWebAdapterMixin {
  /// 根据选择器查找所有匹配的元素
  /// [soup] 可以是 BeautifulSoup 或 Bs4Element 类型
  List<dynamic> findElementBySelector(dynamic soup, String selector) {
    if (soup == null) return [];

    selector = selector.trim();
    if (selector.isEmpty) return [soup];

    if (selector.startsWith('@@')) {
      return soup.findAll('', selector: selector.substring(2));
    }

    // 首先处理子选择器（>），因为它可能包含其他类型的选择器
    if (selector.contains('>')) {
      final parts = selector.split('>').map((s) => s.trim()).toList();
      List<dynamic> current = [soup];

      for (final part in parts) {
        if (current.isEmpty) break;
        List<dynamic> next = [];
        for (final element in current) {
          if (part == 'next') {
            // 处理 next 关键字，获取下一个兄弟元素
            final nextSibling = element.nextSibling;
            if (nextSibling != null) {
              next.add(nextSibling);
            }
          } else if (part == 'prev') {
            // 处理 prev 关键字，获取上一个兄弟元素
            final previousSibling = element.previousSibling;
            if (previousSibling != null) {
              next.add(previousSibling);
            }
          } else if (part == 'nextParsed') {
            // 处理 nextParsed 关键字
            final nextParsed = element.nextParsed;
            if (nextParsed != null) {
              next.add(nextParsed);
            }
          } else if (part == 'previousParsed') {
            // 处理 prevParsed 关键字，获取上一个兄弟元素(包括非标签)
            final prevParsed = element.previousParsed;
            if (prevParsed != null) {
              next.add(prevParsed);
            }
          } else if (part == 'nextNode') {
            // 处理 nextNode 关键字，通过 parent.nodes 精准获取下一个兄弟节点
            final parent = element.parent;
            if (parent != null) {
              final nodes = parent.nodes;
              final currentHtml = element.outerHtml;
              for (int i = 0; i < nodes.length; i++) {
                if (nodes[i].outerHtml == currentHtml) {
                  if (i + 1 < nodes.length) {
                    next.add(nodes[i + 1]);
                  }
                  break;
                }
              }
            }
          } else if (part == 'previousNode') {
            // 处理 previousNode 关键字，通过 parent.nodes 精准获取上一个兄弟节点
            final parent = element.parent;
            if (parent != null) {
              final nodes = parent.nodes;
              final currentHtml = element.outerHtml;
              for (int i = 0; i < nodes.length; i++) {
                if (nodes[i].outerHtml == currentHtml) {
                  if (i - 1 >= 0) {
                    next.add(nodes[i - 1]);
                  }
                  break;
                }
              }
            }
          } else if (part == 'parent') {
            // 处理 parent 关键字，获取父元素
            final parent = element.parent;
            if (parent != null) {
              next.add(parent);
            }
          } else {
            next.addAll(findElementBySelector(element, part));
          }
        }
        current = next;
      }
      return current;
    }

    // 处理复合选择器：tag.class[attr=="value"] 或 tag.class[attr]
    // 这种选择器同时包含类名和属性条件
    final classAndAttrValueMatch = RegExp(
      r'^([a-zA-Z0-9_-]*)\.([a-zA-Z0-9_-]+)\[([a-zA-Z0-9_-]+)([\^=~])="([^"]+)"\]$',
    ).firstMatch(selector);
    if (classAndAttrValueMatch != null) {
      final tag = classAndAttrValueMatch.group(1)?.trim();
      final className = classAndAttrValueMatch.group(2)?.trim();
      final attribute = classAndAttrValueMatch.group(3)?.trim();
      final operator = classAndAttrValueMatch.group(4)?.trim();
      final value = classAndAttrValueMatch.group(5)?.trim();

      if (className != null &&
          attribute != null &&
          operator != null &&
          value != null) {
        // 先按标签和类名查找元素
        final elements = tag != null && tag.isNotEmpty
            ? soup.findAll(tag, class_: className)
            : soup.findAll('*', class_: className);

        // 然后按属性条件过滤
        final filteredElements = <dynamic>[];
        for (final element in elements) {
          final attrValue = element.attributes[attribute];
          if (attrValue != null) {
            bool matches = false;
            switch (operator) {
              case '^': // 前缀匹配
                matches = attrValue.startsWith(value);
                break;
              case '=': // 完全匹配
                matches = attrValue == value;
                break;
              case '~': // 正则匹配
                try {
                  final regex = RegExp(value);
                  matches = regex.hasMatch(attrValue);
                } catch (e) {
                  matches = false;
                }
                break;
            }
            if (matches) {
              filteredElements.add(element);
            }
          }
        }
        return filteredElements;
      }
    }

    // 处理复合选择器：tag.class[attr]（属性存在性）
    final classAndAttrExistsMatch = RegExp(
      r'^([a-zA-Z0-9_-]*)\.([a-zA-Z0-9_-]+)\[([a-zA-Z0-9_-]+)\]$',
    ).firstMatch(selector);
    if (classAndAttrExistsMatch != null) {
      final tag = classAndAttrExistsMatch.group(1)?.trim();
      final className = classAndAttrExistsMatch.group(2)?.trim();
      final attribute = classAndAttrExistsMatch.group(3)?.trim();

      if (className != null && attribute != null) {
        // 先按标签和类名查找元素
        final elements = tag != null && tag.isNotEmpty
            ? soup.findAll(tag, class_: className)
            : soup.findAll('*', class_: className);

        // 然后按属性存在性过滤
        final filteredElements = <dynamic>[];
        for (final element in elements) {
          if (element.attributes[attribute] != null) {
            filteredElements.add(element);
          }
        }
        return filteredElements;
      }
    }

    // 处理属性选择器
    // 1. 属性存在性选择器 tag[attr]
    final attributeExistsMatch = RegExp(
      r'^([a-zA-Z0-9_-]*)\[([a-zA-Z0-9_-]+)\]$',
    ).firstMatch(selector);
    if (attributeExistsMatch != null) {
      final tag = attributeExistsMatch.group(1)?.trim();
      final attribute = attributeExistsMatch.group(2)?.trim();

      if (attribute != null) {
        // 获取所有指定标签的元素（如果没有指定标签，则获取所有元素）
        if (tag != null && tag.isNotEmpty) {
          return soup.findAll(tag, attrs: {attribute: true});
        } else {
          return soup.findAll('*', attrs: {attribute: true});
        }
      }
    }

    // 2. 属性值选择器 tag[attr^="value"], tag[attr=="value"], tag[attr~="pattern"]
    final attributeValueMatch = RegExp(
      r'^([a-zA-Z0-9_-]*)\[([a-zA-Z0-9_-]+)([\^=~])="([^"]+)"\]$',
    ).firstMatch(selector);
    if (attributeValueMatch != null) {
      final tag = attributeValueMatch.group(1)?.trim();
      final attribute = attributeValueMatch.group(2)?.trim();
      final operator = attributeValueMatch.group(3)?.trim();
      final value = attributeValueMatch.group(4)?.trim();

      if (attribute != null && operator != null && value != null) {
        // 获取所有指定标签的元素（如果没有指定标签，则获取所有元素）
        final elements = tag != null && tag.isNotEmpty
            ? soup.findAll(tag)
            : soup.findAll('*');

        final filteredElements = <dynamic>[];
        for (final element in elements) {
          final attrValue = element.attributes[attribute];
          if (attrValue != null) {
            final normalizedAttrValue = normalizeHrefForComparison(attrValue);

            bool matches = false;
            switch (operator) {
              case '^': // 前缀匹配
                matches = normalizedAttrValue.startsWith(value);
                break;
              case '=': // 完全匹配
                matches = normalizedAttrValue == value;
                break;
              case '~': // 正则匹配
                try {
                  final regex = RegExp(value);
                  matches = regex.hasMatch(normalizedAttrValue);
                } catch (e) {
                  // 正则表达式无效，跳过
                  matches = false;
                }
                break;
            }

            if (matches) {
              filteredElements.add(element);
            }
          }
        }
        return filteredElements;
      }
    }

    // 处理单个选择器
    final containsAllMatch = RegExp(
      r'^([^:]*):contains\((.*)\)$',
    ).firstMatch(selector);
    if (containsAllMatch != null) {
      final preSelector = (containsAllMatch.group(1) ?? '').trim();
      final expr = (containsAllMatch.group(2) ?? '').trim();
      final groups = parseContainsExpr(expr);

      final candidates = preSelector.isNotEmpty
          ? findElementBySelector(soup, preSelector)
          : soup.findAll('*');

      final results = <dynamic>[];
      for (final el in candidates) {
        final t = (el.text ?? '')
            .replaceAll('\n', ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        final ok = groups.any((g) => g.every((n) => t.contains(n)));
        if (ok) {
          results.add(el);
        }
      }
      return results;
    }

    if (selector.contains(':nth-child')) {
      // nth-child选择器
      if (selector.contains(':nth-child(')) {
        // 带括号数字的 nth-child 选择器
        final nthChildMatch = RegExp(
          r'^([^:]*):nth-child\((\d+)\)',
        ).firstMatch(selector);
        if (nthChildMatch != null) {
          final tag = nthChildMatch.group(1)?.trim();
          final index = FormatUtil.parseInt(nthChildMatch.group(2) ?? '1') ?? 1;

          // 获取直接子元素
          final children = soup.children;
          if (children.isNotEmpty && index > 0 && index <= children.length) {
            final nthChild = children[index - 1]; // nth-child是1-based索引

            // 如果指定了标签，验证第n个子元素是否匹配该标签
            if (tag != null && tag.isNotEmpty && tag != '*') {
              if (nthChild.name.toLowerCase() == tag.toLowerCase()) {
                return [nthChild];
              }
              // 如果第n个子元素不匹配指定标签，返回空列表
              return [];
            } else {
              // 如果没有指定标签，直接返回第n个子元素
              return [nthChild];
            }
          }
        }
      } else {
        // 不带括号的 nth-child 选择器，只取直接子元素中的指定标签
        final nthChildMatch = RegExp(
          r'^([^:]+):nth-child$',
        ).firstMatch(selector);
        if (nthChildMatch != null) {
          final tag = nthChildMatch.group(1)?.trim();
          if (tag != null && tag.isNotEmpty) {
            // 只在直接子元素中查找指定标签
            final children = soup.children;
            final matchingChildren = children
                .where((child) => child.name.toLowerCase() == tag.toLowerCase())
                .toList();
            return matchingChildren;
          }
        }
      }
    } else if (selector.contains(':first-child')) {
      // 第一个子元素
      final children = soup.children;
      if (children.isNotEmpty) {
        return [children.first];
      }
    } else if (selector.contains(':last-child')) {
      // 最后一个子元素
      final children = soup.children;
      if (children.isNotEmpty) {
        return [children.last];
      }
    } else if (selector.contains(':nth-node')) {
      // nth-child选择器
      if (selector.contains(':nth-node(')) {
        // 带括号数字的 nth-child 选择器
        final nthChildMatch = RegExp(
          r'^([^:]*):nth-node\((\d+)\)',
        ).firstMatch(selector);
        if (nthChildMatch != null) {
          final tag = nthChildMatch.group(1)?.trim();
          final index = FormatUtil.parseInt(nthChildMatch.group(2) ?? '1') ?? 1;

          // 获取直接子元素
          final nodes = soup.nodes;
          if (nodes.isNotEmpty && index > 0 && index <= nodes.length) {
            final node = nodes[index - 1]; // nth-child是1-based索引

            // 如果指定了标签，验证第n个子元素是否匹配该标签
            if (tag != null && tag.isNotEmpty && tag != '*') {
              if (node.name.toLowerCase() == tag.toLowerCase()) {
                return [node];
              }
              // 如果第n个子元素不匹配指定标签，返回空列表
              return [];
            } else {
              // 如果没有指定标签，直接返回第n个子元素
              return [node];
            }
          }
        }
      } else {
        // 不带括号的 nth-child 选择器，只取直接子元素中的指定标签
        final nthNodeMatch = RegExp(r'^([^:]+):nth-node$').firstMatch(selector);
        if (nthNodeMatch != null) {
          final tag = nthNodeMatch.group(1)?.trim();
          if (tag != null && tag.isNotEmpty) {
            // 只在直接子元素中查找指定标签
            final nodes = soup.nodes;
            final matchingNodes = nodes
                .where((node) => node.name.toLowerCase() == tag.toLowerCase())
                .toList();
            return matchingNodes;
          }
        }
      }
    } else if (selector.contains(':first-node')) {
      // 第一个子元素
      final nodes = soup.nodes;
      if (nodes.isNotEmpty) {
        return [nodes.first];
      }
    } else if (selector.contains(':last-node')) {
      // 最后一个子元素
      final nodes = soup.nodes;
      if (nodes.isNotEmpty) {
        return [nodes.last];
      }
    } else if (selector.contains('#')) {
      // ID选择器
      final parts = selector.split('#');
      if (parts.length == 2) {
        final tag = parts[0].isEmpty ? null : parts[0];
        final id = parts[1].split(' ').first; // 处理复合选择器
        if (tag != null) {
          return soup.findAll(tag, id: id);
        } else {
          return soup.findAll('*', id: id);
        }
      }
    } else if (selector.contains('.')) {
      // 类选择器
      final parts = selector.split('.');
      if (parts.length == 2) {
        final tag = parts[0].isEmpty ? null : parts[0];
        final className = parts[1].split(' ').first; // 处理复合选择器
        if (tag != null) {
          return soup.findAll(tag, attrs: {'class': className});
        } else {
          return soup.findAll('*', attrs: {'class': className});
        }
      }
    } else {
      // 简单标签选择器
      return soup.findAll(selector);
    }

    return [];
  }

  /// 根据选择器查找第一个匹配的元素（向前兼容）
  /// [soup] 可以是 BeautifulSoup 或 Bs4Element 类型
  dynamic findFirstElementBySelector(dynamic soup, String selector) {
    final elements = findElementBySelector(soup, selector);
    return elements.isNotEmpty ? elements.first : null;
  }

  /// 根据字段配置提取字段值列表
  Future<List<String>> extractFieldValue(
    dynamic element,
    Map<String, dynamic> fieldConfig,
  ) async {
    final selector = fieldConfig['selector'] as String?;
    final attribute = fieldConfig['attribute'] as String?;
    final filter = fieldConfig['filter'] as Map<String, dynamic>?;

    List<dynamic> targetElements = [element];

    // 如果有选择器，进一步定位元素
    if (selector != null && selector.isNotEmpty) {
      targetElements = findElementBySelector(element, selector);
    }

    if (targetElements.isEmpty) {
      return [];
    }

    // 遍历所有目标元素，提取属性值
    List<String> values = [];
    for (final targetElement in targetElements) {
      if (targetElement == null) continue;

      // 根据属性类型获取值
      String? value;
      if (attribute == 'text') {
        value = targetElement.text?.trim();
      } else if (attribute == 'href') {
        value = targetElement.attributes['href'];
      } else {
        value = targetElement.attributes[attribute ?? 'text'];
      }

      // 如果有过滤器，应用过滤器
      if (filter != null && value != null) {
        value = applyFilter(value, filter);
      }

      // 只添加非空值
      if (value != null && value.isNotEmpty) {
        values.add(value.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' '));
      }
    }

    return values;
  }

  /// 根据字段配置提取第一个字段值（向前兼容）
  Future<String?> extractFirstFieldValue(
    dynamic element,
    Map<String, dynamic> fieldConfig,
  ) async {
    final values = await extractFieldValue(element, fieldConfig);
    return values.isNotEmpty ? values.first : null;
  }

  /// 标准化href属性用于比较
  /// 将绝对URL转换为相对路径格式，便于与配置中的路径进行比较
  String normalizeHrefForComparison(String href) {
    if (href.startsWith('http://') || href.startsWith('https://')) {
      final uri = Uri.tryParse(href);
      if (uri != null) {
        return '${uri.path.substring(1)}${uri.query.isNotEmpty ? '?${uri.query}' : ''}';
      }
    }
    return href;
  }

  /// 应用过滤器
  String? applyFilter(String value, Map<String, dynamic> filter) {
    final filterName = filter['name'] as String?;

    if (filterName == 'regexp') {
      final args = filter['args'] as String?;
      final format = filter['value'] as String?;

      if (args != null) {
        final regex = RegExp(args);
        final match = regex.firstMatch(value);
        if (match != null) {
          final template = format ?? r'$0';
          return template.replaceAllMapped(RegExp(r'\$(\d+)'), (m) {
            final groupIndex = int.parse(m.group(1)!);
            if (groupIndex <= match.groupCount) {
              return match.group(groupIndex) ?? '';
            }
            return m.group(0)!;
          });
        }
      }
    }

    return null;
  }

  /// 在引号外分割字符串
  List<String> splitOutsideQuotes(String input, String op) {
    final out = <String>[];
    var buf = StringBuffer();
    var i = 0;
    var inS = false;
    var inD = false;
    while (i < input.length) {
      final c = input[i];
      if (c == '\'' && !inD) {
        inS = !inS;
        buf.write(c);
        i++;
        continue;
      }
      if (c == '"' && !inS) {
        inD = !inD;
        buf.write(c);
        i++;
        continue;
      }
      if (!inS && !inD && input.substring(i).startsWith(op)) {
        out.add(buf.toString());
        buf = StringBuffer();
        i += op.length;
        continue;
      }
      buf.write(c);
      i++;
    }
    out.add(buf.toString());
    return out;
  }

  /// 解析 contains 表达式
  List<List<String>> parseContainsExpr(String expr) {
    final orParts = splitOutsideQuotes(expr, '||');
    final groups = <List<String>>[];
    for (final orPart in orParts) {
      final andParts = splitOutsideQuotes(orPart, '&&');
      final needles = <String>[];
      for (final p in andParts) {
        final s = p.trim();
        final m =
            RegExp(r"^'(.*)'$").firstMatch(s) ??
            RegExp(r'^"(.*)"$').firstMatch(s);
        if (m != null) {
          final v = (m.group(1) ?? '').trim();
          if (v.isNotEmpty) needles.add(v);
        }
      }
      if (needles.isNotEmpty) groups.add(needles);
    }
    return groups;
  }
}
