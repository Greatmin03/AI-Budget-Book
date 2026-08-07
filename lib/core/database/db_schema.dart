import '../constants/app_categories.dart';

/// SQLite 스키마 정의.
///
/// 테이블/컬럼 이름을 문자열 상수로 모아두어 DataSource 들이 오타 없이 참조하게 한다.
class DbSchema {
  const DbSchema._();

  static const String databaseName = 'budget_book.db';

  /// v1 -> v2: `transactions.needs_review` 추가
  ///           (LLM 없이 사용자가 직접 분류하는 흐름을 위해)
  /// v2 -> v3: `transactions.display_name`, `transactions.tag` 추가
  ///           (이체 거래는 브랜드를 학습하지 않고 표시 이름/태그로만 구분한다)
  /// v3 -> v4: `settlements`, `deposits` 추가
  ///           (더치페이/정산. 원본 거래 금액은 절대 수정하지 않는다)
  /// v4 -> v5: `recurring_rules`, `asset_transfers` 추가 +
  ///           `transactions.recurring_rule_id`, `transactions.is_asset_transfer`
  ///           (거래 유형을 늘리지 않고 거래 위에 메타데이터를 얹는다)
  /// v5 -> v6: 직접 입력 / 수입 구분 / 계좌 / 프로젝트 + `projects`, `accounts`,
  ///           `account_snapshots` 추가
  /// v6 -> v7: `notification_sources`(수집 대상 앱 선택),
  ///           `brand_metadata`(장소 API 조회 캐시) 추가
  /// v7 -> v8: `transactions.account_id`(잔액 자동 반영),
  ///           `transactions.asset_kind`(저축/청약/투자 구분) 추가
  /// v8 -> v9: `transactions.ai_status`, `transactions.ai_processed_at`
  ///           (AI 분류 대기열. 실시간 LLM 호출을 없애고 일괄 처리로 옮겼다)
  /// v9 -> v10: `card_account_links` 추가
  ///            (카드 이름 -> 계좌. 알림 거래를 잔액에 자동 반영하기 위해)
  /// v10 -> v11: `deposits.transaction_id` 추가 (입금 -> 수입 거래 연결)
  /// v11 -> v12: 취소된 원결제에도 `is_cancelled` 표시 (통계에서 함께 제외)
  static const int databaseVersion = 12;

  // ---------------------------------------------------------------- merchants
  /// 학습된 개별 가맹점. "한 번 학습한 가맹점은 다시 AI 를 호출하지 않는다" 의 캐시.
  static const String tableMerchants = 'merchants';
  static const String mId = 'id';
  static const String mBrand = 'brand';
  static const String mMerchantName = 'merchant_name';
  static const String mNormalizedName = 'normalized_name';
  static const String mBranch = 'branch';
  static const String mCategory = 'category';
  static const String mSubcategory = 'subcategory';

  /// seed | rule | llm | user — 우선순위 판단에 사용한다(user 가 가장 강함).
  static const String mSource = 'source';
  static const String mConfidence = 'confidence';
  static const String mHitCount = 'hit_count';
  static const String mCreatedAt = 'created_at';
  static const String mUpdatedAt = 'updated_at';

  // -------------------------------------------------------------- brand_rules
  /// 브랜드 부분일치 규칙. `메가mgc커피춘천후평점` 안에서 `메가mgc커피` 를 찾아낸다.
  static const String tableBrandRules = 'brand_rules';
  static const String brId = 'id';
  static const String brPattern = 'pattern';
  static const String brBrand = 'brand';
  static const String brCategory = 'category';
  static const String brSubcategory = 'subcategory';
  static const String brPriority = 'priority';
  static const String brSource = 'source';

  // ------------------------------------------------------------- transactions
  static const String tableTransactions = 'transactions';
  static const String tId = 'id';
  static const String tMerchantId = 'merchant_id';

  /// 알림에서 추출한 원본 거래명. **절대 사용자 수정으로 덮어쓰지 않는다.**
  ///
  /// 이체 거래에서는 상대방 이름(`000 스마트폰`)이 들어간다.
  static const String tMerchantRaw = 'merchant_raw';

  /// 브랜드명. 가맹점 결제에서만 학습 대상이 된다.
  static const String tBrand = 'brand';

  /// 사용자가 지정한 표시 이름. 예: `친구 대신 결제`
  ///
  /// 원본 거래명을 보존한 채로 목록에 다르게 보여 주기 위한 필드다.
  /// 이체 거래에서 브랜드를 오염시키지 않고 목적을 남기는 수단이기도 하다.
  static const String tDisplayName = 'display_name';

  /// 사용자 태그. 예: `친구 대신 결제`, `회비`
  static const String tTag = 'tag';

  /// 정기결제 규칙 연결(메타데이터). 없으면 일반 거래.
  static const String tRecurringRuleId = 'recurring_rule_id';

  /// 자산 이동 여부(적금 납입 등).
  ///
  /// 1이면 **소비 통계에서 제외**된다. 돈이 사라진 게 아니라 내 계좌 사이를
  /// 이동한 것이기 때문이다. 현금 흐름에는 포함된다.
  /// 상세 정보(어느 계좌에서 어디로)는 `asset_transfers` 에 있다.
  static const String tIsAssetTransfer = 'is_asset_transfer';

  /// 어디서 들어온 거래인가. `notification` | `manual`
  ///
  /// 직접 입력한 거래(현금, 중고거래, 누락분)를 구분한다.
  static const String tEntrySource = 'entry_source';

  /// 지출인가 수입인가. `expense` | `income`
  ///
  /// 수입은 **소비 통계에서 제외**된다. 알림으로 수집된 거래는 항상 지출이다.
  static const String tDirection = 'direction';

  /// 사용한 계좌/수단 이름. 예: `KB 입출금`, `현금`
  ///
  /// 표시용 문자열이다. 잔액 반영 대상은 [tAccountId] 로 판단한다.
  /// (이름만으로 매칭하면 계좌 이름을 바꾼 순간 잔액이 어긋난다)
  static const String tAccount = 'account';

