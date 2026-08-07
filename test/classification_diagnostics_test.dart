import 'dart:io';

import 'package:budget_book/core/constants/app_categories.dart';
import 'package:budget_book/core/constants/classification_source.dart';
import 'package:budget_book/core/database/db_schema.dart';
import 'package:budget_book/features/classification/data/repositories/classification_diagnostics_repository_impl.dart';
import 'package:budget_book/features/classification/domain/entities/classification_diagnostics.dart';
import 'package:budget_book/features/classification/domain/services/place_category_mapper.dart';
import 'package:budget_book/features/parsing/domain/entities/parsed_payment.dart';
import 'package:budget_book/features/transactions/data/datasources/transaction_local_datasource.dart';
import 'package:budget_book/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:budget_book/features/transactions/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

import 'support/legacy_schema.dart';

/// 분류 진단.
///
/// 매핑표를 **추측으로** 늘리지 않으려면 실제로 무엇이 막히는지 알아야 한다.
/// 이 계측이 없으면 "브런치도 넣어야 하나" 를 감으로 결정하게 된다.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late ClassificationDiagnosticsRepositoryImpl diagnostics;
  late TransactionRepositoryImpl transactions;

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
    diagnostics = ClassificationDiagnosticsRepositoryImpl(db);
    transactions = TransactionRepositoryImpl(TransactionLocalDataSource(db));
  });

  tearDown(() async => db.close());

  int seq = 0;
  Future<void> addTransaction({
    required ClassificationSource source,
    AiStatus aiStatus = AiStatus.none,
    bool needsReview = false,
  }) async {
    final DateTime when = DateTime(2026, 8, 5, 12, seq++);
    await transactions.insert(
      Transaction(
        merchantRaw: '가맹점$seq',
        brand: '가맹점$seq',
        amount: 1000,
        category: '식비',
        subcategory: '카페',
        method: PaymentMethodKind.card,
        paymentDatetime: when,
        rawNotification: 'x',
        fingerprint: 'tx|${when.microsecondsSinceEpoch}',
        classificationSource: source,
        aiStatus: aiStatus,
        needsReview: needsReview,
      ),
    );
  }

  group('미매핑 업종 수집', () {
    test('같은 업종은 행을 늘리지 않고 횟수만 올린다', () async {
      await diagnostics.recordUnmapped(
        categoryName: '음식점 > 브런치',
        sampleMerchant: '춘천브런치카페',
      );
      await diagnostics.recordUnmapped(
        categoryName: '음식점 > 브런치',
        sampleMerchant: '다른브런치',
      );

      final List<UnmappedPlaceCategory> all = await diagnostics.findUnmapped();

      expect(all, hasLength(1));
      expect(all.single.categoryName, '음식점 > 브런치');
      expect(all.single.hitCount, 2);
      // 처음 본 가맹점을 남긴다. 무엇을 뜻하는 업종인지 가늠하는 데 쓴다.
      expect(all.single.sampleMerchant, '춘천브런치카페');
    });

    test('자주 막힌 것부터 나온다', () async {
      await diagnostics.recordUnmapped(categoryName: '쇼핑 > 문구');
      for (int i = 0; i < 3; i++) {
        await diagnostics.recordUnmapped(categoryName: '음식점 > 브런치');
      }

      final List<UnmappedPlaceCategory> all = await diagnostics.findUnmapped();

      expect(all.map((UnmappedPlaceCategory u) => u.categoryName),
          <String>['음식점 > 브런치', '쇼핑 > 문구']);
    });

    test('빈 업종은 기록하지 않는다', () async {
      await diagnostics.recordUnmapped(categoryName: '   ');
      expect(await diagnostics.findUnmapped(), isEmpty);
    });

    test('비울 수 있다', () async {
      await diagnostics.recordUnmapped(categoryName: '음식점 > 브런치');
      await diagnostics.clearUnmapped();
      expect(await diagnostics.findUnmapped(), isEmpty);
    });
  });

  group('매퍼가 못 옮긴 업종을 알려 준다', () {
    const PlaceCategoryMapper mapper = PlaceCategoryMapper();

    test('옮기지 못한 원본 문자열을 그대로 담는다', () {
      final PlaceConsensus consensus = mapper.resolveConsensus(<String>[
        '알 수 없는 업종',
        '음식점 > 카페 > 커피전문점',
      ]);

      expect(consensus.unmapped, <String>['알 수 없는 업종']);
    });

    test('큰 분류로만 맞은 것도 근거로 남는다', () {
      // `브런치` 를 못 옮기고 `음식점` 으로 떨어졌다. 결과는 식비/기타가
      // 나오지만 정보는 사라졌다 — 사용자가 겪는 "식비 하나로만 들어간다" 다.
      final PlaceConsensus consensus =
          mapper.resolveConsensus(<String>['음식점 > 브런치']);

      expect(consensus.isConfident, isTrue, reason: '분류는 된다');
      expect(consensus.pair, const CategoryPair('식비', '기타'));
      expect(consensus.unmapped, <String>['음식점 > 브런치'],
          reason: '매핑표를 늘릴 자리로 지목돼야 한다');
    });

    test('구체적인 단계로 맞으면 근거로 남기지 않는다', () {
      final PlaceConsensus consensus =
          mapper.resolveConsensus(<String>['음식점 > 카페 > 커피전문점']);

      expect(consensus.pair, const CategoryPair('식비', '카페'));
      expect(consensus.unmapped, isEmpty);
    });

    test('전부 옮겼으면 비어 있다', () {
      final PlaceConsensus consensus = mapper.resolveConsensus(<String>[
        '음식점 > 카페 > 커피전문점',
        '음식점 > 카페',
      ]);

      expect(consensus.unmapped, isEmpty);
    });

    test('하나도 못 옮기면 전부 담긴다', () {
      final PlaceConsensus consensus = mapper.resolveConsensus(<String>[
        '알 수 없는 업종 하나',
        '알 수 없는 업종 둘',
      ]);

      expect(consensus.isConfident, isFalse);
      expect(consensus.unmapped, hasLength(2));
    });
  });

  group('파이프라인 지표', () {
    test('거래가 없으면 비어 있다', () async {
      final ClassificationDiagnostics data = await diagnostics.load();
      expect(data.isEmpty, isTrue);
      expect(data.autoClassifiedRate, 0, reason: '0으로 나누지 않는다');
    });

    test('분류 경로별 비율을 센다', () async {
      await addTransaction(source: ClassificationSource.seed);
      await addTransaction(source: ClassificationSource.seed);
      await addTransaction(source: ClassificationSource.rule);
      await addTransaction(
        source: ClassificationSource.pending,
        needsReview: true,
      );

      final ClassificationDiagnostics data = await diagnostics.load();

      expect(data.totalTransactions, 4);
      expect(data.brandExtractorRate, 0.5);
      expect(data.placeRuleRate, 0.25);
      // pending 은 "아직 아무도 분류하지 않음" 이므로 실패로 센다.
      expect(data.autoClassifiedRate, 0.75);
      expect(data.needsReview, 1);
    });

    test('AI 대기열 진입률을 센다', () async {
      await addTransaction(source: ClassificationSource.seed);
      await addTransaction(
        source: ClassificationSource.pending,
        aiStatus: AiStatus.pending,
      );
      await addTransaction(
        source: ClassificationSource.llm,
        aiStatus: AiStatus.completed,
      );

      final ClassificationDiagnostics data = await diagnostics.load();

      expect(data.aiPending, 1);
      expect(data.aiCompleted, 1);
      expect(data.aiQueueRate, closeTo(2 / 3, 0.001));
    });

    test('사용자 수정률을 센다', () async {
      await addTransaction(source: ClassificationSource.seed);
      await addTransaction(source: ClassificationSource.user);

      final ClassificationDiagnostics data = await diagnostics.load();

      expect(data.userCorrectionRate, 0.5);
    });

    test('장소 API 성공률은 캐시 기준이다', () async {
      final int now = DateTime.now().millisecondsSinceEpoch;
      Future<void> meta(String brand, {required bool found}) => db.insert(
            DbSchema.tableBrandMetadata,
            <String, Object?>{
              DbSchema.bmBrand: brand,
              DbSchema.bmNormalizedBrand: brand,
              DbSchema.bmSource: 'kakao',
              DbSchema.bmLookedUpAt: now,
              DbSchema.bmFound: found ? 1 : 0,
            },
          );

      await meta('스타벅스', found: true);
      await meta('메가커피', found: true);
      await meta('알수없는가게', found: false);

      final ClassificationDiagnostics data = await diagnostics.load();

      expect(data.brandLookupsFound, 2);
      expect(data.brandLookupsNotFound, 1);
      expect(data.placeLookupRate, closeTo(2 / 3, 0.001));
    });

    test('미매핑 목록이 함께 실린다', () async {
      await addTransaction(source: ClassificationSource.seed);
      await diagnostics.recordUnmapped(categoryName: '음식점 > 브런치');

      final ClassificationDiagnostics data = await diagnostics.load();

      expect(data.unmapped, hasLength(1));
    });
  });

  group('v12 -> v13 이관', () {
    test('기존 DB 를 열어도 데이터가 남고 수집이 동작한다', () async {
      await db.close();

      final Directory dir =
          await Directory.systemTemp.createTemp('diagnostics_upgrade');
      final String path = '${dir.path}/budget.db';

      const int beforeDiagnostics = 12;
      final Database old = await openDatabase(
        path,
        version: beforeDiagnostics,
        onCreate: (Database db, int version) =>
            LegacySchema.createAt(db, beforeDiagnostics),
      );
      final int now = DateTime.now().millisecondsSinceEpoch;
      await old.insert(DbSchema.tableAccounts, <String, Object?>{
        DbSchema.acName: '기존 계좌',
        DbSchema.acType: 'checking',
        DbSchema.acBalance: 1000,
        DbSchema.acBalanceAsOf: 0,
        DbSchema.acCreatedAt: now,
        DbSchema.acUpdatedAt: now,
      });
      await old.close();

      final Database upgraded = await openDatabase(
        path,
        version: DbSchema.databaseVersion,
        onUpgrade: LegacySchema.upgrade,
      );

      expect(await upgraded.query(DbSchema.tableAccounts), hasLength(1));

      final ClassificationDiagnosticsRepositoryImpl migrated =
          ClassificationDiagnosticsRepositoryImpl(upgraded);
      await migrated.recordUnmapped(categoryName: '음식점 > 브런치');
      expect(await migrated.findUnmapped(), hasLength(1));

      await upgraded.close();
      await dir.delete(recursive: true);

      db = await openDatabase(inMemoryDatabasePath);
    });
  });
}
