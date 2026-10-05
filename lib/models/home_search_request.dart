import 'package:flutter/foundation.dart';

enum HomeSearchMode { currentSite, aggregate }

@immutable
class HomeSearchRequest {
  const HomeSearchRequest({
    required this.mode,
    required this.keyword,
    this.categoryIndex,
    this.strategyId,
    this.sequence = 0,
  });

  final HomeSearchMode mode;
  final String keyword;
  final int? categoryIndex;
  final String? strategyId;
  final int sequence;
}