  /// 잔액을 반영할 계좌. null 이면 자산에 영향을 주지 않는다.
  ///
  /// 계좌가 삭제되면 `SET NULL` 이 되고, 그 시점 이후 이 거래는 잔액 계산에서
  /// 빠진다. 거래 자체는 남는다(원본 보존).
  static const String tAccountId = 'account_id';

  /// 자산 이동의 종류. `is_asset_transfer = 1` 일 때만 의미가 있다.
  ///
  /// `saving`(적금) | `housing`(청약) | `investment`(투자) | `other`
  /// 소비 통계에서는 어느 쪽이든 제외되지만, 자산 통계에서는 나눠 보여 준다.
  static const String tAssetKind = 'asset_kind';

  /// AI 분류 대기 상태. `none` | `pending` | `processing` | `completed` | `failed`
  ///
  /// 결제 순간에는 AI 를 호출하지 않는다. 사전/장소 API 로 해결되지 않은 거래만
  /// `pending` 으로 쌓아 두고, Ollama 가 켜진 노트북이 붙었을 때 한 번에
  /// 처리한다. 실시간 호출이 없으므로 저장이 빠르고 배터리도 덜 쓴다.
  static const String tAiStatus = 'ai_status';

  /// AI 분석을 마친 시각(epoch millis). 재시도 판단과 진단에 쓴다.
  static const String tAiProcessedAt = 'ai_processed_at';

  /// 프로젝트(폴더) 연결. 카테고리와 별개로 여러 거래를 하나로 묶는다.
  static const String tProjectId = 'project_id';

  static const String tAmount = 'amount';

  /// 거래 시점의 카테고리 스냅샷. 사용자가 개별 거래만 수정할 수 있으므로
  /// merchants 조인에 의존하지 않고 거래별로 들고 있는다.
  static const String tCategory = 'category';
  static const String tSubcategory = 'subcategory';
  static const String tPaymentMethod = 'payment_method';
  static const String tCardName = 'card_name';
  static const String tInstallmentMonths = 'installment_months';
  static const String tIsCancelled = 'is_cancelled';
  static const String tPaymentDatetime = 'payment_datetime';
  static const String tRawNotification = 'raw_notification';
  static const String tSourcePackage = 'source_package';
  static const String tMemo = 'memo';

  /// 같은 알림이 두 번 들어와도 중복 저장되지 않게 하는 유니크 키.
  static const String tFingerprint = 'fingerprint';
  static const String tClassificationSource = 'classification_source';

  /// 사용자 확인이 필요한 거래(처음 보는 브랜드).
  ///
  /// 1이면 "분류 필요" 목록에 나타나고, 사용자가 카테고리를 한 번 고르면 0이 된다.
  static const String tNeedsReview = 'needs_review';

  static const String tCreatedAt = 'created_at';
  static const String tUpdatedAt = 'updated_at';

  // -------------------------------------------------------------- settlements
  /// 정산(더치페이) 내역. 거래 금액을 고치지 않고 "돌려받은 돈"을 따로 기록한다.
  ///
  /// 30,000원을 결제하고 친구 둘이 10,000원씩 보내주면
  /// 거래는 30,000원으로 남고 정산 2건이 붙는다. 실제 부담은 10,000원이다.
  static const String tableSettlements = 'settlements';
  static const String stId = 'id';
  static const String stTransactionId = 'transaction_id';

  /// 정산해 준 사람. 예: `김철수`
  static const String stCounterparty = 'counterparty';

  /// 받은 금액(항상 양수).
  static const String stAmount = 'amount';
  static const String stSettledAt = 'settled_at';

  /// 입금 알림에서 자동 생성된 경우 그 입금 건.
  static const String stDepositId = 'deposit_id';
  static const String stMemo = 'memo';
  static const String stCreatedAt = 'created_at';

  // ----------------------------------------------------------------- deposits
  /// 입금 알림. 정산 후보 목록이다.
  ///
  /// 같은 입금이 `transactions` 에도 **수입 거래**로 들어간다(v11). 두 곳을
  /// [dpTransactionId] 로 잇는다. 브랜드 학습에는 절대 사용하지 않는다.
  static const String tableDeposits = 'deposits';
  static const String dpId = 'id';

  /// 보낸 사람. 예: `홍길동`
  static const String dpCounterparty = 'counterparty';
  static const String dpAmount = 'amount';
  static const String dpDepositedAt = 'deposited_at';
  static const String dpRawNotification = 'raw_notification';
  static const String dpSourcePackage = 'source_package';
  static const String dpBankName = 'bank_name';

  /// pending | linked | ignored
  static const String dpStatus = 'status';

  /// 이 입금으로 만들어진 수입 거래.
  ///
  /// 입금은 두 곳에 남는다 — 정산 후보 목록(`deposits`)과 수입 통계
  /// (`transactions`). 이 연결이 있어야 정산으로 확정됐을 때 그 수입 거래를
  /// 찾아 `정산` 분류로 옮길 수 있다(= 수입 통계에서 뺄 수 있다).
  static const String dpTransactionId = 'transaction_id';
  static const String dpFingerprint = 'fingerprint';
  static const String dpCreatedAt = 'created_at';

  // ---------------------------------------------------------- recurring_rules
  /// 정기결제 규칙. 거래를 복제하지 않고 "이 브랜드는 매달 나간다" 만 기록한다.
  static const String tableRecurringRules = 'recurring_rules';
  static const String rrId = 'id';
  static const String rrBrand = 'brand';
  static const String rrCategory = 'category';
  static const String rrSubcategory = 'subcategory';

  /// weekly | monthly | quarterly | yearly
  static const String rrCycle = 'cycle';

