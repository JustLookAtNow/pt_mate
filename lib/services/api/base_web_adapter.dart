import '../../utils/format.dart';
import 'dart:collection';

class _AttributeSelector {
  final String? tag;
  final String attribute;
  final String? operator;
  final String? value;
  final RegExp? regex;

  const _AttributeSelector({
    required this.tag,
    required this.attribute,
    this.operator,
    this.value,
    this.regex,
  });
}

class _ClassAttributeSelector extends _AttributeSelector {
  final String className;

  const _ClassAttributeSelector({
    required super.tag,
    required this.className,
    required super.attribute,
    super.operator,
    super.value,
    super.regex,
  });
}

class _ContainsSelector {
  final String preSelector;
  final List<List<String>> groups;

  const _ContainsSelector({required this.preSelector, required this.groups});
}

class _IndexedSelector {
  final String? tag;
  final int index;

  const _IndexedSelector({required this.tag, required this.index});
}

class _NamedSelector {
  final String? tag;
  final String value;

  const _NamedSelector({required this.tag, required this.value});
}

class _SelectorPlan {
  final String selector;
  final bool isEmpty;
  final String? cssSelector;
  final List<String>? childParts;
  final _ClassAttributeSelector? classAndAttrValue;
  final _ClassAttributeSelector? classAndAttrExists;
  final _AttributeSelector? attrValue;
  final _AttributeSelector? attrExists;
  final _ContainsSelector? contains;
  final _IndexedSelector? nthChild;
  final String? nthChildTag;
  final _IndexedSelector? nthNode;
  final String? nthNodeTag;
  final bool firstChild;
  final bool lastChild;
  final bool firstNode;
  final bool lastNode;
  final _NamedSelector? idSelector;
  final _NamedSelector? classSelector;
  final String? tagSelector;

  const _SelectorPlan({
    required this.selector,
    this.isEmpty = false,
    this.cssSelector,
    this.childParts,
    this.classAndAttrValue,
    this.classAndAttrExists,
    this.attrValue,
    this.attrExists,
    this.contains,
    this.nthChild,
    this.nthChildTag,
    this.nthNode,
    this.nthNodeTag,
    this.firstChild = false,
    this.lastChild = false,
    this.firstNode = false,
    this.lastNode = false,
    this.idSelector,
    this.classSelector,
    this.tagSelector,
  });
}

