import 'package:flutter/foundation.dart';

import '../../models/app_models.dart';
import '../storage/storage_service.dart';

class DisplaySettingsManager extends ChangeNotifier {
  final StorageService _storageService;

  bool _showCoverImages = true;
  Set<String> _visibleTags = Set.unmodifiable(
    TagType.values.map((tag) => tag.name),
  );
  bool _isLoading = true;

  DisplaySettingsManager(this._storageService) {
    _loadSettings();
  }

  bool get showCoverImages => _showCoverImages;
  Set<String> get visibleTags => _visibleTags;
  bool get isLoading => _isLoading;

  Future<void> setShowCoverImages(bool value) async {
    if (_showCoverImages == value) return;

    await _storageService.saveShowCoverImages(value);
    _showCoverImages = value;
    notifyListeners();
  }

  Future<void> setVisibleTags(Set<String> tags) async {
    final nextTags = Set<String>.unmodifiable(tags);
    if (setEquals(_visibleTags, nextTags)) return;

    await _storageService.saveVisibleTags(nextTags.toList());
    _visibleTags = nextTags;
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    try {
      _showCoverImages = await _storageService.loadShowCoverImages();
    } catch (_) {
      _showCoverImages = true;
    }
    try {
      await _storageService.loadVisibleTags();
      _visibleTags = Set.unmodifiable(_storageService.visibleTags);
    } catch (_) {
      _visibleTags = Set.unmodifiable(TagType.values.map((tag) => tag.name));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