  /// 예상 결제 금액. 실제 금액은 조금씩 달라질 수 있다(환율, 요금 변경).
  static const String rrExpectedAmount = 'expected_amount';
  static const String rrLastPaidAt = 'last_paid_at';
  static const String rrNextExpectedAt = 'next_expected_at';
  static const String rrIsActive = 'is_active';

  /// 사용자가 직접 만들었는지, 자동 감지에서 왔는지.
  static const String rrSource = 'source';
  static const String rrCreatedAt = 'created_at';
  static const String rrUpdatedAt = 'updated_at';

  // ---------------------------------------------------------- asset_transfers
  /// 자산 이동 상세(적금 납입, 계좌 간 이동).
  ///
  /// 소비가 아니라 내 자산의 위치가 바뀐 것이다.
  static const String tableAssetTransfers = 'asset_transfers';
  static const String atId = 'id';

  /// 연결된 거래. 알림 없이 수동으로 기록한 이동이면 null.
  static const String atTransactionId = 'transaction_id';

  /// 보낸 곳. 예: `KB 입출금`
  static const String atFromAccount = 'from_account';

  /// 받는 곳. 예: `KB 청년미래적금`
  static const String atToAccount = 'to_account';
  static const String atAmount = 'amount';
  static const String atTransferredAt = 'transferred_at';
  static const String atNote = 'note';
  static const String atCreatedAt = 'created_at';

  // ----------------------------------------------------------------- projects
  /// 프로젝트(폴더). 카테고리와 별개로 거래를 묶는다.
  ///
  /// 예: `일본 여행` 하나에 숙박·식비·교통·쇼핑이 모두 들어간다.
  static const String tableProjects = 'projects';
  static const String pjId = 'id';
  static const String pjName = 'name';
  static const String pjDescription = 'description';

  /// 목표 금액(선택). 예산이 아니라 "이 프로젝트에 이만큼 쓸 예정" 이다.
  static const String pjTargetAmount = 'target_amount';
  static const String pjStartedAt = 'started_at';
  static const String pjEndedAt = 'ended_at';
  static const String pjIsArchived = 'is_archived';
  static const String pjCreatedAt = 'created_at';
  static const String pjUpdatedAt = 'updated_at';

  // ----------------------------------------------------------------- accounts
  /// 자산 계좌. 잔액은 사용자가 입력한다(은행 연동이 없으므로).
  static const String tableAccounts = 'accounts';
  static const String acId = 'id';
  static const String acName = 'name';

  /// checking | savings | cash | investment | other
  static const String acType = 'type';

  /// **기준 잔액.** 사용자가 입력한 시점의 잔액이다.
  ///
  /// 현재 잔액은 이 값에 [acBalanceAsOf] 이후의 거래를 합산해서 구한다.
  /// 잔액을 직접 증감시키지 않는 이유:
  ///  - 저장 중 앱이 죽으면 영구히 어긋난다(복구 수단이 없다)
  ///  - 거래를 수정/삭제할 때마다 차액을 정확히 되돌려야 한다
  ///  - 파생값이면 언제든 다시 계산할 수 있어 어긋날 방법이 없다
  static const String acBalance = 'balance';

  /// 기준 잔액이 유효한 시각. 이 시각 **이후**의 거래만 잔액에 반영된다.
  ///
  /// 기존 계좌는 마이그레이션 시각으로 설정되므로 이미 입력해 둔 잔액이
  /// 과거 거래 때문에 흔들리지 않는다.
  static const String acBalanceAsOf = 'balance_as_of';
  static const String acIsActive = 'is_active';
  static const String acSortOrder = 'sort_order';
  static const String acCreatedAt = 'created_at';
  static const String acUpdatedAt = 'updated_at';

  // -------------------------------------------------------- account_snapshots
  /// 잔액 기록. 자산 추이(지난달 대비)를 계산하는 근거다.
  static const String tableAccountSnapshots = 'account_snapshots';
  static const String asId = 'id';
  static const String asAccountId = 'account_id';
  static const String asBalance = 'balance';
  static const String asRecordedAt = 'recorded_at';

  // --------------------------------------------------- notification_sources
  /// 알림을 수집할 앱 목록.
  ///
  /// 금융 앱을 여러 개 쓰면 같은 결제가 여러 앱에서 알림으로 온다.
  /// 사용자가 고른 앱만 수집해 중복과 노이즈를 막는다.
  static const String tableNotificationSources = 'notification_sources';
  static const String nsPackageName = 'package_name';
  static const String nsDisplayName = 'display_name';
  static const String nsEnabled = 'enabled';
  static const String nsLastSeenAt = 'last_seen_at';
  static const String nsDetectedAt = 'detected_at';

  // ------------------------------------------------------------ brand_metadata
  /// 브랜드 업종 조회 캐시.
  ///
  /// **브랜드당 최대 1회만 외부 조회한다.** 실패(못 찾음)도 저장해서
  /// 같은 브랜드를 반복 조회하지 않는다. 이게 없으면 API 할당량이 금방 소진된다.
  static const String tableBrandMetadata = 'brand_metadata';
  static const String bmId = 'id';

  /// 조회 키. `TextNormalizer.normalize` 결과.
  static const String bmNormalizedBrand = 'normalized_brand';
  static const String bmBrand = 'brand';

  /// 장소 API 가 알려 준 업종 문자열. 예: `음식점 > 중식 > 중국요리`
  static const String bmIndustry = 'industry';
  static const String bmCategory = 'category';
  static const String bmSubcategory = 'subcategory';

  /// kakao | naver | dictionary | llm | user
  static const String bmSource = 'source';
  static const String bmLookedUpAt = 'looked_up_at';

  /// 사용자가 손으로 고쳤는지. 고친 값은 재조회로 덮어쓰지 않는다.
  static const String bmUserModified = 'user_modified';

  /// 조회에 성공했는지. 0이면 "찾지 못함" 을 캐시한 것이다.
  static const String bmFound = 'found';

