import 'package:flutter/foundation.dart';

import '../storage/storage_service.dart';

class DisplaySettingsManager extends ChangeNotifier {
  final StorageService _storageService;

  bool _showCoverImages = true;
  bool _isLoading = true;

  DisplaySettingsManager(this._storageService) {
    _loadSettings();
  }

  bool get showCoverImages => _showCoverImages;
  bool get isLoading => _isLoading;

  Future<void> setShowCoverImages(bool value) async {
    if (_showCoverImages == value) return;

    await _storageService.saveShowCoverImages(value);
    _showCoverImages = value;
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    try {
      _showCoverImages = await _storageService.loadShowCoverImages();
    } catch (_) {
      _showCoverImages = true;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
