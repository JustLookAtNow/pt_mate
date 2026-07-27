import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/services/storage/secure_storage_transaction.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences preferences;
  late Map<String, String> secureValues;
  late List<String> events;
  late int revision;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    secureValues = <String, String>{};
    events = <String>[];
    revision = 0;
  });

  SecureStorageTransaction createTransaction({
    SecureValueReader? read,
    SecureValueWriter? write,
    SecureValueDeleter? delete,
    SecureManifestWriter? writeManifest,
    SecureTransactionHook? beforeManifestBarrier,
  }) => SecureStorageTransaction(
    preferences: preferences,
    readSecureValue:
        read ??
        (key) async {
          events.add('read');
          return secureValues[key];
        },
    writeSecureValue:
        write ??
        (key, value) async {
          events.add('write');
          secureValues[key] = value;
        },
    deleteSecureValue:
        delete ??
        (key) async {
          events.add('delete');
          secureValues.remove(key);
        },
    writeManifest:
        writeManifest ??
        (key, value) async {
          events.add('commit');
          return preferences.setString(key, value);
        },
    beforeManifestBarrier: beforeManifestBarrier,
    createRevisionId: () => 'revision-${revision++}',
  );

  Map<String, dynamic> readManifest() =>
      jsonDecode(
            preferences.getString(
              SecureStorageTransaction.defaultManifestPreferenceKey,
            )!,
          )
          as Map<String, dynamic>;

  test('reads legacy key until the first manifest is committed', () async {
    secureValues['logical-a'] = 'legacy-value';
    final transaction = createTransaction();

    expect(await transaction.read('logical-a'), 'legacy-value');

    await transaction.commit([
      const SecureStorageMutation.upsert('logical-a', 'new-value'),
    ]);
    final manifest = readManifest();
    final activePhysicalKey =
        (manifest['entries'] as Map<String, dynamic>)['logical-a'] as String;

    expect(activePhysicalKey, isNot('logical-a'));
    expect(secureValues['logical-a'], 'legacy-value');
    expect(manifest['garbage'], ['logical-a']);
    expect(await transaction.read('logical-a'), 'new-value');

    final nextStartup = createTransaction();
    final reconcileResult = await nextStartup.reconcile();

    expect(reconcileResult.cleanup.deletedCount, 1);
    expect(secureValues['logical-a'], isNull);
    expect(await nextStartup.read('logical-a'), 'new-value');
  });

  test(
    'reports active logical categories without exposing physical values',
    () async {
      final transaction = createTransaction();
      await transaction.commit([
        const SecureStorageMutation.upsert('site.cookie.site-a', 'cookie'),
        const SecureStorageMutation.upsert('proxy.password', 'password'),
      ]);

      expect(
        await transaction.hasActiveLogicalKeyWithPrefix(const ['site.cookie.']),
        isTrue,
      );
      expect(
        await transaction.hasActiveLogicalKeyWithPrefix(const ['site.apiKey.']),
        isFalse,
      );
    },
  );

  test(
    'stages and verifies before committing, then defers legacy cleanup',
    () async {
      secureValues['logical-a'] = 'old-value';
      final transaction = createTransaction();

      final result = await transaction.commit([
        const SecureStorageMutation.upsert('logical-a', 'new-value'),
      ]);

      expect(events, ['write', 'read', 'commit']);
      expect(result.activeEntryCount, 1);
      expect(result.pendingCleanupCount, 1);
      expect(readManifest()['garbage'], ['logical-a']);
      expect(secureValues['logical-a'], 'old-value');

      events.clear();
      final nextStartup = createTransaction();
      final reconcileResult = await nextStartup.reconcile();

      expect(reconcileResult.cleanup.deletedCount, 1);
      expect(events, ['read', 'delete', 'commit']);
      expect((readManifest()['garbage'] as List<dynamic>), isEmpty);
      expect(secureValues['logical-a'], isNull);
    },
  );

  test(
    'staging failure keeps the previous manifest and active value',
    () async {
      secureValues['logical-a'] = 'old-a';
      secureValues['logical-b'] = 'old-b';
      var writeCount = 0;
      final transaction = createTransaction(
        write: (key, value) async {
          writeCount++;
          if (writeCount == 2) {
            throw StateError('injected staging failure');
          }
          secureValues[key] = value;
        },
      );

      await expectLater(
        transaction.commit([
          const SecureStorageMutation.upsert('logical-a', 'new-a'),
          const SecureStorageMutation.upsert('logical-b', 'new-b'),
        ]),
        throwsA(
          isA<SecureStorageTransactionException>().having(
            (error) => error.stage,
            'stage',
            SecureStorageTransactionStage.staging,
          ),
        ),
      );

      expect(
        preferences.getString(
          SecureStorageTransaction.defaultManifestPreferenceKey,
        ),
        isNull,
      );
      expect(secureValues, {'logical-a': 'old-a', 'logical-b': 'old-b'});
      expect(await transaction.read('logical-a'), 'old-a');
    },
  );

  test(
    'verification mismatch discards staging without moving manifest',
    () async {
      secureValues['logical-a'] = 'old-value';
      final transaction = createTransaction(
        read: (key) async {
          if (key.startsWith(
            SecureStorageTransaction.defaultPhysicalKeyPrefix,
          )) {
            return 'corrupted-value';
          }
          return secureValues[key];
        },
      );

      await expectLater(
        transaction.commit([
          const SecureStorageMutation.upsert('logical-a', 'new-value'),
        ]),
        throwsA(
          isA<SecureStorageTransactionException>().having(
            (error) => error.stage,
            'stage',
            SecureStorageTransactionStage.verification,
          ),
        ),
      );

      expect(
        preferences.getString(
          SecureStorageTransaction.defaultManifestPreferenceKey,
        ),
        isNull,
      );
      expect(secureValues, {'logical-a': 'old-value'});
    },
  );

  test(
    'manifest commit failure keeps old pointer and retains ambiguous staging',
    () async {
      secureValues['logical-a'] = 'old-value';
      final transaction = createTransaction(
        writeManifest: (key, value) async {
          throw StateError('injected commit failure');
        },
      );

      await expectLater(
        transaction.commit([
          const SecureStorageMutation.upsert('logical-a', 'new-value'),
        ]),
        throwsA(
          isA<SecureStorageTransactionException>().having(
            (error) => error.stage,
            'stage',
            SecureStorageTransactionStage.commit,
          ),
        ),
      );

      expect(
        preferences.getString(
          SecureStorageTransaction.defaultManifestPreferenceKey,
        ),
        isNull,
      );
      expect(secureValues['logical-a'], 'old-value');
      expect(secureValues.values, contains('new-value'));
      expect(await transaction.read('logical-a'), 'old-value');
    },
  );

  test('preparation failure never moves the active manifest', () async {
    secureValues['logical-a'] = 'old-value';
    final transaction = createTransaction();

    await expectLater(
      transaction.commit(
        [const SecureStorageMutation.upsert('logical-a', 'new-value')],
        beforeManifestCommit: (_) async {
          throw StateError('injected preparation failure');
        },
      ),
      throwsA(
        isA<SecureStorageTransactionException>().having(
          (error) => error.stage,
          'stage',
          SecureStorageTransactionStage.preparation,
        ),
      ),
    );

    expect(
      preferences.getString(
        SecureStorageTransaction.defaultManifestPreferenceKey,
      ),
      isNull,
    );
    expect(secureValues, {'logical-a': 'old-value'});
  });

  test(
    'durability barrier runs after verification and before preparation',
    () async {
      final transaction = createTransaction(
        beforeManifestBarrier: (_) async => events.add('barrier'),
      );

      await transaction.commit(
        [const SecureStorageMutation.upsert('logical-a', 'new-value')],
        beforeManifestCommit: (_) async => events.add('prepare'),
        afterManifestCommit: (_) async => events.add('post-commit'),
      );

      expect(events, [
        'write',
        'read',
        'barrier',
        'prepare',
        'commit',
        'post-commit',
      ]);
    },
  );

  test('durability barrier failure never switches the manifest', () async {
    secureValues['logical-a'] = 'old-value';
    final transaction = createTransaction(
      beforeManifestBarrier: (_) async {
        events.add('barrier');
        throw StateError('injected durability failure');
      },
    );

    await expectLater(
      transaction.commit([
        const SecureStorageMutation.upsert('logical-a', 'new-value'),
      ]),
      throwsA(
        isA<SecureStorageTransactionException>().having(
          (error) => error.stage,
          'stage',
          SecureStorageTransactionStage.preparation,
        ),
      ),
    );

    expect(events, ['write', 'read', 'barrier', 'delete']);
    expect(
      preferences.getString(
        SecureStorageTransaction.defaultManifestPreferenceKey,
      ),
      isNull,
    );
    expect(secureValues, {'logical-a': 'old-value'});
  });

  test('post-commit failure keeps complete new and old revisions', () async {
    secureValues['logical-a'] = 'old-value';
    final transaction = createTransaction();

    await expectLater(
      transaction.commit(
        [const SecureStorageMutation.upsert('logical-a', 'new-value')],
        afterManifestCommit: (_) async {
          throw StateError('injected companion commit failure');
        },
      ),
      throwsA(
        isA<SecureStorageTransactionException>().having(
          (error) => error.stage,
          'stage',
          SecureStorageTransactionStage.postCommit,
        ),
      ),
    );

    final manifest = readManifest();
    expect(manifest['garbage'], ['logical-a']);
    expect(secureValues['logical-a'], 'old-value');
    expect(await transaction.read('logical-a'), 'new-value');
  });

  test(
    'manifest callback error after persistence is ambiguous and fail-closed',
    () async {
      secureValues['logical-a'] = 'old-value';
      final transaction = createTransaction(
        writeManifest: (key, value) async {
          await preferences.setString(key, value);
          throw StateError('injected error after persistence');
        },
      );

      await expectLater(
        transaction.commit([
          const SecureStorageMutation.upsert('logical-a', 'new-value'),
        ]),
        throwsA(
          isA<SecureStorageTransactionException>().having(
            (error) => error.stage,
            'stage',
            SecureStorageTransactionStage.commit,
          ),
        ),
      );

      expect(await transaction.read('logical-a'), 'new-value');
      expect(secureValues['logical-a'], 'old-value');
      expect(secureValues.values, contains('new-value'));
    },
  );

  test(
    'manifest false result is never promoted by the updated cache',
    () async {
      secureValues['logical-a'] = 'old-value';
      final transaction = createTransaction(
        writeManifest: (key, value) async {
          await preferences.setString(key, value);
          return false;
        },
      );

      await expectLater(
        transaction.commit([
          const SecureStorageMutation.upsert('logical-a', 'new-value'),
        ]),
        throwsA(
          isA<SecureStorageTransactionException>().having(
            (error) => error.stage,
            'stage',
            SecureStorageTransactionStage.commit,
          ),
        ),
      );

      expect(await transaction.read('logical-a'), 'new-value');
      expect(secureValues['logical-a'], 'old-value');
      expect(secureValues.values, contains('new-value'));
    },
  );

  test(
    'orphaned staging from process exit leaves legacy version active',
    () async {
      secureValues['logical-a'] = 'old-value';
      secureValues['${SecureStorageTransaction.defaultPhysicalKeyPrefix}.revision-0.0'] =
          'verified-but-uncommitted';

      final restarted = createTransaction();

      expect(await restarted.read('logical-a'), 'old-value');
      expect(
        preferences.getString(
          SecureStorageTransaction.defaultManifestPreferenceKey,
        ),
        isNull,
      );
    },
  );

  test(
    'process exit after multi-item staging or verification keeps complete old revision',
    () async {
      final transaction = createTransaction();
      await transaction.commit([
        const SecureStorageMutation.upsert('logical-a', 'old-a'),
        const SecureStorageMutation.upsert('logical-b', 'old-b'),
      ]);
      final manifestBeforeExit = preferences.getString(
        SecureStorageTransaction.defaultManifestPreferenceKey,
      );

      // Staged values have been written and can even have been read back, but
      // the single active manifest pointer has not moved when the process dies.
      secureValues['${SecureStorageTransaction.defaultPhysicalKeyPrefix}.crash.0'] =
          'new-a';
      secureValues['${SecureStorageTransaction.defaultPhysicalKeyPrefix}.crash.1'] =
          'new-b';
      expect(
        preferences.getString(
          SecureStorageTransaction.defaultManifestPreferenceKey,
        ),
        manifestBeforeExit,
      );

      final restarted = createTransaction();
      expect(await restarted.read('logical-a'), 'old-a');
      expect(await restarted.read('logical-b'), 'old-b');
    },
  );

  test(
    'process exit after partial cleanup still reads complete new revision',
    () async {
      final transaction = createTransaction();
      await transaction.commit([
        const SecureStorageMutation.upsert('logical-a', 'old-a'),
        const SecureStorageMutation.upsert('logical-b', 'old-b'),
      ]);
      await transaction.cleanup();
      await transaction.commit([
        const SecureStorageMutation.upsert('logical-a', 'new-a'),
        const SecureStorageMutation.upsert('logical-b', 'new-b'),
      ]);
      final manifest = readManifest();
      final garbage = List<String>.from(manifest['garbage'] as List<dynamic>);
      expect(garbage, hasLength(2));

      // One old value was deleted, then the process exited before the reduced
      // garbage manifest could be persisted.
      secureValues.remove(garbage.first);
      final restarted = createTransaction();
      expect(await restarted.read('logical-a'), 'new-a');
      expect(await restarted.read('logical-b'), 'new-b');

      final reconciliation = await restarted.reconcile();
      expect(reconciliation.isHealthy, isTrue);
      expect(reconciliation.cleanup.pendingCount, 0);
      expect(readManifest()['garbage'], isEmpty);
      expect(await restarted.read('logical-a'), 'new-a');
      expect(await restarted.read('logical-b'), 'new-b');
    },
  );

  test(
    'ambiguous cleanup manifest write stays pending with complete active data',
    () async {
      var failAfterPersist = false;
      final transaction = createTransaction(
        writeManifest: (key, value) async {
          await preferences.setString(key, value);
          if (failAfterPersist) {
            throw StateError('injected error after cleanup persistence');
          }
          return true;
        },
      );
      await transaction.commit([
        const SecureStorageMutation.upsert('logical-a', 'old-a'),
      ]);
      await transaction.commit([
        const SecureStorageMutation.upsert('logical-a', 'new-a'),
      ]);
      final pendingBefore = (readManifest()['garbage'] as List<dynamic>).length;
      failAfterPersist = true;

      final cleanup = await transaction.cleanup();

      expect(cleanup.pendingCount, pendingBefore);
      expect(readManifest()['garbage'], isEmpty);
      expect(await createTransaction().read('logical-a'), 'new-a');
    },
  );

  test(
    'cleanup failure is retryable and does not affect committed reads',
    () async {
      secureValues['logical-a'] = 'old-value';
      var failCleanup = true;
      final transaction = createTransaction(
        delete: (key) async {
          events.add('delete');
          if (failCleanup) {
            throw StateError('injected cleanup failure');
          }
          secureValues.remove(key);
        },
      );

      final commitResult = await transaction.commit([
        const SecureStorageMutation.upsert('logical-a', 'new-value'),
      ]);

      expect(commitResult.pendingCleanupCount, 1);
      expect(await transaction.read('logical-a'), 'new-value');
      expect(readManifest()['garbage'], ['logical-a']);

      final failedCleanup = await transaction.cleanup();

      expect(failedCleanup.failedCount, 1);
      expect(failedCleanup.pendingCount, 1);
      expect(secureValues['logical-a'], 'old-value');
      expect(readManifest()['garbage'], ['logical-a']);

      failCleanup = false;
      final cleanupResult = await transaction.cleanup();

      expect(cleanupResult.deletedCount, 1);
      expect(cleanupResult.pendingCount, 0);
      expect(secureValues['logical-a'], isNull);
      expect(readManifest()['garbage'], isEmpty);
      expect(await transaction.read('logical-a'), 'new-value');
    },
  );

  test(
    'cleanup never deletes a physical key active in current manifest',
    () async {
      final deletedKeys = <String>[];
      final transaction = createTransaction(
        delete: (key) async {
          deletedKeys.add(key);
          secureValues.remove(key);
        },
      );
      await transaction.commit([
        const SecureStorageMutation.upsert('logical-a', 'value-a'),
      ]);
      final manifest = readManifest();
      final activePhysicalKey =
          (manifest['entries'] as Map<String, dynamic>)['logical-a'] as String;
      manifest['garbage'] = [activePhysicalKey];
      await preferences.setString(
        SecureStorageTransaction.defaultManifestPreferenceKey,
        jsonEncode(manifest),
      );
      deletedKeys.clear();

      final result = await transaction.cleanup();

      expect(result.skippedActiveCount, 1);
      expect(deletedKeys, isEmpty);
      expect(secureValues[activePhysicalKey], 'value-a');
      expect(readManifest()['garbage'], isEmpty);
    },
  );

  test(
    'delete commits absence before cleaning the old physical value',
    () async {
      secureValues['logical-a'] = 'legacy-value';
      final transaction = createTransaction();

      await transaction.commit([
        const SecureStorageMutation.delete('logical-a'),
      ]);

      expect(await transaction.read('logical-a'), isNull);
      expect(secureValues['logical-a'], 'legacy-value');
      expect(readManifest()['entries'], isEmpty);
      expect(readManifest()['garbage'], ['logical-a']);

      final nextStartup = createTransaction();
      final reconcileResult = await nextStartup.reconcile();

      expect(reconcileResult.cleanup.deletedCount, 1);
      expect(secureValues['logical-a'], isNull);
      expect(await nextStartup.read('logical-a'), isNull);
    },
  );

  test('reconcile reports missing and unavailable active values', () async {
    final transaction = createTransaction();
    await transaction.commit([
      const SecureStorageMutation.upsert('logical-a', 'value-a'),
      const SecureStorageMutation.upsert('logical-b', 'value-b'),
    ]);
    final entries = readManifest()['entries'] as Map<String, dynamic>;
    secureValues.remove(entries['logical-a']);
    final unavailableKey = entries['logical-b'] as String;

    final checkingTransaction = createTransaction(
      read: (key) async {
        if (key == unavailableKey) {
          throw StateError('injected read failure');
        }
        return secureValues[key];
      },
    );
    final result = await checkingTransaction.reconcile();

    expect(result.hasManifest, isTrue);
    expect(result.activeEntryCount, 2);
    expect(result.missingActiveEntryCount, 1);
    expect(result.unavailableActiveEntryCount, 1);
    expect(result.isHealthy, isFalse);
  });

  for (final failureMode in ['missing', 'unavailable']) {
    test(
      'reconcile preserves old revisions when active value is $failureMode',
      () async {
        secureValues['logical-a'] = 'legacy-value';
        final transaction = createTransaction();
        await transaction.commit([
          const SecureStorageMutation.upsert('logical-a', 'revision-one'),
        ]);
        await transaction.commit([
          const SecureStorageMutation.upsert('logical-a', 'revision-two'),
        ]);

        final before = readManifest();
        final activePhysicalKey =
            (before['entries'] as Map<String, dynamic>)['logical-a'] as String;
        final garbageBefore = List<String>.from(
          before['garbage'] as List<dynamic>,
        );
        expect(garbageBefore, hasLength(2));

        if (failureMode == 'missing') {
          secureValues.remove(activePhysicalKey);
        }
        events.clear();
        final nextStartup = createTransaction(
          read: (key) async {
            events.add('read');
            if (failureMode == 'unavailable' && key == activePhysicalKey) {
              throw StateError('injected active read failure');
            }
            return secureValues[key];
          },
        );

        final result = await nextStartup.reconcile();

        expect(result.isHealthy, isFalse);
        expect(result.cleanup.attemptedCount, 0);
        expect(result.cleanup.pendingCount, garbageBefore.length);
        expect(events, isNot(contains('delete')));
        expect(readManifest()['garbage'], garbageBefore);
        for (final oldPhysicalKey in garbageBefore) {
          expect(secureValues[oldPhysicalKey], isNotNull);
        }
      },
    );
  }

  test('concurrent commits are serialized by one coordinator', () async {
    final firstWriteStarted = Completer<void>();
    final releaseFirstWrite = Completer<void>();
    var writeCount = 0;
    final transaction = createTransaction(
      write: (key, value) async {
        writeCount++;
        if (writeCount == 1) {
          firstWriteStarted.complete();
          await releaseFirstWrite.future;
        }
        secureValues[key] = value;
      },
    );

    final first = transaction.commit([
      const SecureStorageMutation.upsert('logical-a', 'value-a'),
    ]);
    await firstWriteStarted.future;
    final second = transaction.commit([
      const SecureStorageMutation.upsert('logical-b', 'value-b'),
    ]);

    await Future<void>.delayed(Duration.zero);
    expect(writeCount, 1);
    releaseFirstWrite.complete();
    await Future.wait([first, second]);

    expect(await transaction.read('logical-a'), 'value-a');
    expect(await transaction.read('logical-b'), 'value-b');
  });
}
