// Callback parameter names are part of the transaction test/consumer API.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

typedef SecureValueReader = Future<String?> Function(String key);
typedef SecureValueWriter = Future<void> Function(String key, String value);
typedef SecureValueDeleter = Future<void> Function(String key);
typedef SecureManifestWriter = Future<bool> Function(String key, String value);
typedef SecureTransactionHook = Future<void> Function(String revision);

enum SecureStorageTransactionStage {
  manifestRead,
  activeRead,
  staging,
  verification,
  preparation,
  commit,
  postCommit,
}

/// An error whose string representation never contains a secure-storage key.
class SecureStorageTransactionException implements Exception {
  const SecureStorageTransactionException(this.stage, [this.cause]);

  final SecureStorageTransactionStage stage;
  final Object? cause;

  @override
  String toString() => 'SecureStorageTransactionException(${stage.name})';
}

enum SecureStorageMutationType { upsert, delete }

class SecureStorageMutation {
  const SecureStorageMutation.upsert(this.logicalKey, String newValue)
    : type = SecureStorageMutationType.upsert,
      value = newValue;

  const SecureStorageMutation.delete(this.logicalKey)
    : type = SecureStorageMutationType.delete,
      value = null;

  final String logicalKey;
  final SecureStorageMutationType type;
  final String? value;
}

class SecureStorageCommitResult {
  const SecureStorageCommitResult({
    required this.revision,
    required this.activeEntryCount,
    required this.pendingCleanupCount,
  });

  final String revision;
  final int activeEntryCount;
  final int pendingCleanupCount;
}

class SecureStorageCleanupResult {
  const SecureStorageCleanupResult({
    required this.attemptedCount,
    required this.deletedCount,
    required this.failedCount,
    required this.skippedActiveCount,
    required this.pendingCount,
  });

  static const empty = SecureStorageCleanupResult(
    attemptedCount: 0,
    deletedCount: 0,
    failedCount: 0,
    skippedActiveCount: 0,
    pendingCount: 0,
  );

  final int attemptedCount;
  final int deletedCount;
  final int failedCount;
  final int skippedActiveCount;
  final int pendingCount;
}

class SecureStorageReconcileResult {
  const SecureStorageReconcileResult({
    required this.hasManifest,
    required this.activeEntryCount,
    required this.missingActiveEntryCount,
    required this.unavailableActiveEntryCount,
    required this.cleanup,
  });

  final bool hasManifest;
  final int activeEntryCount;
  final int missingActiveEntryCount;
  final int unavailableActiveEntryCount;
  final SecureStorageCleanupResult cleanup;

  bool get isHealthy =>
      missingActiveEntryCount == 0 && unavailableActiveEntryCount == 0;
}

/// Provides revision-based commits over a key/value secure storage.
///
/// The active logical-to-physical mapping is committed with one
/// [SharedPreferences.setString] call. Secure values are staged and verified
/// before that pointer switch. An optional platform durability barrier runs
/// after verification and before any companion preparation or manifest write.
/// Cleanup is best effort and never targets a key referenced by the current
/// manifest.
///
/// Calls made through one instance are serialized. Callers must use one shared
/// instance when writing, because SharedPreferences does not provide a
/// cross-instance compare-and-swap primitive.
class SecureStorageTransaction {
  SecureStorageTransaction({
    required SharedPreferences preferences,
    required SecureValueReader readSecureValue,
    required SecureValueWriter writeSecureValue,
    required SecureValueDeleter deleteSecureValue,
    SecureManifestWriter? writeManifest,
    SecureTransactionHook? beforeManifestBarrier,
    String Function()? createRevisionId,
    this.manifestPreferenceKey = defaultManifestPreferenceKey,
    this.physicalKeyPrefix = defaultPhysicalKeyPrefix,
  }) : _preferences = preferences,
       _readSecureValue = readSecureValue,
       _writeSecureValue = writeSecureValue,
       _deleteSecureValue = deleteSecureValue,
       _writeManifest = writeManifest ?? preferences.setString,
       _beforeManifestBarrier = beforeManifestBarrier,
       _createRevisionId = createRevisionId ?? _defaultRevisionId;

  static const String defaultManifestPreferenceKey =
      'secureStorage.transaction.manifest.v1';
  static const String defaultPhysicalKeyPrefix = 'secureStorage.revision.v1';

  static String _defaultRevisionId() => const Uuid().v4();

  final SharedPreferences _preferences;
  final SecureValueReader _readSecureValue;
  final SecureValueWriter _writeSecureValue;
  final SecureValueDeleter _deleteSecureValue;
  final SecureManifestWriter _writeManifest;
  final SecureTransactionHook? _beforeManifestBarrier;
  final String Function() _createRevisionId;
  final String manifestPreferenceKey;
  final String physicalKeyPrefix;

