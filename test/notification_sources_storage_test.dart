import 'package:budget_book/core/database/db_schema.dart';
import 'package:budget_book/features/classification/data/repositories/brand_metadata_repository_impl.dart';
import 'package:budget_book/features/classification/domain/entities/brand_metadata.dart';
import 'package:budget_book/features/notifications/data/datasources/notification_platform_channel.dart';
import 'package:budget_book/features/notifications/data/repositories/notification_source_repository_impl.dart';
import 'package:budget_book/features/notifications/domain/entities/notification_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

/// 알림 수집 대상 앱 / 브랜드 업종 캐시를 실제 SQLite 로 검증한다.
///
/// 이 두 테이블은 "사용자가 끈 앱이 계속 수집된다", "같은 브랜드를 매번 다시
/// 조회한다" 처럼 조용히 잘못 동작하는 종류의 버그가 나오는 곳이다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  /// 네이티브가 발견했다고 보고할 앱 목록.
  late List<Map<String, Object?>> nativeSeen;

  /// 네이티브에 마지막으로 밀어 넣은 허용 목록.
  List<String>? pushedToNative;

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: DbSchema.databaseVersion,
      onCreate: (Database db, int version) async {
        for (final String statement in DbSchema.createStatements) {
          await db.execute(statement);
        }
      },
    );

    nativeSeen = <Map<String, Object?>>[];
    pushedToNative = null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(NotificationPlatformChannel.methodChannelName),
      (MethodCall call) async {
        switch (call.method) {
          case 'seenSources':
            return nativeSeen;
          case 'setEnabledSources':
            final Map<Object?, Object?> args =
                call.arguments as Map<Object?, Object?>;
            pushedToNative =
                (args['packages'] as List<Object?>).cast<String>();
            return null;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(NotificationPlatformChannel.methodChannelName),
      null,
    );
    await db.close();
  });

  NotificationSourceRepositoryImpl buildRepo() =>
      NotificationSourceRepositoryImpl(
        db: db,
        channel: NotificationPlatformChannel(),
      );

  Map<String, Object?> seen(
    String packageName,
    String displayName, {
    int lastSeenAt = 1000,
  }) =>
      <String, Object?>{
        'packageName': packageName,
        'displayName': displayName,
        'lastSeenAt': lastSeenAt,
        'detectedAt': 500,
      };

  group('알림 수집 대상 앱', () {
    test('네이티브가 발견한 앱이 목록에 들어오고 기본은 비허용', () async {
      nativeSeen = <Map<String, Object?>>[
        seen('com.kbcard.cxh.appcard', 'KB Pay'),
        seen('com.shinhancard.smartshinhan', '신한플레이'),
      ];

      final NotificationSourceConfig config = await buildRepo().load();

      expect(config.sources.length, 2);
      expect(config.sources.every((NotificationSource s) => !s.enabled), isTrue);
      // 아무것도 고르지 않았으면 전체 수집으로 동작한다(빈 가계부를 막는다).
      expect(config.isConfigured, isFalse);
      expect(config.isFiltering, isFalse);
    });

    test('선택을 저장하면 네이티브 캐시에도 반영된다', () async {
      nativeSeen = <Map<String, Object?>>[
        seen('com.kbcard.cxh.appcard', 'KB Pay'),
        seen('com.shinhancard.smartshinhan', '신한플레이'),
      ];
      final NotificationSourceRepositoryImpl repo = buildRepo();
      await repo.load();

      await repo.setEnabled(<String>{'com.kbcard.cxh.appcard'});

      expect(pushedToNative, <String>['com.kbcard.cxh.appcard']);

      final NotificationSourceConfig after = await repo.load();
      expect(after.enabledCount, 1);
      expect(after.enabled.single.packageName, 'com.kbcard.cxh.appcard');
      expect(after.isFiltering, isTrue);
    });

    test('다시 감지되어도 사용자의 선택을 지우지 않는다', () async {
      nativeSeen = <Map<String, Object?>>[seen('com.a', 'A앱')];
      final NotificationSourceRepositoryImpl repo = buildRepo();
      await repo.load();
      await repo.setEnabled(<String>{'com.a'});

      // 같은 앱이 새 알림을 보내 다시 보고된다.
      nativeSeen = <Map<String, Object?>>[
        seen('com.a', 'A앱 (이름 변경)', lastSeenAt: 9999),
      ];
      final NotificationSourceConfig after = await repo.load();

      expect(after.sources.single.enabled, isTrue, reason: '선택이 유지돼야 한다');
      expect(after.sources.single.displayName, 'A앱 (이름 변경)');
      expect(
        after.sources.single.lastSeenAt!.millisecondsSinceEpoch,
        9999,
      );
    });

    test('토글은 즉시 네이티브에 동기화된다', () async {
      nativeSeen = <Map<String, Object?>>[
        seen('com.a', 'A앱'),
        seen('com.b', 'B앱'),
      ];
      final NotificationSourceRepositoryImpl repo = buildRepo();
      await repo.load();

      await repo.toggle(packageName: 'com.b', enabled: true);
      expect(pushedToNative, <String>['com.b']);

      await repo.toggle(packageName: 'com.a', enabled: true);
      expect(pushedToNative, containsAll(<String>['com.a', 'com.b']));

      await repo.toggle(packageName: 'com.b', enabled: false);
      expect(pushedToNative, <String>['com.a']);
    });

    test('시작 시 동기화는 DB 를 기준으로 네이티브를 덮어쓴다', () async {
      nativeSeen = <Map<String, Object?>>[seen('com.a', 'A앱')];
      final NotificationSourceRepositoryImpl repo = buildRepo();
      await repo.load();
      await repo.setEnabled(<String>{'com.a'});
      pushedToNative = null;

      await repo.syncToNative();

      expect(pushedToNative, <String>['com.a']);
    });

    test('모두 끄면 빈 목록을 밀어 넣는다(= 전체 수집으로 되돌아간다)', () async {
      nativeSeen = <Map<String, Object?>>[seen('com.a', 'A앱')];
      final NotificationSourceRepositoryImpl repo = buildRepo();
      await repo.load();
      await repo.setEnabled(<String>{'com.a'});

      await repo.setEnabled(<String>{});

      expect(pushedToNative, isEmpty);
      final NotificationSourceConfig after = await repo.load();
      expect(after.isFiltering, isFalse);
    });

    test('패키지명은 중복 저장되지 않는다', () async {
      nativeSeen = <Map<String, Object?>>[seen('com.a', 'A앱')];
      final NotificationSourceRepositoryImpl repo = buildRepo();
      await repo.load();
      await repo.load();
      await repo.load();

      expect((await repo.load()).sources.length, 1);
    });
  });

  group('브랜드 업종 캐시', () {
    test('저장한 뒤 정규화된 이름으로 찾을 수 있다', () async {
      final BrandMetadataRepositoryImpl repo = BrandMetadataRepositoryImpl(db);
      await repo.save(
        BrandMetadata(
          brand: '메가커피',
          normalizedBrand: '메가커피',
          industry: '커피전문점',
          category: '식비',
          subcategory: '카페',
          source: BrandMetadataSource.kakao,
          lookedUpAt: DateTime(2026, 8, 5),
        ),
      );

      final BrandMetadata? found = await repo.find('메가커피');
      expect(found, isNotNull);
      expect(found!.category, '식비');
      expect(found.isUsable, isTrue);
      expect(await repo.count(), 1);
    });

    test('같은 브랜드를 다시 저장해도 한 행만 남는다', () async {
      final BrandMetadataRepositoryImpl repo = BrandMetadataRepositoryImpl(db);
      for (int i = 0; i < 3; i++) {
        await repo.save(
          BrandMetadata(
            brand: '메가커피',
            normalizedBrand: '메가커피',
            category: '식비',
            subcategory: '카페',
            source: BrandMetadataSource.kakao,
            lookedUpAt: DateTime(2026, 8, 5),
          ),
        );
      }
      expect(await repo.count(), 1);
    });

    test('못 찾음도 저장되고 조회된다 (재조회 방지)', () async {
      final BrandMetadataRepositoryImpl repo = BrandMetadataRepositoryImpl(db);
      await repo.save(
        BrandMetadata.notFound(
          brand: '무명가게',
          normalizedBrand: '무명가게',
          source: BrandMetadataSource.kakao,
          lookedUpAt: DateTime(2026, 8, 5),
        ),
      );

      final BrandMetadata? found = await repo.find('무명가게');
      expect(found, isNotNull, reason: '조회한 적 있다는 사실이 남아야 한다');
      expect(found!.found, isFalse);
      expect(found.isUsable, isFalse);
    });

    test('사용자 지정은 자동 조회 결과로 덮이지 않는다', () async {
      final BrandMetadataRepositoryImpl repo = BrandMetadataRepositoryImpl(db);
      await repo.markUserModified(
        brand: '메가커피',
        category: '식비',
        subcategory: '디저트',
      );

      await repo.save(
        BrandMetadata(
          brand: '메가커피',
          normalizedBrand: '메가커피',
          category: '식비',
          subcategory: '카페',
          source: BrandMetadataSource.kakao,
          lookedUpAt: DateTime(2026, 8, 6),
        ),
      );

      expect((await repo.find('메가커피'))!.subcategory, '디저트');
    });

    test('사용자가 다시 고치면 사용자 값끼리는 갱신된다', () async {
      final BrandMetadataRepositoryImpl repo = BrandMetadataRepositoryImpl(db);
      await repo.markUserModified(
        brand: '메가커피',
        category: '식비',
        subcategory: '디저트',
      );
      await repo.markUserModified(
        brand: '메가커피',
        category: '식비',
        subcategory: '카페',
      );

      expect((await repo.find('메가커피'))!.subcategory, '카페');
      expect(await repo.count(), 1);
    });

    test('캐시를 비우면 자동 조회분만 사라진다', () async {
      final BrandMetadataRepositoryImpl repo = BrandMetadataRepositoryImpl(db);
      await repo.save(
        BrandMetadata(
          brand: '자동A',
          normalizedBrand: '자동a',
          category: '식비',
          subcategory: '카페',
          source: BrandMetadataSource.kakao,
          lookedUpAt: DateTime(2026, 8, 5),
        ),
      );
      await repo.markUserModified(
        brand: '수동B',
        category: '생활',
        subcategory: '편의점',
      );

      expect(await repo.clearLookupCache(), 1);
      expect(await repo.count(), 1);
      expect((await repo.findAll()).single.userModified, isTrue);
    });
  });

  group('스키마 v7 마이그레이션', () {
    test('v6 DB 에 새 테이블/인덱스를 추가할 수 있다', () async {
      // 새 테이블이 없는 상태를 만들어 마이그레이션 SQL 을 그대로 실행한다.
      await db.execute('DROP TABLE ${DbSchema.tableNotificationSources}');
      await db.execute('DROP TABLE ${DbSchema.tableBrandMetadata}');

      for (final String statement in DbSchema.migrations[7]!) {
        await db.execute(statement);
      }

      // 실제로 쓸 수 있는지 확인한다(CREATE 만 성공해도 컬럼이 틀릴 수 있다).
      final BrandMetadataRepositoryImpl brands =
          BrandMetadataRepositoryImpl(db);
      await brands.save(
        BrandMetadata(
          brand: '테스트',
          normalizedBrand: '테스트',
          category: '식비',
          subcategory: '카페',
          source: BrandMetadataSource.kakao,
          lookedUpAt: DateTime(2026, 8, 5),
        ),
      );
      expect(await brands.count(), 1);

      nativeSeen = <Map<String, Object?>>[seen('com.a', 'A앱')];
      expect((await buildRepo().load()).sources.length, 1);
    });

    test('마이그레이션을 두 번 실행해도 실패하지 않는다', () async {
      for (final String statement in DbSchema.migrations[7]!) {
        await db.execute(statement);
      }
      for (final String statement in DbSchema.migrations[7]!) {
        await db.execute(statement);
      }
    });
  });
  group('스키마 v8 마이그레이션', () {
    test('v7 DB 에 잔액/자산종류 컬럼을 추가할 수 있다', () async {
      // 새 컬럼이 없는 상태를 만든다. SQLite 는 DROP COLUMN 지원이 제한적이라
      // 테이블을 다시 만들어 v7 모양을 재현한다.
      await db.execute('DROP TABLE ${DbSchema.tableTransactions}');
      await db.execute('DROP TABLE ${DbSchema.tableAccounts}');
      await db.execute(
        'CREATE TABLE ${DbSchema.tableTransactions} ('
        '${DbSchema.tId} INTEGER PRIMARY KEY AUTOINCREMENT, '
        '${DbSchema.tMerchantRaw} TEXT NOT NULL, '
        '${DbSchema.tBrand} TEXT NOT NULL, '
        '${DbSchema.tAmount} INTEGER NOT NULL, '
        '${DbSchema.tPaymentDatetime} INTEGER NOT NULL, '
        "${DbSchema.tDirection} TEXT NOT NULL DEFAULT 'expense', "
        '${DbSchema.tIsAssetTransfer} INTEGER NOT NULL DEFAULT 0)',
      );
      await db.execute(
        'CREATE TABLE ${DbSchema.tableAccounts} ('
        '${DbSchema.acId} INTEGER PRIMARY KEY AUTOINCREMENT, '
        '${DbSchema.acName} TEXT NOT NULL, '
        '${DbSchema.acBalance} INTEGER NOT NULL DEFAULT 0)',
      );
      await db.insert(DbSchema.tableAccounts, <String, Object?>{
        DbSchema.acName: '기존 계좌',
        DbSchema.acBalance: 1000000,
      });

      for (final String statement in DbSchema.migrations[8]!) {
        await db.execute(statement);
      }

      // 기존 계좌의 잔액은 그대로 남아야 한다.
      final List<Map<String, Object?>> rows =
          await db.query(DbSchema.tableAccounts);
      expect(rows.single[DbSchema.acBalance], 1000000);

      // **기준 시각이 0이 아니어야 한다.** 0이면 과거 거래가 전부 소급
      // 반영되어 사용자가 입력한 잔액이 갑자기 바뀐다.
      expect(
        rows.single[DbSchema.acBalanceAsOf],
        isA<int>().having((int v) => v, '기준 시각', greaterThan(0)),
      );
    });

    test('v8 마이그레이션을 두 번 실행해도 인덱스 생성은 실패하지 않는다', () async {
      // ADD COLUMN 은 두 번 실행할 수 없으므로 멱등한 문장만 확인한다.
      final List<String> idempotent = DbSchema.migrations[8]!
          .where((String s) => s.contains('IF NOT EXISTS'))
          .toList();
      expect(idempotent, isNotEmpty);
      for (int i = 0; i < 2; i++) {
        for (final String statement in idempotent) {
          await db.execute(statement);
        }
      }
    });
  });
}