  // ------------------------------------------------------ card_account_links
  /// 카드 이름 -> 계좌 연결.
  ///
  /// 알림은 `KB국민카드` 같은 **카드 이름**만 준다. 그 카드가 어느 계좌에서
  /// 빠져나가는지는 앱이 알 수 없으므로 사용자가 한 번 지정한다.
  /// 지정하면 이후 그 카드의 결제가 계좌 잔액에 자동 반영된다.
  ///
  /// 계좌 이름으로 추측하지 않는다. 틀리면 잔액이 조용히 어긋나고
  /// 사용자가 알아채기 어렵다.
  static const String tableCardAccountLinks = 'card_account_links';

  /// 알림에서 읽은 카드 이름. 이것이 키다.
  static const String calCardName = 'card_name';

  /// 연결된 계좌. 계좌가 삭제되면 연결도 함께 사라진다.
  static const String calAccountId = 'account_id';
  static const String calCreatedAt = 'created_at';

  // ----------------------------------------------------------------- settings
  static const String tableSettings = 'settings';
  static const String sKey = 'key';
  static const String sValue = 'value';

  // ---------------------------------------------------------- ingest_failures
  /// 파싱에 실패한 알림 보관함. 파서 규칙을 개선하는 근거로 쓴다.
  static const String tableIngestFailures = 'ingest_failures';
  static const String fId = 'id';
  static const String fPackage = 'package';
  static const String fTitle = 'title';
  static const String fText = 'text';
  static const String fPostedAt = 'posted_at';
  static const String fReason = 'reason';
  static const String fCreatedAt = 'created_at';