  Future<void> _operationTail = Future<void>.value();

  /// Reads the active version. Before the first manifest commit, the logical
  /// key itself is treated as the legacy physical key.
  Future<String?> read(String logicalKey) => _serialize(() async {
    _validateLogicalKey(logicalKey);
    final manifest = _loadManifest();
    final physicalKey = manifest == null
        ? logicalKey
        : manifest.entries[logicalKey];
    if (physicalKey == null) {
      return null;
    }

    try {
      final value = await _readSecureValue(physicalKey);
      if (manifest != null && value == null) {
        throw const SecureStorageTransactionException(
          SecureStorageTransactionStage.activeRead,
        );
      }
      return value;
    } on SecureStorageTransactionException {
      rethrow;
    } catch (error) {
      throw SecureStorageTransactionException(
        SecureStorageTransactionStage.activeRead,
        error,
      );
    }
  });

  /// Applies all [mutations] as one revision.
  ///
  /// Duplicate logical keys are rejected instead of relying on mutation order.
  Future<SecureStorageCommitResult> commit(
    Iterable<SecureStorageMutation> mutations, {
    SecureTransactionHook? beforeManifestCommit,
    SecureTransactionHook? afterManifestCommit,
  }) => _serialize(
    () => _commit(
      mutations.toList(growable: false),
      beforeManifestCommit: beforeManifestCommit,
      afterManifestCommit: afterManifestCommit,
    ),
  );

  /// Returns the non-sensitive active revision identifier, if initialized.
  Future<String?> activeRevision() =>
      _serialize(() async => _loadManifest()?.revision);

  /// Reports only whether an active logical key belongs to one of the given
  /// non-sensitive categories. Key names never leave this coordinator.
  Future<bool> hasActiveLogicalKeyWithPrefix(Iterable<String> prefixes) =>
      _serialize(() async {
        final normalized = prefixes.where((value) => value.isNotEmpty).toList();
        if (normalized.isEmpty) return false;
        final manifest = _loadManifest();
        if (manifest == null) return false;
        return manifest.entries.keys.any(
          (key) => normalized.any(key.startsWith),
        );
      });

  /// Retries deletion of stale physical keys recorded in the manifest.
  Future<SecureStorageCleanupResult> cleanup() =>
      _serialize(_cleanupCurrentManifest);

  /// Checks that every active mapping resolves to a value, then retries stale
  /// key cleanup. It reports counts only and never exposes key names.
  Future<SecureStorageReconcileResult> reconcile({
    bool cleanupIfHealthy = true,
  }) => _serialize(() async {
    final manifest = _loadManifest();
    if (manifest == null) {
      return const SecureStorageReconcileResult(
        hasManifest: false,
        activeEntryCount: 0,
        missingActiveEntryCount: 0,
        unavailableActiveEntryCount: 0,
        cleanup: SecureStorageCleanupResult.empty,
      );
    }

    var missing = 0;
    var unavailable = 0;
    for (final physicalKey in manifest.entries.values) {
      try {
        if (await _readSecureValue(physicalKey) == null) {
          missing++;
        }
      } catch (_) {
        unavailable++;
      }
    }

    // Never delete the previous revision while the active revision is
    // incomplete or unreadable. The stale values are the last local recovery
    // material available until the user restores an external backup.
    final cleanupResult = missing == 0 && unavailable == 0 && cleanupIfHealthy
        ? await _cleanupLoadedManifest(manifest)
        : SecureStorageCleanupResult(
            attemptedCount: 0,
            deletedCount: 0,
            failedCount: 0,
            skippedActiveCount: 0,
            pendingCount: manifest.garbage.length,
          );
    return SecureStorageReconcileResult(
      hasManifest: true,
      activeEntryCount: manifest.entries.length,
      missingActiveEntryCount: missing,
      unavailableActiveEntryCount: unavailable,
      cleanup: cleanupResult,
    );
  });

