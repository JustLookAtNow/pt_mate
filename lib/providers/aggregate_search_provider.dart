import 'package:flutter/foundation.dart';

import '../models/app_models.dart';
import '../services/aggregate_search_service.dart';

/// 聚合搜索状态管理
class AggregateSearchProvider extends ChangeNotifier {
  // 搜索相关状态
  String _searchKeyword = '';
  String _selectedStrategy = '';
  String _sortBy = 'none';
  bool _sortAscending = false;
  List<AggregateSearchConfig> _searchConfigs = [];
  bool _loading = true;
  
  // 搜索结果状态
  bool _searching = false;
  List<AggregateSearchResultItem> _searchResults = [];
  Map<String, String> _searchErrors = {};
  AggregateSearchProgress? _searchProgress;
  AggregateSearchCancelToken? _cancelToken;
  bool _cancelled = false;

  // 标签筛选状态
  final Set<TagType> _includedTags = {};
  final Set<TagType> _excludedTags = {};

  // Getters
  String get searchKeyword => _searchKeyword;
  String get selectedStrategy => _selectedStrategy;
  String get sortBy => _sortBy;
  bool get sortAscending => _sortAscending;
  List<AggregateSearchConfig> get searchConfigs => _searchConfigs;
  bool get loading => _loading;
  bool get searching => _searching;
  List<AggregateSearchResultItem> get searchResults => _searchResults;
  Map<String, String> get searchErrors => _searchErrors;
  AggregateSearchProgress? get searchProgress => _searchProgress;
  AggregateSearchCancelToken? get cancelToken => _cancelToken;
  bool get cancelled => _cancelled;
  Set<TagType> get includedTags => _includedTags;
  Set<TagType> get excludedTags => _excludedTags;

  // 获取经过标签筛选后的结果
  List<AggregateSearchResultItem> get filteredResults {
    if (_includedTags.isEmpty && _excludedTags.isEmpty) {
      return _searchResults;
    }
    return _searchResults.where((item) {
      // 包含筛选:必须包含所有选中的标签
      for (final tag in _includedTags) {
        if (!item.torrent.tags.contains(tag)) return false;
      }
      // 排除筛选:不能包含任何选中的标签
      for (final tag in _excludedTags) {
        if (item.torrent.tags.contains(tag)) return false;
      }
      return true;
    }).toList();
  }

  // Setters
  void setSearchKeyword(String keyword) {
    _searchKeyword = keyword;
    notifyListeners();
  }

  void setSelectedStrategy(String strategy) {
    _selectedStrategy = strategy;
    notifyListeners();
  }

  void setSortBy(String sortBy) {
    _sortBy = sortBy;
    notifyListeners();
  }

  void setSortAscending(bool ascending) {
    _sortAscending = ascending;
    notifyListeners();
  }

  void setSearchConfigs(List<AggregateSearchConfig> configs) {
    _searchConfigs = configs;
    notifyListeners();
  }

  void setLoading(bool loading) {
    _loading = loading;
    notifyListeners();
  }

  void setSearching(bool searching) {
    _searching = searching;
    notifyListeners();
  }

  void setSearchResults(List<AggregateSearchResultItem> results) {
    _searchResults = results;
    notifyListeners();
  }

  void setSearchErrors(Map<String, String> errors) {
    _searchErrors = errors;
    notifyListeners();
  }

  void setSearchProgress(AggregateSearchProgress? progress) {
    _searchProgress = progress;
    notifyListeners();
  }

  void createCancelToken() {
    _cancelToken = AggregateSearchCancelToken();
    _cancelled = false;
  }

  void cancelSearch() {
    if (_cancelToken != null) {
      _cancelToken!.cancel();
      _cancelled = true;
      notifyListeners();
    }
  }

  void clearSearchResults() {
    _searchResults.clear();
    _searchErrors.clear();
    _searchProgress = null;
    notifyListeners();
  }

  /// 重置所有状态（用于清理）
  void reset() {
    _searchKeyword = '';
    _selectedStrategy = '';
    _sortBy = 'none';
    _sortAscending = false;
    _searchConfigs = [];
    _loading = true;
    _searching = false;
    _searchResults = [];
    _searchErrors = {};
    _searchProgress = null;
    _cancelToken = null;
    _cancelled = false;
    _includedTags.clear();
    _excludedTags.clear();
    notifyListeners();
  }

  /// 设置包含标签
  void setIncludedTags(Set<TagType> tags) {
    _includedTags.clear();
    _includedTags.addAll(tags);
    notifyListeners();
  }

  /// 设置排除标签
  void setExcludedTags(Set<TagType> tags) {
    _excludedTags.clear();
    _excludedTags.addAll(tags);
    notifyListeners();
  }

  /// 清空标签筛选
  void clearTagFilters() {
    _includedTags.clear();
    _excludedTags.clear();
    notifyListeners();
  }

  /// 初始化默认选中的策略
  void initializeDefaultStrategy() {
    if (_searchConfigs.isNotEmpty) {
      // 如果当前选中的策略不在激活列表中，或者没有选中策略，重新选择
      if (_selectedStrategy.isEmpty || !_searchConfigs.any((config) => config.id == _selectedStrategy)) {
        // 优先选择"所有站点"配置
        final allSitesConfig = _searchConfigs.firstWhere(
          (config) => config.isAllSitesType,
          orElse: () => _searchConfigs.first,
        );
        _selectedStrategy = allSitesConfig.id;
        notifyListeners();
      }
    } else {
      // 如果没有配置，清空选中的策略
      if (_selectedStrategy.isNotEmpty) {
        _selectedStrategy = '';
        notifyListeners();
      }
    }
  }
}