/// Web DOM 解析适配器的基础 Mixin
/// 提供通用的 DOM 元素选择和字段提取功能
mixin BaseWebAdapterMixin {
  // Static regex cache for dynamic regexes
  static final LinkedHashMap<String, RegExp> _regexCache =
      LinkedHashMap<String, RegExp>();
  static final LinkedHashMap<String, _SelectorPlan> _selectorPlanCache =
      LinkedHashMap<String, _SelectorPlan>();
  static const int _maxCacheSize = 100;
  static const int _maxSelectorPlanCacheSize = 200;

  // Cached static regexes
  static final RegExp _classAndAttrValueRegExp = RegExp(
    r'^([a-zA-Z0-9_-]*)\.([a-zA-Z0-9_-]+)\[([a-zA-Z0-9_-]+)([\^=~])="([^"]+)"\]$',
  );
  static final RegExp _classAndAttrExistsRegExp = RegExp(
    r'^([a-zA-Z0-9_-]*)\.([a-zA-Z0-9_-]+)\[([a-zA-Z0-9_-]+)\]$',
  );
  static final RegExp _attributeExistsRegExp = RegExp(
    r'^([a-zA-Z0-9_-]*)\[([a-zA-Z0-9_-]+)\]$',
  );
  static final RegExp _attributeValueRegExp = RegExp(
    r'^([a-zA-Z0-9_-]*)\[([a-zA-Z0-9_-]+)([\^=~])="([^"]+)"\]$',
  );
  static final RegExp _containsAllRegExp = RegExp(
    r'^([^:]*):contains\((.*)\)$',
  );
  static final RegExp _whitespaceRegExp = RegExp(r'\s+');
  static final RegExp _nthChildWithParenRegExp = RegExp(
    r'^([^:]*):nth-child\((\d+)\)',
  );
  static final RegExp _nthChildRegExp = RegExp(r'^([^:]+):nth-child$');
  static final RegExp _nthNodeWithParenRegExp = RegExp(
    r'^([^:]*):nth-node\((\d+)\)',
  );
  static final RegExp _nthNodeRegExp = RegExp(r'^([^:]+):nth-node$');
  static final RegExp _filterGroupRegExp = RegExp(r'\$(\d+)');
  static final RegExp _singleQuoteRegExp = RegExp(r"^'(.*)'$");
  static final RegExp _doubleQuoteRegExp = RegExp(r'^"(.*)"$');

  RegExp _getCachedRegExp(String pattern) {
    if (_regexCache.containsKey(pattern)) {
      final regex = _regexCache.remove(pattern)!;
      _regexCache[pattern] = regex; // move to end
      return regex;
    }
    final regex = RegExp(pattern);
    _regexCache[pattern] = regex;
    if (_regexCache.length > _maxCacheSize) {
      _regexCache.remove(_regexCache.keys.first);
    }
    return regex;
  }

  _SelectorPlan _getSelectorPlan(String selector) {
    final trimmed = selector.trim();
    if (_selectorPlanCache.containsKey(trimmed)) {
      final plan = _selectorPlanCache.remove(trimmed)!;
      _selectorPlanCache[trimmed] = plan;
      return plan;
    }

    final plan = _buildSelectorPlan(trimmed);
    _selectorPlanCache[trimmed] = plan;
    if (_selectorPlanCache.length > _maxSelectorPlanCacheSize) {
      _selectorPlanCache.remove(_selectorPlanCache.keys.first);
    }
    return plan;
  }

  _SelectorPlan _buildSelectorPlan(String selector) {
    if (selector.isEmpty) {
      return const _SelectorPlan(selector: '', isEmpty: true);
    }
    if (selector.startsWith('@@')) {
      return _SelectorPlan(
        selector: selector,
        cssSelector: selector.substring(2),
      );
    }
    if (selector.contains('>')) {
      return _SelectorPlan(
        selector: selector,
        childParts: selector.split('>').map((s) => s.trim()).toList(),
      );
    }

    final classAndAttrValueMatch = _classAndAttrValueRegExp.firstMatch(
      selector,
    );
    if (classAndAttrValueMatch != null) {
      final operator = classAndAttrValueMatch.group(4)?.trim();
      final value = classAndAttrValueMatch.group(5)?.trim();
      return _SelectorPlan(
        selector: selector,
        classAndAttrValue: _ClassAttributeSelector(
          tag: _emptyToNull(classAndAttrValueMatch.group(1)?.trim()),
          className: classAndAttrValueMatch.group(2)?.trim() ?? '',
          attribute: classAndAttrValueMatch.group(3)?.trim() ?? '',
          operator: operator,
          value: value,
          regex: operator == '~' && value != null
              ? _tryBuildRegExp(value)
              : null,
        ),
      );
    }

    final classAndAttrExistsMatch = _classAndAttrExistsRegExp.firstMatch(
      selector,
    );
    if (classAndAttrExistsMatch != null) {
      return _SelectorPlan(
        selector: selector,
        classAndAttrExists: _ClassAttributeSelector(
          tag: _emptyToNull(classAndAttrExistsMatch.group(1)?.trim()),
          className: classAndAttrExistsMatch.group(2)?.trim() ?? '',
          attribute: classAndAttrExistsMatch.group(3)?.trim() ?? '',
        ),
      );
    }

    final attributeExistsMatch = _attributeExistsRegExp.firstMatch(selector);
    if (attributeExistsMatch != null) {
      return _SelectorPlan(
        selector: selector,
        attrExists: _AttributeSelector(
          tag: _emptyToNull(attributeExistsMatch.group(1)?.trim()),
          attribute: attributeExistsMatch.group(2)?.trim() ?? '',
        ),
      );
    }

    final attributeValueMatch = _attributeValueRegExp.firstMatch(selector);
    if (attributeValueMatch != null) {
      final operator = attributeValueMatch.group(3)?.trim();
      final value = attributeValueMatch.group(4)?.trim();
      return _SelectorPlan(
        selector: selector,
        attrValue: _AttributeSelector(
          tag: _emptyToNull(attributeValueMatch.group(1)?.trim()),
          attribute: attributeValueMatch.group(2)?.trim() ?? '',
          operator: operator,
          value: value,
          regex: operator == '~' && value != null
              ? _tryBuildRegExp(value)
              : null,
        ),
      );
    }

    final containsAllMatch = _containsAllRegExp.firstMatch(selector);
    if (containsAllMatch != null) {
      final expr = (containsAllMatch.group(2) ?? '').trim();
      return _SelectorPlan(
        selector: selector,
        contains: _ContainsSelector(
          preSelector: (containsAllMatch.group(1) ?? '').trim(),
          groups: parseContainsExpr(expr),
        ),
      );
    }

    if (selector.contains(':nth-child')) {
      if (selector.contains(':nth-child(')) {
        final nthChildMatch = _nthChildWithParenRegExp.firstMatch(selector);
        if (nthChildMatch != null) {
          return _SelectorPlan(
            selector: selector,
            nthChild: _IndexedSelector(
              tag: _emptyToNull(nthChildMatch.group(1)?.trim()),
              index: FormatUtil.parseInt(nthChildMatch.group(2) ?? '1') ?? 1,
            ),
          );
        }
      } else {
        final nthChildMatch = _nthChildRegExp.firstMatch(selector);
        if (nthChildMatch != null) {
          return _SelectorPlan(
            selector: selector,
            nthChildTag: _emptyToNull(nthChildMatch.group(1)?.trim()),
          );
        }
      }
    } else if (selector.contains(':first-child')) {
      return _SelectorPlan(selector: selector, firstChild: true);
    } else if (selector.contains(':last-child')) {
      return _SelectorPlan(selector: selector, lastChild: true);
    } else if (selector.contains(':nth-node')) {
      if (selector.contains(':nth-node(')) {
        final nthNodeMatch = _nthNodeWithParenRegExp.firstMatch(selector);
        if (nthNodeMatch != null) {
          return _SelectorPlan(
            selector: selector,
            nthNode: _IndexedSelector(
              tag: _emptyToNull(nthNodeMatch.group(1)?.trim()),
              index: FormatUtil.parseInt(nthNodeMatch.group(2) ?? '1') ?? 1,
            ),
          );
        }
      } else {
        final nthNodeMatch = _nthNodeRegExp.firstMatch(selector);
        if (nthNodeMatch != null) {
          return _SelectorPlan(
            selector: selector,
            nthNodeTag: _emptyToNull(nthNodeMatch.group(1)?.trim()),
          );
        }
      }
    } else if (selector.contains(':first-node')) {
      return _SelectorPlan(selector: selector, firstNode: true);
    } else if (selector.contains(':last-node')) {
      return _SelectorPlan(selector: selector, lastNode: true);
    } else if (selector.contains('#')) {
      final parts = selector.split('#');
      if (parts.length == 2) {
        return _SelectorPlan(
          selector: selector,
          idSelector: _NamedSelector(
            tag: _emptyToNull(parts[0]),
            value: parts[1].split(' ').first,
          ),
        );
      }
    } else if (selector.contains('.')) {
      final parts = selector.split('.');
      if (parts.length == 2) {
        return _SelectorPlan(
          selector: selector,
          classSelector: _NamedSelector(
            tag: _emptyToNull(parts[0]),
            value: parts[1].split(' ').first,
          ),
        );
      }
    }

    return _SelectorPlan(selector: selector, tagSelector: selector);
  }

  RegExp? _tryBuildRegExp(String pattern) {
    try {
      return _getCachedRegExp(pattern);
    } catch (_) {
      return null;
    }
  }

  static String? _emptyToNull(String? value) {
    if (value == null || value.isEmpty) return null;
    return value;
  }

  /// 根据选择器查找所有匹配的元素
  /// [soup] 可以是 BeautifulSoup 或 Bs4Element 类型
  List<dynamic> findElementBySelector(dynamic soup, String selector) {
    if (soup == null) return [];

    final plan = _getSelectorPlan(selector);
    if (plan.isEmpty) return [soup];

    if (plan.cssSelector != null) {
      return soup.findAll('', selector: plan.cssSelector);
    }

    // 首先处理子选择器（>），因为它可能包含其他类型的选择器
    final childParts = plan.childParts;
    if (childParts != null) {
      List<dynamic> current = [soup];

      for (final part in childParts) {
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
    final classAndAttrValue = plan.classAndAttrValue;
    if (classAndAttrValue != null) {
      if (classAndAttrValue.className.isNotEmpty &&
          classAndAttrValue.attribute.isNotEmpty &&
          classAndAttrValue.operator != null &&
          classAndAttrValue.value != null) {
        // 先按标签和类名查找元素
        final elements = classAndAttrValue.tag != null
            ? soup.findAll(
                classAndAttrValue.tag,
                class_: classAndAttrValue.className,
              )
            : soup.findAll('*', class_: classAndAttrValue.className);

        // 然后按属性条件过滤
        final filteredElements = <dynamic>[];
        for (final element in elements) {
          final attrValue = element.attributes[classAndAttrValue.attribute];
          if (attrValue != null) {
            if (_matchesAttribute(
              attrValue,
              classAndAttrValue,
              normalize: false,
            )) {
              filteredElements.add(element);
            }
          }
        }
        return filteredElements;
      }
    }

    // 处理复合选择器：tag.class[attr]（属性存在性）
    final classAndAttrExists = plan.classAndAttrExists;
    if (classAndAttrExists != null) {
      if (classAndAttrExists.className.isNotEmpty &&
          classAndAttrExists.attribute.isNotEmpty) {
        // 先按标签和类名查找元素
        final elements = classAndAttrExists.tag != null
            ? soup.findAll(
                classAndAttrExists.tag,
                class_: classAndAttrExists.className,
              )
            : soup.findAll('*', class_: classAndAttrExists.className);

        // 然后按属性存在性过滤
        final filteredElements = <dynamic>[];
        for (final element in elements) {
          if (element.attributes[classAndAttrExists.attribute] != null) {
            filteredElements.add(element);
          }
        }
        return filteredElements;
      }
    }

    // 处理属性选择器
    // 1. 属性存在性选择器 tag[attr]
    final attrExists = plan.attrExists;
    if (attrExists != null) {
      if (attrExists.attribute.isNotEmpty) {
        // 获取所有指定标签的元素（如果没有指定标签，则获取所有元素）
        if (attrExists.tag != null) {
          return soup.findAll(
            attrExists.tag,
            attrs: {attrExists.attribute: true},
          );
        } else {
          return soup.findAll('*', attrs: {attrExists.attribute: true});
        }
      }
    }

    // 2. 属性值选择器 tag[attr^="value"], tag[attr=="value"], tag[attr~="pattern"]
    final attrValueSelector = plan.attrValue;
    if (attrValueSelector != null) {
      if (attrValueSelector.attribute.isNotEmpty &&
          attrValueSelector.operator != null &&
          attrValueSelector.value != null) {
        // 获取所有指定标签的元素（如果没有指定标签，则获取所有元素）
        final elements = attrValueSelector.tag != null
            ? soup.findAll(attrValueSelector.tag)
            : soup.findAll('*');

        final filteredElements = <dynamic>[];
        for (final element in elements) {
          final attrValue = element.attributes[attrValueSelector.attribute];
          if (attrValue != null) {
            if (_matchesAttribute(
              attrValue,
              attrValueSelector,
              normalize: true,
            )) {
              filteredElements.add(element);
            }
          }
        }
        return filteredElements;
      }
    }

    // 处理单个选择器
    final contains = plan.contains;
    if (contains != null) {
      final candidates = contains.preSelector.isNotEmpty
          ? findElementBySelector(soup, contains.preSelector)
          : soup.findAll('*');

      final results = <dynamic>[];
      for (final el in candidates) {
        final t = (el.text ?? '')
            .replaceAll('\n', ' ')
            .replaceAll(_whitespaceRegExp, ' ')
            .trim();
        final ok = contains.groups.any((g) => g.every((n) => t.contains(n)));
        if (ok) {
          results.add(el);
        }
      }
      return results;
    }

    final nthChild = plan.nthChild;
    if (nthChild != null) {
      final children = soup.children;
      if (children.isNotEmpty &&
          nthChild.index > 0 &&
          nthChild.index <= children.length) {
        final child = children[nthChild.index - 1]; // nth-child是1-based索引

        if (nthChild.tag != null &&
            nthChild.tag!.isNotEmpty &&
            nthChild.tag != '*') {
          if (child.name.toLowerCase() == nthChild.tag!.toLowerCase()) {
            return [child];
          }
          return [];
        } else {
          return [child];
        }
      }
    } else if (plan.nthChildTag != null) {
      final tag = plan.nthChildTag!;
      final children = soup.children;
      return children
          .where((child) => child.name.toLowerCase() == tag.toLowerCase())
          .toList();
    } else if (plan.firstChild) {
      // 第一个子元素
      final children = soup.children;
      if (children.isNotEmpty) {
        return [children.first];
      }
    } else if (plan.lastChild) {
      // 最后一个子元素
      final children = soup.children;
      if (children.isNotEmpty) {
        return [children.last];
      }
    } else if (plan.nthNode != null) {
      final nthNode = plan.nthNode!;
      final nodes = soup.nodes;
      if (nodes.isNotEmpty &&
          nthNode.index > 0 &&
          nthNode.index <= nodes.length) {
        final node = nodes[nthNode.index - 1]; // nth-node是1-based索引

        if (nthNode.tag != null &&
            nthNode.tag!.isNotEmpty &&
            nthNode.tag != '*') {
          if (node.name.toLowerCase() == nthNode.tag!.toLowerCase()) {
            return [node];
          }
          return [];
        } else {
          return [node];
        }
      }
    } else if (plan.nthNodeTag != null) {
      final tag = plan.nthNodeTag!;
      final nodes = soup.nodes;
      return nodes
          .where((node) => node.name.toLowerCase() == tag.toLowerCase())
          .toList();
    } else if (plan.firstNode) {
      // 第一个子元素
      final nodes = soup.nodes;
      if (nodes.isNotEmpty) {
        return [nodes.first];
      }
    } else if (plan.lastNode) {
      // 最后一个子元素
      final nodes = soup.nodes;
      if (nodes.isNotEmpty) {
        return [nodes.last];
      }
    } else if (plan.idSelector != null) {
      // ID选择器
      final idSelector = plan.idSelector!;
      if (idSelector.tag != null) {
        return soup.findAll(idSelector.tag, id: idSelector.value);
      } else {
        return soup.findAll('*', id: idSelector.value);
      }
    } else if (plan.classSelector != null) {
      // 类选择器
      final classSelector = plan.classSelector!;
      if (classSelector.tag != null) {
        return soup.findAll(
          classSelector.tag,
          attrs: {'class': classSelector.value},
        );
      } else {
        return soup.findAll('*', attrs: {'class': classSelector.value});
      }
    } else if (plan.tagSelector != null) {
      // 简单标签选择器
      return soup.findAll(plan.tagSelector);
    }

    return [];
  }

  bool _matchesAttribute(
    String attrValue,
    _AttributeSelector selector, {
    required bool normalize,
  }) {
    final value = selector.value;
    if (value == null) return false;
    final compareValue = normalize
        ? normalizeHrefForComparison(attrValue)
        : attrValue;
    switch (selector.operator) {
      case '^':
        return compareValue.startsWith(value);
      case '=':
        return compareValue == value;
      case '~':
        return selector.regex?.hasMatch(attrValue) ?? false;
    }
    return false;
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
    return extractFieldValueSync(element, fieldConfig);
  }

  /// 根据字段配置同步提取字段值列表
  List<String> extractFieldValueSync(
    dynamic element,
    Map<String, dynamic> fieldConfig,
  ) {
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
        values.add(
          value.replaceAll('\n', ' ').replaceAll(_whitespaceRegExp, ' '),
        );
      }
    }

    return values;
  }

  /// 根据字段配置提取第一个字段值（向前兼容）
  Future<String?> extractFirstFieldValue(
    dynamic element,
    Map<String, dynamic> fieldConfig,
  ) async {
    final values = extractFieldValueSync(element, fieldConfig);
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
        final regex = _getCachedRegExp(args);
        final match = regex.firstMatch(value);
        if (match != null) {
          final template = format ?? r'$0';
          return template.replaceAllMapped(_filterGroupRegExp, (m) {
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
            _singleQuoteRegExp.firstMatch(s) ??
            _doubleQuoteRegExp.firstMatch(s);
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