  Future<SecureStorageCommitResult> _commit(
    List<SecureStorageMutation> mutations, {
    SecureTransactionHook? beforeManifestCommit,
    SecureTransactionHook? afterManifestCommit,
  }) async {
    if (mutations.isEmpty) {
      throw ArgumentError('At least one mutation is required.');
    }

    final seenLogicalKeys = <String>{};
    for (final mutation in mutations) {
      _validateLogicalKey(mutation.logicalKey);
      if (!seenLogicalKeys.add(mutation.logicalKey)) {
        throw ArgumentError('Duplicate logical keys are not allowed.');
      }
      if (mutation.type == SecureStorageMutationType.upsert &&
          mutation.value == null) {
        throw ArgumentError('An upsert value is required.');
      }
    }

    final previous = _loadManifest();
    final previousEntries = Map<String, String>.of(
      previous?.entries ?? const <String, String>{},
    );
    final nextEntries = Map<String, String>.of(previousEntries);
    final garbage = <String>{...?previous?.garbage};
    final stagedKeys = <String>[];
    final revision = _createRevisionId().trim();
    if (revision.isEmpty) {
      throw ArgumentError('The revision id must not be empty.');
    }

    var upsertIndex = 0;
    try {
      for (final mutation in mutations) {
        final oldPhysicalKey = previous == null
            ? mutation.logicalKey
            : previousEntries[mutation.logicalKey];

        if (mutation.type == SecureStorageMutationType.delete) {
          nextEntries.remove(mutation.logicalKey);
          if (oldPhysicalKey != null) {
            garbage.add(oldPhysicalKey);
          }
          continue;
        }

        final physicalKey = '$physicalKeyPrefix.$revision.$upsertIndex';
        upsertIndex++;
        if (previousEntries.containsValue(physicalKey) ||
            stagedKeys.contains(physicalKey)) {
          throw const SecureStorageTransactionException(
            SecureStorageTransactionStage.staging,
          );
        }

        try {
          await _writeSecureValue(physicalKey, mutation.value!);
        } catch (error) {
          throw SecureStorageTransactionException(
            SecureStorageTransactionStage.staging,
            error,
          );
        }
        stagedKeys.add(physicalKey);

        String? verifiedValue;
        try {
          verifiedValue = await _readSecureValue(physicalKey);
        } catch (error) {
          throw SecureStorageTransactionException(
            SecureStorageTransactionStage.verification,
            error,
          );
        }
        if (verifiedValue != mutation.value) {
          throw const SecureStorageTransactionException(
            SecureStorageTransactionStage.verification,
          );
        }

        nextEntries[mutation.logicalKey] = physicalKey;
        if (oldPhysicalKey != null) {
          garbage.add(oldPhysicalKey);
        }
      }
    } catch (_) {
      await _discardUncommitted(stagedKeys);
      rethrow;
    }

    garbage.removeAll(nextEntries.values);
    final nextManifest = _SecureStorageManifest(
      revision: revision,
      entries: nextEntries,
      garbage: garbage,
    );
    final encodedManifest = nextManifest.encode();

    if (_beforeManifestBarrier != null || beforeManifestCommit != null) {
      try {
        await _beforeManifestBarrier?.call(revision);
        await beforeManifestCommit?.call(revision);
      } catch (error) {
        await _discardUncommitted(stagedKeys);
        throw SecureStorageTransactionException(
          SecureStorageTransactionStage.preparation,
          error,
        );
      }
    }

    var committed = false;
    Object? commitError;
    try {
      committed = await _writeManifest(manifestPreferenceKey, encodedManifest);
    } catch (error) {
      commitError = error;
    }

    // SharedPreferences updates its in-process cache before Android reports
    // whether the synchronous disk commit succeeded. Cache equality therefore
    // cannot turn `false` (or an exception) into success. Once the manifest
    // write has been attempted its disk outcome can be ambiguous, so staged
    // values must be retained rather than risking a persisted pointer to data
    // that we delete as an alleged rollback.
    final persisted = _preferences.getString(manifestPreferenceKey);
    if (commitError != null || !committed || persisted != encodedManifest) {
      throw SecureStorageTransactionException(
        SecureStorageTransactionStage.commit,
        commitError ?? StateError('Manifest commit was not confirmed.'),
      );
    }

    if (afterManifestCommit != null) {
      try {
        await afterManifestCommit(revision);
      } catch (error) {
        // The active pointer has already moved. Keep both the staged values
        // and previous revision so startup recovery can finish the companion
        // ordinary-preferences commit without fabricating a rollback.
        throw SecureStorageTransactionException(
          SecureStorageTransactionStage.postCommit,
          error,
        );
      }
    }

    return SecureStorageCommitResult(
      revision: revision,
      activeEntryCount: nextEntries.length,
      pendingCleanupCount: nextManifest.garbage.length,
    );
  }

  Future<SecureStorageCleanupResult> _cleanupCurrentManifest() async {
    final manifest = _loadManifest();
    if (manifest == null) {
      return SecureStorageCleanupResult.empty;
    }
    return _cleanupLoadedManifest(manifest);
  }