  static const List<String> createStatements = <String>[
    '''
    CREATE TABLE $tableMerchants (
      $mId INTEGER PRIMARY KEY AUTOINCREMENT,
      $mBrand TEXT NOT NULL,
      $mMerchantName TEXT NOT NULL,
      $mNormalizedName TEXT NOT NULL UNIQUE,
      $mBranch TEXT,
      $mCategory TEXT NOT NULL,
      $mSubcategory TEXT NOT NULL,
      $mSource TEXT NOT NULL,
      $mConfidence REAL NOT NULL DEFAULT 0,
      $mHitCount INTEGER NOT NULL DEFAULT 0,
      $mCreatedAt INTEGER NOT NULL,
      $mUpdatedAt INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE $tableBrandRules (
      $brId INTEGER PRIMARY KEY AUTOINCREMENT,
      $brPattern TEXT NOT NULL UNIQUE,
      $brBrand TEXT NOT NULL,
      $brCategory TEXT NOT NULL,
      $brSubcategory TEXT NOT NULL,
      $brPriority INTEGER NOT NULL DEFAULT 0,
      $brSource TEXT NOT NULL DEFAULT 'seed'
    )
    ''',
    // projects 를 먼저 만든다. transactions 가 이 테이블을 참조한다.
    '''
    CREATE TABLE $tableProjects (
      $pjId INTEGER PRIMARY KEY AUTOINCREMENT,
      $pjName TEXT NOT NULL,
      $pjDescription TEXT,
      $pjTargetAmount INTEGER,
      $pjStartedAt INTEGER,
      $pjEndedAt INTEGER,
      $pjIsArchived INTEGER NOT NULL DEFAULT 0,
      $pjCreatedAt INTEGER NOT NULL,
      $pjUpdatedAt INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE $tableAccounts (
      $acId INTEGER PRIMARY KEY AUTOINCREMENT,
      $acName TEXT NOT NULL UNIQUE,
      $acType TEXT NOT NULL,
      $acBalance INTEGER NOT NULL DEFAULT 0,
      $acBalanceAsOf INTEGER NOT NULL DEFAULT 0,
      $acIsActive INTEGER NOT NULL DEFAULT 1,
      $acSortOrder INTEGER NOT NULL DEFAULT 0,
      $acCreatedAt INTEGER NOT NULL,
      $acUpdatedAt INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE $tableAccountSnapshots (
      $asId INTEGER PRIMARY KEY AUTOINCREMENT,
      $asAccountId INTEGER NOT NULL
        REFERENCES $tableAccounts($acId) ON DELETE CASCADE,
      $asBalance INTEGER NOT NULL,
      $asRecordedAt INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE $tableTransactions (
      $tId INTEGER PRIMARY KEY AUTOINCREMENT,
      $tMerchantId INTEGER REFERENCES $tableMerchants($mId) ON DELETE SET NULL,
      $tMerchantRaw TEXT NOT NULL,
      $tBrand TEXT NOT NULL,
      $tDisplayName TEXT,
      $tTag TEXT,
      $tAmount INTEGER NOT NULL,
      $tCategory TEXT NOT NULL,
      $tSubcategory TEXT NOT NULL,
      $tPaymentMethod TEXT NOT NULL,
      $tCardName TEXT,
      $tInstallmentMonths INTEGER NOT NULL DEFAULT 0,
      $tIsCancelled INTEGER NOT NULL DEFAULT 0,
      $tPaymentDatetime INTEGER NOT NULL,
      $tRawNotification TEXT NOT NULL,
      $tSourcePackage TEXT,
      $tMemo TEXT,
      $tFingerprint TEXT NOT NULL UNIQUE,
      $tClassificationSource TEXT NOT NULL,
      $tNeedsReview INTEGER NOT NULL DEFAULT 0,
      $tRecurringRuleId INTEGER,
      $tIsAssetTransfer INTEGER NOT NULL DEFAULT 0,
      $tEntrySource TEXT NOT NULL DEFAULT 'notification',
      $tDirection TEXT NOT NULL DEFAULT 'expense',
      $tAccount TEXT,
      $tAccountId INTEGER
        REFERENCES $tableAccounts($acId) ON DELETE SET NULL,
      $tAssetKind TEXT,
      $tAiStatus TEXT NOT NULL DEFAULT 'none',
      $tAiProcessedAt INTEGER,
      $tProjectId INTEGER
        REFERENCES $tableProjects($pjId) ON DELETE SET NULL,
      $tCreatedAt INTEGER NOT NULL,
      $tUpdatedAt INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE $tableRecurringRules (
      $rrId INTEGER PRIMARY KEY AUTOINCREMENT,
      $rrBrand TEXT NOT NULL,
      $rrCategory TEXT NOT NULL,
      $rrSubcategory TEXT NOT NULL,
      $rrCycle TEXT NOT NULL,
      $rrExpectedAmount INTEGER NOT NULL,
      $rrLastPaidAt INTEGER,
      $rrNextExpectedAt INTEGER,
      $rrIsActive INTEGER NOT NULL DEFAULT 1,
      $rrSource TEXT NOT NULL DEFAULT 'auto',
      $rrCreatedAt INTEGER NOT NULL,
      $rrUpdatedAt INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE $tableAssetTransfers (
      $atId INTEGER PRIMARY KEY AUTOINCREMENT,
      $atTransactionId INTEGER
        REFERENCES $tableTransactions($tId) ON DELETE CASCADE,
      $atFromAccount TEXT NOT NULL,
      $atToAccount TEXT NOT NULL,
      $atAmount INTEGER NOT NULL,
      $atTransferredAt INTEGER NOT NULL,
      $atNote TEXT,
      $atCreatedAt INTEGER NOT NULL
    )
    ''',
    // deposits 를 먼저 만든다. settlements 가 이 테이블을 참조한다.
    '''
    CREATE TABLE $tableDeposits (
      $dpId INTEGER PRIMARY KEY AUTOINCREMENT,
      $dpCounterparty TEXT NOT NULL,
      $dpAmount INTEGER NOT NULL,
      $dpDepositedAt INTEGER NOT NULL,
      $dpRawNotification TEXT NOT NULL,
      $dpSourcePackage TEXT,
      $dpBankName TEXT,
      $dpStatus TEXT NOT NULL DEFAULT 'pending',
      $dpFingerprint TEXT NOT NULL UNIQUE,
      $dpTransactionId INTEGER
        REFERENCES $tableTransactions($tId) ON DELETE SET NULL,
      $dpCreatedAt INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE $tableSettlements (
      $stId INTEGER PRIMARY KEY AUTOINCREMENT,
      $stTransactionId INTEGER NOT NULL
        REFERENCES $tableTransactions($tId) ON DELETE CASCADE,
      $stCounterparty TEXT NOT NULL,
      $stAmount INTEGER NOT NULL,
      $stSettledAt INTEGER NOT NULL,
      $stDepositId INTEGER
        REFERENCES $tableDeposits($dpId) ON DELETE SET NULL,
      $stMemo TEXT,
      $stCreatedAt INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE $tableNotificationSources (
      $nsPackageName TEXT PRIMARY KEY,
      $nsDisplayName TEXT NOT NULL,
      $nsEnabled INTEGER NOT NULL DEFAULT 0,
      $nsLastSeenAt INTEGER,
      $nsDetectedAt INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE $tableBrandMetadata (
      $bmId INTEGER PRIMARY KEY AUTOINCREMENT,
      $bmNormalizedBrand TEXT NOT NULL UNIQUE,
      $bmBrand TEXT NOT NULL,
      $bmIndustry TEXT,
      $bmCategory TEXT,
      $bmSubcategory TEXT,
      $bmSource TEXT NOT NULL,
      $bmLookedUpAt INTEGER NOT NULL,
      $bmUserModified INTEGER NOT NULL DEFAULT 0,
      $bmFound INTEGER NOT NULL DEFAULT 1
    )
    ''',
    '''
    CREATE TABLE $tableCardAccountLinks (
      $calCardName TEXT PRIMARY KEY,
      $calAccountId INTEGER NOT NULL
        REFERENCES $tableAccounts($acId) ON DELETE CASCADE,
      $calCreatedAt INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE $tableSettings (
      $sKey TEXT PRIMARY KEY,
      $sValue TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE $tableIngestFailures (
      $fId INTEGER PRIMARY KEY AUTOINCREMENT,
      $fPackage TEXT,
      $fTitle TEXT,
      $fText TEXT,
      $fPostedAt INTEGER,
      $fReason TEXT,
      $fCreatedAt INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_tx_datetime ON $tableTransactions($tPaymentDatetime)',
    'CREATE INDEX idx_tx_category ON $tableTransactions($tCategory)',
    'CREATE INDEX idx_tx_brand ON $tableTransactions($tBrand)',
    'CREATE INDEX idx_tx_merchant ON $tableTransactions($tMerchantId)',
    'CREATE INDEX idx_tx_needs_review ON $tableTransactions($tNeedsReview)',
    'CREATE INDEX idx_merchant_brand ON $tableMerchants($mBrand)',
    'CREATE INDEX idx_settlement_tx ON $tableSettlements($stTransactionId)',
    'CREATE INDEX idx_deposit_status ON $tableDeposits($dpStatus)',
    'CREATE INDEX idx_deposit_time ON $tableDeposits($dpDepositedAt)',
    'CREATE INDEX idx_tx_asset_transfer ON $tableTransactions($tIsAssetTransfer)',
    'CREATE INDEX idx_tx_recurring ON $tableTransactions($tRecurringRuleId)',
    'CREATE INDEX idx_recurring_active ON $tableRecurringRules($rrIsActive)',
    'CREATE INDEX idx_recurring_brand ON $tableRecurringRules($rrBrand)',
    'CREATE INDEX idx_asset_tx ON $tableAssetTransfers($atTransactionId)',
    'CREATE INDEX idx_tx_project ON $tableTransactions($tProjectId)',
    'CREATE INDEX idx_tx_direction ON $tableTransactions($tDirection)',
    'CREATE INDEX idx_snapshot_account '
        'ON $tableAccountSnapshots($asAccountId, $asRecordedAt)',
    'CREATE INDEX idx_source_enabled '
        'ON $tableNotificationSources($nsEnabled)',
    'CREATE INDEX idx_tx_account ON $tableTransactions($tAccountId)',
    'CREATE INDEX idx_tx_ai_status ON $tableTransactions($tAiStatus)',
  ];

  /// 거래의 정산 합계(돌려받은 금액). `transactions` 를 `t` 로 별칭 지어야 한다.
  static const String settledSumExpr =
      '(SELECT COALESCE(SUM(s.$stAmount), 0) FROM $tableSettlements s '
      'WHERE s.$stTransactionId = t.$tId)';

  /// **실제 부담 금액** = 거래 금액 - 정산 합계.
  ///
  /// 통계/대시보드는 이 값을 쓴다. 거래 목록은 원본 `amount` 를 쓴다.
  static const String netAmountExpr = '(t.$tAmount - $settledSumExpr)';

  /// 나가는 돈만. **자산 이동을 포함한다.**
  ///
  /// 수입은 양수로 저장되므로(`direction` 으로만 구분한다) 이 조건을 빼면
  /// 수입이 지출에 더해진다. 300,000원 입금 + 15,000원 결제가
  /// 315,000원으로 합산되던 버그가 정확히 그것이었다.
  static const String expenseOnly = "t.$tDirection = 'expense'";

  /// 들어오는 돈만.
  static const String incomeOnly = "t.$tDirection = 'income'";

  /// 취소되지 않은 거래.
  ///
  /// 승인취소가 오면 **취소 건과 원결제 양쪽에** 이 표시를 단다. 그래야 한
  /// 조건으로 둘 다 빠진다.
  ///
  /// 취소 건만 빼면 원결제가 그대로 남아 쓰지도 않은 돈이 잡히고, 둘 다
  /// 남기면 금액은 상계되지만 **건수가 오염된다** — 취소된 결제 한 번 때문에
  /// "가장 많이 간 가게" 1위가 되는 식이다. 없었던 일로 다루는 것이 맞다.
  static const String notCancelled = 't.$tIsCancelled = 0';

  /// **번 돈만.** 돌려받은 돈(정산)을 뺀다.
  ///
  /// 더치페이로 친구가 보낸 20,000원은 소득이 아니다. 그 결제의
  /// `settlements` 로 이미 내 부담이 줄었으므로, 수입으로도 세면 같은 돈을
  /// 두 번 세게 된다.
  ///
  /// "얼마가 들어왔나"(= [incomeOnly])와 "얼마를 벌었나"(= 이 조건)는
  /// 다른 질문이다. 수입 통계는 후자에 답한다.
  static const String earnedIncomeOnly = '$incomeOnly AND $notCancelled '
      "AND t.$tCategory != '${CategoryTaxonomy.settlementCategory}'";

  /// **소비 지표에만 포함되는 거래** 조건.
  ///
  /// 두 가지를 제외한다.
  ///  - 자산 이동(적금 납입 등): 돈이 사라진 게 아니라 계좌를 옮긴 것
  ///  - 수입(입금): 지출이 아니다
  ///
  /// 카테고리 비율·브랜드 순위·소비 추이 같은 지표는 모두 이 조건을 붙인다.
  /// 현금 흐름 지표는 [expenseOnly] 를 쓴다(자산 이동 포함, 수입 제외).
  static const String spendingOnly =
      't.$tIsAssetTransfer = 0 AND $expenseOnly AND $notCancelled';

  /// 자산 이동만. 저축/청약/투자 구분은 [tAssetKind] 로 한다.
  static const String assetTransferOnly =
      't.$tIsAssetTransfer = 1 AND $expenseOnly';

  /// AI 분석을 기다리는 거래 조건.
  ///
  /// `processing` 은 포함하지 않는다. 처리 중인 것을 다시 집어 오면 같은
  /// 브랜드를 두 번 호출한다.
  static const String aiPendingOnly = "t.$tAiStatus = 'pending'";

  /// 계좌 잔액에 더할 **부호 있는 금액**.
  ///
  ///  - 수입: `+`
  ///  - 지출: `-` (취소 거래는 `amount` 가 음수이므로 자동으로 환불이 된다)
  ///  - 자산 이동: `0`
  ///
  /// 자산 이동을 0으로 두는 이유는 총자산이 변하지 않기 때문이다.
  /// 적금 납입은 입출금 계좌에서 적금 계좌로 옮긴 것이므로 합계가 같다.
  ///
  /// **정산 차감(`netAmountExpr`)을 쓰지 않고 `amount` 를 쓴다.**
  /// 카드에서 빠져나간 금액은 정산과 무관하게 원래 금액이고, 돌려받은 돈은
  /// 입금으로 따로 들어온다. net 을 쓰면 환급이 두 번 반영된다.
  static const String balanceDeltaExpr = 'CASE '
      'WHEN t.$tIsAssetTransfer = 1 THEN 0 '
      "WHEN t.$tDirection = 'income' THEN t.$tAmount "
      'ELSE -t.$tAmount END';

  /// 버전별 마이그레이션. `onUpgrade` 에서 `from < key` 인 항목을 순서대로 실행한다.
  static const Map<int, List<String>> migrations = <int, List<String>>{
    2: <String>[
      'ALTER TABLE $tableTransactions '
          'ADD COLUMN $tNeedsReview INTEGER NOT NULL DEFAULT 0',
      'CREATE INDEX IF NOT EXISTS idx_tx_needs_review '
          'ON $tableTransactions($tNeedsReview)',
    ],
    3: <String>[
      'ALTER TABLE $tableTransactions ADD COLUMN $tDisplayName TEXT',
      'ALTER TABLE $tableTransactions ADD COLUMN $tTag TEXT',
    ],
    4: <String>[
      '''
      CREATE TABLE IF NOT EXISTS $tableDeposits (
        $dpId INTEGER PRIMARY KEY AUTOINCREMENT,
        $dpCounterparty TEXT NOT NULL,
        $dpAmount INTEGER NOT NULL,
        $dpDepositedAt INTEGER NOT NULL,
        $dpRawNotification TEXT NOT NULL,
        $dpSourcePackage TEXT,
        $dpBankName TEXT,
        $dpStatus TEXT NOT NULL DEFAULT 'pending',
        $dpFingerprint TEXT NOT NULL UNIQUE,
        $dpCreatedAt INTEGER NOT NULL
      )
      ''',
      '''
      CREATE TABLE IF NOT EXISTS $tableSettlements (
        $stId INTEGER PRIMARY KEY AUTOINCREMENT,
        $stTransactionId INTEGER NOT NULL
          REFERENCES $tableTransactions($tId) ON DELETE CASCADE,
        $stCounterparty TEXT NOT NULL,
        $stAmount INTEGER NOT NULL,
        $stSettledAt INTEGER NOT NULL,
        $stDepositId INTEGER
          REFERENCES $tableDeposits($dpId) ON DELETE SET NULL,
        $stMemo TEXT,
        $stCreatedAt INTEGER NOT NULL
      )
      ''',
      'CREATE INDEX IF NOT EXISTS idx_settlement_tx '
          'ON $tableSettlements($stTransactionId)',
      'CREATE INDEX IF NOT EXISTS idx_deposit_status '
          'ON $tableDeposits($dpStatus)',
      'CREATE INDEX IF NOT EXISTS idx_deposit_time '
          'ON $tableDeposits($dpDepositedAt)',
    ],
    5: <String>[
      'ALTER TABLE $tableTransactions ADD COLUMN $tRecurringRuleId INTEGER',
      'ALTER TABLE $tableTransactions '
          'ADD COLUMN $tIsAssetTransfer INTEGER NOT NULL DEFAULT 0',
      '''
      CREATE TABLE IF NOT EXISTS $tableRecurringRules (
        $rrId INTEGER PRIMARY KEY AUTOINCREMENT,
        $rrBrand TEXT NOT NULL,
        $rrCategory TEXT NOT NULL,
        $rrSubcategory TEXT NOT NULL,
        $rrCycle TEXT NOT NULL,
        $rrExpectedAmount INTEGER NOT NULL,
        $rrLastPaidAt INTEGER,
        $rrNextExpectedAt INTEGER,
        $rrIsActive INTEGER NOT NULL DEFAULT 1,
        $rrSource TEXT NOT NULL DEFAULT 'auto',
        $rrCreatedAt INTEGER NOT NULL,
        $rrUpdatedAt INTEGER NOT NULL
      )
      ''',
      '''
      CREATE TABLE IF NOT EXISTS $tableAssetTransfers (
        $atId INTEGER PRIMARY KEY AUTOINCREMENT,
        $atTransactionId INTEGER
          REFERENCES $tableTransactions($tId) ON DELETE CASCADE,
        $atFromAccount TEXT NOT NULL,
        $atToAccount TEXT NOT NULL,
        $atAmount INTEGER NOT NULL,
        $atTransferredAt INTEGER NOT NULL,
        $atNote TEXT,
        $atCreatedAt INTEGER NOT NULL
      )
      ''',
      'CREATE INDEX IF NOT EXISTS idx_tx_asset_transfer '
          'ON $tableTransactions($tIsAssetTransfer)',
      'CREATE INDEX IF NOT EXISTS idx_tx_recurring '
          'ON $tableTransactions($tRecurringRuleId)',
      'CREATE INDEX IF NOT EXISTS idx_recurring_active '
          'ON $tableRecurringRules($rrIsActive)',
      'CREATE INDEX IF NOT EXISTS idx_recurring_brand '
          'ON $tableRecurringRules($rrBrand)',
      'CREATE INDEX IF NOT EXISTS idx_asset_tx '
          'ON $tableAssetTransfers($atTransactionId)',
    ],
    6: <String>[
      '''
      CREATE TABLE IF NOT EXISTS $tableProjects (
        $pjId INTEGER PRIMARY KEY AUTOINCREMENT,
        $pjName TEXT NOT NULL,
        $pjDescription TEXT,
        $pjTargetAmount INTEGER,
        $pjStartedAt INTEGER,
        $pjEndedAt INTEGER,
        $pjIsArchived INTEGER NOT NULL DEFAULT 0,
        $pjCreatedAt INTEGER NOT NULL,
        $pjUpdatedAt INTEGER NOT NULL
      )
      ''',
      '''
      CREATE TABLE IF NOT EXISTS $tableAccounts (
        $acId INTEGER PRIMARY KEY AUTOINCREMENT,
        $acName TEXT NOT NULL UNIQUE,
        $acType TEXT NOT NULL,
        $acBalance INTEGER NOT NULL DEFAULT 0,
        $acIsActive INTEGER NOT NULL DEFAULT 1,
        $acSortOrder INTEGER NOT NULL DEFAULT 0,
        $acCreatedAt INTEGER NOT NULL,
        $acUpdatedAt INTEGER NOT NULL
      )
      ''',
      '''
      CREATE TABLE IF NOT EXISTS $tableAccountSnapshots (
        $asId INTEGER PRIMARY KEY AUTOINCREMENT,
        $asAccountId INTEGER NOT NULL
          REFERENCES $tableAccounts($acId) ON DELETE CASCADE,
        $asBalance INTEGER NOT NULL,
        $asRecordedAt INTEGER NOT NULL
      )
      ''',
      'ALTER TABLE $tableTransactions ADD COLUMN $tEntrySource TEXT '
          "NOT NULL DEFAULT 'notification'",
      'ALTER TABLE $tableTransactions ADD COLUMN $tDirection TEXT '
          "NOT NULL DEFAULT 'expense'",
      'ALTER TABLE $tableTransactions ADD COLUMN $tAccount TEXT',
      'ALTER TABLE $tableTransactions ADD COLUMN $tProjectId INTEGER',
      'CREATE INDEX IF NOT EXISTS idx_tx_project '
          'ON $tableTransactions($tProjectId)',
      'CREATE INDEX IF NOT EXISTS idx_tx_direction '
          'ON $tableTransactions($tDirection)',
      'CREATE INDEX IF NOT EXISTS idx_snapshot_account '
          'ON $tableAccountSnapshots($asAccountId, $asRecordedAt)',
    ],
    7: <String>[
      '''
      CREATE TABLE IF NOT EXISTS $tableNotificationSources (
        $nsPackageName TEXT PRIMARY KEY,
        $nsDisplayName TEXT NOT NULL,
        $nsEnabled INTEGER NOT NULL DEFAULT 0,
        $nsLastSeenAt INTEGER,
        $nsDetectedAt INTEGER NOT NULL
      )
      ''',
      '''
      CREATE TABLE IF NOT EXISTS $tableBrandMetadata (
        $bmId INTEGER PRIMARY KEY AUTOINCREMENT,
        $bmNormalizedBrand TEXT NOT NULL UNIQUE,
        $bmBrand TEXT NOT NULL,
        $bmIndustry TEXT,
        $bmCategory TEXT,
        $bmSubcategory TEXT,
        $bmSource TEXT NOT NULL,
        $bmLookedUpAt INTEGER NOT NULL,
        $bmUserModified INTEGER NOT NULL DEFAULT 0,
        $bmFound INTEGER NOT NULL DEFAULT 1
      )
      ''',
      'CREATE INDEX IF NOT EXISTS idx_source_enabled '
          'ON $tableNotificationSources($nsEnabled)',
    ],
    8: <String>[
      // 잔액 자동 반영 대상 계좌. 이름이 아니라 id 로 연결한다.
      // (SQLite 의 ALTER TABLE 은 ADD COLUMN 에 REFERENCES 를 붙일 수 있지만
      //  기존 행에 대해 외래키를 검사하지 않으므로 안전하다)
      'ALTER TABLE $tableTransactions ADD COLUMN $tAccountId INTEGER '
          'REFERENCES $tableAccounts($acId) ON DELETE SET NULL',
      // 자산 이동의 종류(저축/청약/투자). 기존 자산 이동은 종류 미지정으로 남는다.
      'ALTER TABLE $tableTransactions ADD COLUMN $tAssetKind TEXT',
      'CREATE INDEX IF NOT EXISTS idx_tx_account '
          'ON $tableTransactions($tAccountId)',
      // 기준 잔액 시각. 기본 0 으로 추가한 뒤 아래에서 '지금' 으로 올린다.
      'ALTER TABLE $tableAccounts ADD COLUMN $acBalanceAsOf '
          'INTEGER NOT NULL DEFAULT 0',
      // **이미 입력해 둔 잔액이 흔들리지 않게** 기준 시각을 지금으로 맞춘다.
      // 0 으로 두면 과거 거래 전체가 소급 반영되어 잔액이 갑자기 바뀐다.
      // Dart 의 시각을 문자열에 넣을 수 없으므로 SQLite 시간 함수를 쓴다.
      'UPDATE $tableAccounts '
          "SET $acBalanceAsOf = CAST(strftime('%s', 'now') AS INTEGER) * 1000 "
          'WHERE $acBalanceAsOf = 0',
    ],
    9: <String>[
      'ALTER TABLE $tableTransactions ADD COLUMN $tAiStatus '
          "TEXT NOT NULL DEFAULT 'none'",
      'ALTER TABLE $tableTransactions ADD COLUMN $tAiProcessedAt INTEGER',
      'CREATE INDEX IF NOT EXISTS idx_tx_ai_status '
          'ON $tableTransactions($tAiStatus)',
      // 이미 쌓여 있는 "분류 필요" 거래를 대기열에 넣는다.
      // 이 기능이 생기기 전에 모인 미분류 거래도 한 번에 정리할 수 있어야 한다.
      "UPDATE $tableTransactions SET $tAiStatus = 'pending' "
          'WHERE $tNeedsReview = 1',
    ],
    10: <String>[
      '''
      CREATE TABLE IF NOT EXISTS $tableCardAccountLinks (
        $calCardName TEXT PRIMARY KEY,
        $calAccountId INTEGER NOT NULL
          REFERENCES $tableAccounts($acId) ON DELETE CASCADE,
        $calCreatedAt INTEGER NOT NULL
      )
      ''',
    ],
    11: <String>[
      // 입금을 수입 거래로도 남기기 시작했다. 그 거래를 가리키는 연결.
      'ALTER TABLE $tableDeposits ADD COLUMN $dpTransactionId INTEGER '
          'REFERENCES $tableTransactions($tId) ON DELETE SET NULL',
    ],
    12: <String>[
      // 통계가 `is_cancelled = 0` 을 보기 시작했다. 그전에는 취소 건만
      // 표시되어 있었으므로, 이 이관 없이는 **원결제만 남아 쓰지도 않은 돈이
      // 잡힌다.** 이미 쌓인 취소 쌍의 원결제에도 표시를 단다.
      //
      // 같은 브랜드 + 같은 금액 + 취소보다 앞선 결제 중 가장 가까운 것 하나.
      // 60일을 넘겨 거슬러 올라가지 않는다 — 우연히 금액이 같은 옛 결제를
      // 지우면 안 된다.
      '''
      UPDATE $tableTransactions SET $tIsCancelled = 1
      WHERE $tId IN (
        SELECT (
          SELECT o.$tId FROM $tableTransactions o
          WHERE o.$tBrand = c.$tBrand
            AND o.$tAmount = -c.$tAmount
            AND o.$tIsCancelled = 0
            AND o.$tPaymentDatetime <= c.$tPaymentDatetime
            AND o.$tPaymentDatetime >= c.$tPaymentDatetime - 5184000000
          ORDER BY o.$tPaymentDatetime DESC
          LIMIT 1
        )
        FROM $tableTransactions c
        WHERE c.$tIsCancelled = 1 AND c.$tAmount < 0
      )
      ''',
    ],
  };
}
