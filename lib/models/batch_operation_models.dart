import '../services/downloader/downloader_config.dart';
import 'app_models.dart';

abstract class BatchRetryContext {
  const BatchRetryContext();
}

class BatchDownloadContext extends BatchRetryContext {
  final DownloaderConfig clientConfig;
  final String password;
  final String? category;
  final List<String> tags;
  final String? savePath;
  final bool? autoTMM;
  final bool? startPaused;
  final Map<String, SiteConfig>? sitesById;

  const BatchDownloadContext({
    required this.clientConfig,
    required this.password,
    required this.category,
    required this.tags,
    required this.savePath,
    required this.autoTMM,
    required this.startPaused,
    this.sitesById,
  });

  BatchDownloadContext copyWith({
    DownloaderConfig? clientConfig,
    String? password,
    String? category,
    List<String>? tags,
    String? savePath,
    bool? autoTMM,
    bool? startPaused,
    Map<String, SiteConfig>? sitesById,
  }) => BatchDownloadContext(
    clientConfig: clientConfig ?? this.clientConfig,
    password: password ?? this.password,
    category: category ?? this.category,
    tags: tags ?? this.tags,
    savePath: savePath ?? this.savePath,
    autoTMM: autoTMM ?? this.autoTMM,
    startPaused: startPaused ?? this.startPaused,
    sitesById: sitesById ?? this.sitesById,
  );
}

class BatchFailureRecord<T> {
  final T item;
  final String itemId;
  final String itemName;
  final String errorMessage;

  const BatchFailureRecord({
    required this.item,
    required this.itemId,
    required this.itemName,
    required this.errorMessage,
  });
}

class BatchProgressState<T> {
  final BatchOperationType actionType;
  final bool isRunning;
  final int trackedTotalCount;
  final int runTotalCount;
  final int runCompletedCount;
  final int successCount;
  final int failureCount;
  final String? currentItemName;
  final List<BatchFailureRecord<T>> failedItems;
  final BatchRetryContext? retryableContext;

  const BatchProgressState({
    required this.actionType,
    required this.isRunning,
    required this.trackedTotalCount,
    required this.runTotalCount,
    required this.runCompletedCount,
    required this.successCount,
    required this.failureCount,
    required this.currentItemName,
    required this.failedItems,
    this.retryableContext,
  });

  BatchProgressState<T> copyWith({
    BatchOperationType? actionType,
    bool? isRunning,
    int? trackedTotalCount,
    int? runTotalCount,
    int? runCompletedCount,
    int? successCount,
    int? failureCount,
    String? currentItemName,
    bool clearCurrentItemName = false,
    List<BatchFailureRecord<T>>? failedItems,
    BatchRetryContext? retryableContext,
    bool keepRetryableContext = true,
  }) => BatchProgressState<T>(
    actionType: actionType ?? this.actionType,
    isRunning: isRunning ?? this.isRunning,
    trackedTotalCount: trackedTotalCount ?? this.trackedTotalCount,
    runTotalCount: runTotalCount ?? this.runTotalCount,
    runCompletedCount: runCompletedCount ?? this.runCompletedCount,
    successCount: successCount ?? this.successCount,
    failureCount: failureCount ?? this.failureCount,
    currentItemName: clearCurrentItemName
        ? null
        : currentItemName ?? this.currentItemName,
    failedItems: failedItems ?? this.failedItems,
    retryableContext: keepRetryableContext
        ? (retryableContext ?? this.retryableContext)
        : retryableContext,
  );

  double get progress =>
      runTotalCount == 0 ? 0 : runCompletedCount / runTotalCount;

  String get actionLabel {
    switch (actionType) {
      case BatchOperationType.favorite:
        return '批量收藏';
      case BatchOperationType.download:
        return '批量下载';
    }
  }

  String get titleLabel {
    final isRetryRun = trackedTotalCount > runTotalCount;
    final prefix = isRetryRun ? '$actionLabel重试' : actionLabel;
    return '$prefix $runCompletedCount/$runTotalCount';
  }
}

String formatBatchError(Object error) {
  final text = error.toString().trim();
  return text.startsWith('Exception: ') ? text.substring(11) : text;
}

List<BatchFailureRecord<T>> buildBatchFailureRecords<T>({
  required Map<String, BatchItemState> itemStates,
  required Map<String, String> itemErrors,
  required Map<String, T> trackedItems,
  required String Function(T item) itemNameOf,
}) {
  final failures = <BatchFailureRecord<T>>[];
  trackedItems.forEach((itemId, item) {
    if (itemStates[itemId] != BatchItemState.failed) {
      return;
    }
    failures.add(
      BatchFailureRecord<T>(
        item: item,
        itemId: itemId,
        itemName: itemNameOf(item),
        errorMessage: itemErrors[itemId] ?? '操作失败',
      ),
    );
  });
  return List<BatchFailureRecord<T>>.unmodifiable(failures);
}

BatchProgressState<T> buildBatchProgressState<T>({
  required BatchOperationType actionType,
  required bool isRunning,
  required int runTotalCount,
  required int runCompletedCount,
  required Map<String, BatchItemState> itemStates,
  required Map<String, String> itemErrors,
  required Map<String, T> trackedItems,
  required String Function(T item) itemNameOf,
  String? currentItemName,
  BatchRetryContext? retryableContext,
}) {
  var successCount = 0;
  var failureCount = 0;
  for (final state in itemStates.values) {
    switch (state) {
      case BatchItemState.idle:
      case BatchItemState.running:
        break;
      case BatchItemState.success:
        successCount++;
        break;
      case BatchItemState.failed:
        failureCount++;
        break;
    }
  }

  return BatchProgressState<T>(
    actionType: actionType,
    isRunning: isRunning,
    trackedTotalCount: trackedItems.length,
    runTotalCount: runTotalCount,
    runCompletedCount: runCompletedCount,
    successCount: successCount,
    failureCount: failureCount,
    currentItemName: currentItemName,
    failedItems: buildBatchFailureRecords(
      itemStates: itemStates,
      itemErrors: itemErrors,
      trackedItems: trackedItems,
      itemNameOf: itemNameOf,
    ),
    retryableContext: retryableContext,
  );
}