  Future<SecureStorageCleanupResult> _cleanupLoadedManifest(
    _SecureStorageManifest manifest,
  ) async {
    if (manifest.garbage.isEmpty) {
      return SecureStorageCleanupResult.empty;
    }

    // Reload before deleting so even another transaction coordinator cannot
    // make us delete a key that is active now.
    final current = _loadManifest();
    if (current == null) {
      return SecureStorageCleanupResult.empty;
    }
    final activeKeys = current.entries.values.toSet();
    final remaining = <String>{};
    var attempted = 0;
    var deleted = 0;
    var failed = 0;
    var skippedActive = 0;

    for (final physicalKey in current.garbage) {
      if (activeKeys.contains(physicalKey)) {
        skippedActive++;
        continue;
      }
      attempted++;
      try {
        await _deleteSecureValue(physicalKey);
        deleted++;
      } catch (_) {
        failed++;
        remaining.add(physicalKey);
      }
    }

    var manifestUpdated = true;
    if (!_sameSet(current.garbage, remaining)) {
      final reducedManifest = current.copyWith(garbage: remaining);
      final encodedManifest = reducedManifest.encode();
      var manifestCommitted = false;
      try {
        manifestCommitted = await _writeManifest(
          manifestPreferenceKey,
          encodedManifest,
        );
      } catch (_) {
        // Keep the previous garbage list when persistence is ambiguous. A
        // later startup can retry idempotent deletion of those stale values.
      }
      manifestUpdated =
          manifestCommitted &&
          _preferences.getString(manifestPreferenceKey) == encodedManifest;
    }

    return SecureStorageCleanupResult(
      attemptedCount: attempted,
      deletedCount: deleted,
      failedCount: failed,
      skippedActiveCount: skippedActive,
      pendingCount: manifestUpdated ? remaining.length : current.garbage.length,
    );
  }

  Future<void> _discardUncommitted(Iterable<String> stagedKeys) async {
    final activeKeys = _loadManifest()?.entries.values.toSet() ?? <String>{};
    for (final physicalKey in stagedKeys) {
      if (activeKeys.contains(physicalKey)) {
        continue;
      }
      try {
        await _deleteSecureValue(physicalKey);
      } catch (_) {
        // An orphan is preferable to deleting a possibly active value. A
        // future storage-wide maintenance pass may remove unreachable keys.
      }
    }
  }

  _SecureStorageManifest? _loadManifest() {
    final encoded = _preferences.getString(manifestPreferenceKey);
    if (encoded == null) {
      return null;
    }
    try {
      return _SecureStorageManifest.decode(encoded);
    } catch (error) {
      throw SecureStorageTransactionException(
        SecureStorageTransactionStage.manifestRead,
        error,
      );
    }
  }

  Future<T> _serialize<T>(Future<T> Function() operation) async {
    final predecessor = _operationTail;
    final release = Completer<void>();
    _operationTail = release.future;
    await predecessor;
    try {
      return await operation();
    } finally {
      release.complete();
    }
  }

  static void _validateLogicalKey(String logicalKey) {
    if (logicalKey.isEmpty) {
      throw ArgumentError('The logical key must not be empty.');
    }
  }

  static bool _sameSet(Set<String> left, Set<String> right) =>
      left.length == right.length && left.containsAll(right);
}

class _SecureStorageManifest {
  const _SecureStorageManifest({
    required this.revision,
    required this.entries,
    required this.garbage,
  });

  static const int schemaVersion = 1;

  final String revision;
  final Map<String, String> entries;
  final Set<String> garbage;

  String encode() {
    final sortedEntries = Map<String, String>.fromEntries(
      entries.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    final sortedGarbage = garbage.toList()..sort();
    return jsonEncode({
      'version': schemaVersion,
      'revision': revision,
      'entries': sortedEntries,
      'garbage': sortedGarbage,
    });
  }

  _SecureStorageManifest copyWith({Set<String>? garbage}) =>
      _SecureStorageManifest(
        revision: revision,
        entries: entries,
        garbage: garbage ?? this.garbage,
      );

  static _SecureStorageManifest decode(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != schemaVersion ||
        decoded['revision'] is! String ||
        (decoded['revision'] as String).isEmpty ||
        decoded['entries'] is! Map<String, dynamic> ||
        decoded['garbage'] is! List<dynamic>) {
      throw const FormatException('Invalid secure storage manifest.');
    }

    final entries = <String, String>{};
    for (final entry in (decoded['entries'] as Map<String, dynamic>).entries) {
      if (entry.key.isEmpty ||
          entry.value is! String ||
          (entry.value as String).isEmpty) {
        throw const FormatException('Invalid secure storage manifest entry.');
      }
      entries[entry.key] = entry.value as String;
    }
    if (entries.values.toSet().length != entries.length) {
      throw const FormatException('Duplicate secure storage physical key.');
    }

    final garbage = <String>{};
    for (final value in decoded['garbage'] as List<dynamic>) {
      if (value is! String || value.isEmpty) {
        throw const FormatException('Invalid secure storage garbage entry.');
      }
      garbage.add(value);
    }

    return _SecureStorageManifest(
      revision: decoded['revision'] as String,
      entries: entries,
      garbage: garbage,
    );
  }
}
