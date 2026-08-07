# PROJECT_CONTEXT.md

> **이 문서 하나로 프로젝트 전체를 이해할 수 있게 쓴 개발 인수인계 문서다.**
> 코드에서 읽을 수 있는 사실은 짧게, **코드에 적혀 있지 않은 "왜"** 는 길게 적었다.
>
> 최종 갱신: 2026-08-06 (Round 12 완료)
> 검증 상태: `flutter analyze` 무경고 · `flutter test` 340개 통과 · `flutter build apk --debug` 성공 · 실기기(Galaxy S24+, Android 16) 실행 확인

---

## 목차

1. [프로젝트 개요](#1-프로젝트-개요)
2. [구현된 기능](#2-구현된-기능)
3. [아키텍처와 프로젝트 구조](#3-아키텍처와-프로젝트-구조)
4. [데이터베이스](#4-데이터베이스)
5. [AI 파이프라인](#5-ai-파이프라인)
6. [AI Pending Queue](#6-ai-pending-queue)
7. [Ollama](#7-ollama)
8. [카카오 장소 API](#8-카카오-장소-api)
9. [알림 처리 흐름](#9-알림-처리-흐름)
10. [브랜드 학습 정책](#10-브랜드-학습-정책)
11. [정산 · 자산 · 프로젝트](#11-정산--자산--프로젝트)
12. [InsightFacts / InsightNarrator](#12-insightfacts--insightnarrator)
13. [UI 화면](#13-ui-화면)
14. [개발 히스토리 (라운드별)](#14-개발-히스토리-라운드별)
15. [버그 수정 이력](#15-버그-수정-이력)
16. [테스트](#16-테스트)
17. [개발 철학](#17-개발-철학)
18. [실행 방법](#18-실행-방법)
19. [앞으로 구현 예정](#19-앞으로-구현-예정)
20. [현재 알려진 한계](#20-현재-알려진-한계)
21. [다음 작업자가 반드시 알아야 하는 것](#21-다음-작업자가-반드시-알아야-하는-것)

---

## 1. 프로젝트 개요

### 목적

**결제 알림을 읽어 가계부를 자동으로 작성하는 개인용 Android 앱.**

가계부 앱이 실패하는 이유는 기능이 부족해서가 아니라 **사람이 매번 입력해야 하기 때문**이다. 이 앱은 사용자가 입력하지 않는다. 카드사·은행 앱이 띄우는 결제 알림을 읽어 금액·가맹점·카드·시각을 뽑아 저장하고, 사용자는 통계만 본다.

```
카드로 결제
  → 카드사 앱이 알림을 띄운다
  → NotificationListenerService 가 가로챈다
  → 파싱해서 금액/가맹점/카드/시각을 뽑는다
  → 브랜드를 분류한다
  → SQLite 에 한 줄 기록된다
  → 사용자는 통계만 본다
```

### 사용 기술

| 항목 | 값 |
|---|---|
| 이름 | budget_book |
| 플랫폼 | **Android 전용** (iOS는 알림 접근 API가 없어 원리적으로 불가) |
| 프레임워크 | Flutter 3.44.8 / Dart 3.12.2 (`sdk: >=3.22.0`) |
| 로컬 DB | sqflite (SQLite) — **스키마 v17** |
| 네이티브 | Kotlin · NotificationListenerService · MethodChannel/EventChannel |
| 로컬 LLM | Ollama (기본 모델 `gemma3:4b`) — **선택 기능, 기본 꺼짐** |
| 외부 API | 카카오 로컬 API — **선택 기능, 사용자 본인 키** |
| 상태관리 | `ChangeNotifier` (외부 패키지 없음) |
| DI | 손으로 만든 서비스 로케이터 (`lib/core/di/injector.dart`) |
| 규모 | `lib/` 139 파일 / 약 25,700줄 · `test/` 21 파일 / 약 6,200줄 · Kotlin 5 파일 |

의존성은 의도적으로 적다.

```yaml
sqflite, path      # 로컬 DB
http               # Ollama / 카카오 API
intl               # 날짜·금액 포맷
flutter_localizations
# dev
flutter_lints, sqflite_common_ffi   # 데스크톱에서 실제 SQLite 로 테스트
```

`build_runner` 코드 생성을 쓰지 않는다(Drift 대신 sqflite + 손으로 쓴 DTO). 생성 코드가 없으면 clone 직후 바로 빌드된다.

### 현재 진행 상태

- 알림 수집 → 파싱 → 분류 → 저장 파이프라인 **완성**
- 통계(소비/수입/자산/프로젝트/요일) **완성**
- 정산(더치페이), 정기결제, 자산 이동, 프로젝트 **완성**
- AI 분류: **실시간 호출 없음.** 대기열에 쌓아 Ollama 가 붙을 때 일괄 처리
- 실기기(Galaxy S24+ / Android 16)에서 실행·마이그레이션 확인 완료

---

## 2. 구현된 기능

### 거래

| 기능 | 상태 | 비고 |
|---|---|---|
| 자동 알림 수집 | ✅ | 네이티브 파일 큐(JSONL). 앱이 죽어 있어도 유실 없음 |
| 결제 알림 파싱 | ✅ | 국내 주요 카드사/은행/페이 문구. 실패분은 보관함에 |
| 직접 입력 | ✅ | 현금·중고거래·누락분. 수입도 입력 가능 |
| 거래 수정 | ✅ | 날짜/시간/금액/수입지출/분류/브랜드/프로젝트/계좌/메모 |
| 거래 삭제 | ✅ | 수정 시트에서 확인 후 삭제 |
| 거래 검색 | ✅ | 브랜드·메모·태그. `LIKE` 이스케이프 처리 |
| 기간 필터 | ✅ | 오늘 / 이번 주 / 이번 달 / 올해 / 사용자 지정 |
| 중복 저장 방지 | ✅ | 지문(UNIQUE) + 근접 중복(금액·브랜드·수단 동일 & ±30초) |
| 수입/지출 그룹화 | ✅ | 같은 날짜 안에서 지출 → 수입 순, 부호+색 구분 |
| 분류 필요 큐 | ✅ | 처음 보는 브랜드를 한 번 골라 주면 이후 자동 |

### 프로젝트 (거래 묶음)

| 기능 | 상태 |
|---|---|
| 프로젝트 생성/수정 | ✅ |
| 목표 금액 | ✅ |
| 진행률(목표 대비 사용액) | ✅ |
| 카테고리·브랜드별 내역 | ✅ |
| 보관(archive) | ✅ |
| 삭제 (거래는 남고 연결만 해제) | ✅ |

### 자산

| 기능 | 상태 | 비고 |
|---|---|---|
| 계좌 관리 | ✅ | 입출금/적금/현금/증권/기타 |
| **거래 → 잔액 자동 반영** | ✅ | 기준 잔액 + 기준 시각 이후 거래 합(파생값) |
| 계좌 스냅샷 | ✅ | 잔액 변경 시 기록. 지난달 대비 계산 근거 |
| 오늘/이번 주/이번 달 변화 | ✅ | 거래 합산 기준 |
| 자산 이동(적금·청약·투자) | ✅ | 소비 통계 제외, 종류별 분리 |

### 통계

| 기능 | 상태 |
|---|---|
| 소비(카테고리/세부항목/브랜드) | ✅ |
| **수입** (카테고리별 + 월별 추이) | ✅ |
| 소비 / 저축 / 청약 / 투자 분리 | ✅ |
| 브랜드 드릴다운 (금액/횟수/평균/최근) | ✅ |
| 카테고리 드릴다운 | ✅ |
| 프로젝트별 통계 | ✅ |
| 요일 패턴 | ✅ |
| 월별 추이 (최근 6개월) | ✅ |
| 정산 반영 실제 부담 금액 | ✅ |

### AI 분류

| 단계 | 상태 | 비고 |
|---|---|---|
| 1. 사용자 규칙 | ✅ | 사용자가 고친 것이 항상 최우선 |
| 2. 내장 브랜드 사전 | ✅ | 179건 시드 |
| 3. 카카오 장소 API | ✅ | 브랜드당 1회, 실패도 캐시 |
| 4. **AI Pending Queue** | ✅ | 실시간 호출 없음. 일괄 처리 |
| 5. Ollama 일괄 분석 | ✅ | 브랜드당 LLM 1회 |
| 6. 사용자 직접 선택 | ✅ | 항상 존재하는 최종 수단 |
| 브랜드 캐시 | ✅ | `brand_metadata`. 성공/실패 모두 캐시 |
| AI 재분석(재시도) | ✅ | `failed` 상태로 남아 언제든 다시 |

### 그 외

- 더치페이 정산 (원본 금액 보존)
- 입금 → 정산 자동 연결
- 정기결제 자동 감지
- 알림 수집 앱 선택 (어느 금융 앱을 읽을지)
- 사실 기반 분석/절약 제안 (숫자는 앱이, 문장만 LLM)
- 파싱 실패 보관함
- 앱 내부 동작 로그

---

## 3. 아키텍처와 프로젝트 구조

Clean Architecture + feature-first. 기능별로 3층이 반복된다.

```
lib/
├── main.dart                 # 로케일 → DI init → 권한 있으면 수집 시작 → AI 대기열 확인
├── app.dart                  # MaterialApp, 테마, 로컬라이제이션
├── presentation/
│   ├── home_shell.dart       # 하단 탭 5개 (IndexedStack)
│   └── widgets/period_selector.dart
├── core/
│   ├── constants/            # app_categories(분류 체계), classification_source, payment_sources
│   ├── database/
│   │   ├── db_schema.dart    # ★ 테이블/컬럼/CREATE/마이그레이션/공통 SQL 단일 소스
│   │   ├── app_database.dart # open / upgrade / 시드 주입
│   │   └── seed/brand_seed.dart
│   ├── di/injector.dart      # ★ 서비스 로케이터 (의존 관계 전체가 이 한 파일에 보인다)
│   ├── error/failures.dart
│   ├── logging/app_logger.dart   # 앱 내 로그 화면용 링 버퍼
│   ├── theme/app_theme.dart      # CVD 검증 카테고리 팔레트 + 수입/지출 의미색
│   └── utils/                # date_range, month_range, formatters, text_normalizer
└── features/<기능>/
    ├── domain/
    │   ├── entities/         # 순수 Dart. DB/JSON 을 모른다
    │   ├── repositories/     # abstract interface class
    │   ├── services/         # 순수 로직 (정책, 파서, 매퍼)
    │   └── usecases/         # 한 동작 = 한 클래스
    ├── data/
    │   ├── datasources/      # SQL / HTTP / MethodChannel
    │   ├── models/           # DTO (fromRow / toRow)
    │   └── repositories/     # 구현체
    └── presentation/
        ├── controllers/      # ChangeNotifier
        ├── screens/
        └── widgets/
```

기능 목록 (15개):

```
assets  classification  dashboard  ingest  insights  merchants
notifications  parsing  projects  recurring  search  settings
settlements  statistics  transactions
```

### 네이티브 (Kotlin)

`android/app/src/main/kotlin/com/example/budget_book/`

| 파일 | 역할 |
|---|---|
| `MainActivity.kt` | FlutterActivity + 브릿지 등록 |
| `NotificationBridge.kt` | MethodChannel / EventChannel 핸들러 |
| `PaymentNotificationListenerService.kt` | 알림 수신, 키워드 1차 필터, 큐 적재 |
| `NotificationQueueStore.kt` | JSONL 파일 큐 (읽기+삭제를 한 lock 안에서) |
| `NotificationSourceStore.kt` | 수집 대상 앱 SharedPreferences 캐시 |

---

## 4. 데이터베이스

**단일 소스는 `lib/core/database/db_schema.dart` 다.** 테이블·컬럼 문자열을 다른 곳에 직접 쓰지 말고 반드시 이 상수를 참조한다.

현재 `databaseVersion = 17`. 마이그레이션은 `DbSchema.migrations` (`Map<int, List<String>>`) 에 버전별로 모아 두고, `app_database.dart` 의 `onUpgrade` 가 `from < key` 인 항목을 순서대로 실행한다.

### 테이블 14개

| 테이블 | 역할 | 비고 |
|---|---|---|
| `transactions` | **원본 거래.** 가계부의 중심 | 금액을 고쳐 쓰지 않는다 |
| `merchants` | 학습된 가맹점 (원본 거래명 → 분류) | |
| `brand_rules` | 브랜드 표기(alias) 규칙 (시드 + 사용자) | `priority` 로 사용자 규칙이 시드를 이긴다. 시드는 `BrandDefinition` 에서 생성 |
| `settlements` | 더치페이로 돌려받은 금액 | 거래 1:N |
| `deposits` | 입금 알림 (정산 후보) | **브랜드 학습 안 함** |
| `recurring_rules` | 정기결제 규칙 | 거래 위의 메타데이터 |
| `asset_transfers` | 자산 이동 상세 (어느 계좌 → 어디로) | |
| `projects` | 거래 묶음(폴더) | 삭제 시 거래는 `SET NULL` |
| `accounts` | 자산 계좌와 **기준** 잔액 | 현재 잔액은 파생값 |
| `account_snapshots` | 잔액 추이 기록 | |
| `card_account_links` | 카드 이름 → 계좌 | 알림 거래를 잔액에 반영하는 다리 |
| `deposits.transaction_id` | 입금 → 그 입금이 만든 수입 거래 | 정산 확정 시 분류를 옮기는 고리 |
| `notification_sources` | 수집 대상 앱 | 원본은 여기, 네이티브는 캐시 |
| `brand_metadata` | 브랜드 업종/분류 캐시 | **못 찾음도 저장** |
| `settings` | key-value 설정 | |
| `ingest_failures` | 파싱 실패 보관함 | 파서 개선용 재료 |
| `unmapped_place_categories` | 못 옮긴 카카오 업종 | 매핑표를 늘릴 근거. 추측 금지 |

### 스키마 버전별 변경 이력

#### v1 — 최초
- 테이블: `merchants`, `brand_rules`, `transactions`, `settings`, `ingest_failures`
- 인덱스: 지문 UNIQUE, 결제 시각, 브랜드, 카테고리

#### v2 — 사용자 확인 큐
- **추가 컬럼**: `transactions.needs_review INTEGER NOT NULL DEFAULT 0`
- **인덱스**: `idx_tx_needs_review`
- 이유: LLM 없이도 쓸 수 있어야 한다. 처음 보는 브랜드를 "분류 필요" 로 남기고 사용자가 한 번 고른다.

#### v3 — 이체 거래 표현
- **추가 컬럼**: `transactions.display_name TEXT`, `transactions.tag TEXT`
- 이유: 이체 거래는 브랜드를 학습하지 않으므로, 원본 거래명을 보존한 채 목록에 다르게 보여 줄 수단이 필요했다.

#### v4 — 정산(더치페이)
- **추가 테이블**: `settlements`, `deposits`
- **인덱스**: `idx_settlement_tx`, `idx_deposit_status`, `idx_deposit_time`
- 이유: 원본 거래 금액을 고치지 않고 "돌려받은 돈" 을 따로 기록한다.

#### v5 — 정기결제 · 자산 이동
- **추가 테이블**: `recurring_rules`, `asset_transfers`
- **추가 컬럼**: `transactions.recurring_rule_id INTEGER`, `transactions.is_asset_transfer INTEGER NOT NULL DEFAULT 0`
- **인덱스**: `idx_tx_asset_transfer`, `idx_tx_recurring`, `idx_recurring_active`, `idx_recurring_brand`, `idx_asset_tx`
- 이유: 거래 타입을 늘리지 않고 거래 **위에** 메타데이터를 얹는다.

#### v6 — 직접 입력 · 수입 · 계좌 · 프로젝트
- **추가 테이블**: `projects`, `accounts`, `account_snapshots`
- **추가 컬럼**: `transactions.entry_source`, `direction`, `account`, `project_id`
- **인덱스**: `idx_tx_project`, `idx_tx_direction`, `idx_snapshot_account`
- 이유: 현금·중고거래 같은 알림 없는 거래와 수입을 담아야 했다.

#### v7 — 알림 수집 앱 · 브랜드 업종 캐시
- **추가 테이블**: `notification_sources`, `brand_metadata`
- **인덱스**: `idx_source_enabled`
- 이유: 금융 앱을 여러 개 쓰면 같은 결제가 여러 번 알림으로 온다. 그리고 외부 조회는 브랜드당 1회로 묶어야 한다.

#### v8 — 잔액 자동 반영 · 자산 종류
- **추가 컬럼**:
  - `transactions.account_id INTEGER REFERENCES accounts(id) ON DELETE SET NULL`
  - `transactions.asset_kind TEXT` (`saving` / `housing` / `investment` / `other`)
  - `accounts.balance_as_of INTEGER NOT NULL DEFAULT 0`
- **인덱스**: `idx_tx_account`
- **데이터 마이그레이션**: 기존 계좌의 `balance_as_of` 를 마이그레이션 시각으로 설정
  ```sql
  UPDATE accounts SET balance_as_of = CAST(strftime('%s','now') AS INTEGER) * 1000
  WHERE balance_as_of = 0
  ```
  0으로 두면 과거 거래가 전부 소급 반영되어 **사용자가 이미 입력해 둔 잔액이 갑자기 바뀐다.**

#### v9 — AI 분류 대기열
- **추가 컬럼**:
  - `transactions.ai_status TEXT NOT NULL DEFAULT 'none'` (`none`/`pending`/`processing`/`completed`/`failed`)
  - `transactions.ai_processed_at INTEGER`
- **인덱스**: `idx_tx_ai_status`
- **데이터 마이그레이션**: 이미 쌓여 있는 "분류 필요" 거래를 대기열에 편입
  ```sql
  UPDATE transactions SET ai_status = 'pending' WHERE needs_review = 1
  ```
  이 기능이 생기기 전에 모인 미분류도 한 번에 정리할 수 있어야 한다.

#### v10 — 카드 → 계좌 연결
- **추가 테이블**: `card_account_links` (`card_name` PK, `account_id`, `created_at`)
- 알림은 카드 이름만 준다. 그 카드가 어느 계좌에서 빠져나가는지 앱은 알 수 없다.
  연결이 없으면 수집된 거래에 `account_id` 가 없고, **아무리 쌓여도 잔액이 움직이지 않는다.**
- **계좌 이름으로 짐작하지 않는다.** `KB국민카드` 와 `KB 입출금` 이 비슷하다고 이어 붙이면,
  틀렸을 때 잔액이 조용히 어긋나고 사용자가 알아챌 방법이 없다. 사용자가 한 번 지정한다.
- 데이터 마이그레이션은 없다. 연결은 사용자가 만드는 값이라 추측해서 채울 수 없다.

#### v11 — 입금을 수입으로
- **추가 컬럼**: `deposits.transaction_id` (그 입금으로 만들어진 수입 거래)
- 그전까지 입금 알림은 `deposits` 에만 들어갔다. 통계는 `transactions` 만 읽으므로
  **월급도 용돈도 수입 통계에 잡히지 않았다.** 이제 입금은 두 곳에 남는다 —
  정산 후보(`deposits`)와 수입 거래(`transactions`).
- 정산으로 확정되면 그 수입 거래를 `정산` 분류로 옮긴다. 돌려받은 돈은 번 돈이 아니다.
  이미 원결제의 `settlements` 로 부담이 줄었으므로 수입으로도 세면 두 번 세는 것이다.
- 데이터 마이그레이션은 없다. 옛 입금에는 연결이 없고(`NULL`), 그 경우 분류 이동만 건너뛴다.

#### v12 — 취소된 원결제도 통계에서 제외
- **추가 컬럼 없음.** 데이터만 고친다.
- 그전까지 `is_cancelled` 는 취소 건에만 붙었고 통계는 이 값을 보지 않았다.
  금액은 상계되어 맞았지만 **건수가 오염**됐다 — 취소된 결제 한 번 때문에
  "가장 많이 간 가게" 1위가 되는 식이다.
- 이제 취소가 오면 **원결제에도** 표시를 달고, 통계는 `is_cancelled = 0` 한
  조건으로 둘 다 뺀다.
- **데이터 마이그레이션**: 이미 쌓인 취소 쌍의 원결제에 표시를 단다.
  ```sql
  UPDATE transactions SET is_cancelled = 1 WHERE id IN (...)
  ```
  이 이관이 없으면 취소 건만 빠지고 원결제가 남아 **오히려 나빠진다.**
  같은 브랜드 + 같은 금액 + 60일 이내의 가장 가까운 결제 하나만 짝짓는다.

#### v13 — 분류 진단
- **추가 테이블**: `unmapped_place_categories`
  (`category_name` PK, `sample_merchant`, `hit_count`, `first_seen_at`, `last_seen_at`)
- 매핑표를 **추측으로** 늘리지 않기 위한 근거다. 실제로 무엇이 막히는지 모르면
  "브런치도 넣어야 하나" 를 감으로 결정하게 된다.
- 두 가지를 수집한다.
  - 아예 못 옮긴 업종
  - **큰 분류로만 옮긴 업종** — `음식점 > 브런치` 가 `음식점` 규칙에 걸려
    `식비/기타` 가 되는 경우다. 매핑에는 "성공" 했지만 정보가 사라졌고,
    사용자가 겪는 "식비 하나로만 들어간다" 가 바로 이것이다.
- 설정 > 개발자 > 분류 진단 (`kDebugMode` 에서만 보인다)

#### v14 — 자산 이동이 계좌 잔액에 반영된다
- **추가 컬럼**: `asset_transfers.to_account_id`
- 그전까지 `balanceDeltaExpr` 이 자산 이동을 **0** 으로 두었다. 총자산이 변하지
  않는다는 이유였는데, 그러면 **계좌별로는 틀린다** — 입출금에서 적금으로
  100,000원을 옮겨도 입출금 잔액이 그대로였다.
- 총자산이 안 변하는 것은 **받는 계좌가 그만큼 늘기 때문**이지, 나간 계좌가
  안 줄어서가 아니다. 이제 나간 계좌는 `-amount`, 받는 계좌는
  `asset_transfers.to_account_id` 로 `+amount`.
- **이름이 아니라 id 로 잇는다.** `to_account` 는 표시용이다. 이름 매칭은
  계좌 이름을 바꾼 순간 잔액이 조용히 어긋난다(`account_id` 와 같은 이유).
- **데이터 마이그레이션은 없다.** 옛 기록에는 이름만 있어 채울 수 없다.
  `to_account_id` 가 null 이면 나간 쪽만 반영된다(추적하지 않는 곳으로 나간
  것과 같다). 필요하면 거래를 열어 받는 계좌를 다시 고르면 된다.

#### v15~v17 — 알림 병합과 취소 매칭
- **v15**: 체크카드 결제가 계좌이체로 저장돼 있던 것을 카드로 교정.
  이체로 판정되면 상대방 이름 보호 정책이 걸려 카카오도 AI 도 돌지 않는다.
- **v16**: `transactions.account_number`, `balance_after`, `merged_sources`.
  같은 결제를 토스와 은행이 각각 알린다. **거래는 하나만 남기고 정보만 합친다.**
  토스는 브랜드를, 은행은 계좌와 잔액을 담당한다(`NotificationSourceTrait`).
- **v17**: `transactions.cancels_transaction_id`.
  **취소 알림에는 가맹점 이름이 없다.**
  ```
  [결제] ... 카카오T비  체크카드출금 3,400 잔액1,268,162
  [취소] ... 출금취소 3,400 잔액1,271,562
  ```
  그래서 브랜드로 맞추지 않는다. 같은 카드 + 같은 금액 + 취소 이전으로 좁히고
  **후보가 하나뿐일 때만** 자동으로 잇는다. 여럿이면 사용자가 고른다 —
  틀리게 이으면 엉뚱한 결제가 통계에서 조용히 사라진다.
  오래된 취소(7일 초과)는 자동으로 잇지 않는다.

> **삭제된 컬럼은 없다.** SQLite 의 `DROP COLUMN` 지원이 제한적이고, 컬럼을 지우면 구버전 DB 에서 올라온 사용자의 데이터가 사라질 수 있다. 쓰지 않게 된 값은 남겨 두고 읽지 않는다.

### 통계용 공통 SQL 조각 (매우 중요)

`db_schema.dart` 에 정의된 조각을 **모든 집계에서 재사용한다.** 화면마다 SQL 을 새로 쓰면 같은 기간에 다른 금액이 보인다.

```dart
// 이 거래에 붙은 정산 합계
static const String settledSumExpr =
    '(SELECT COALESCE(SUM(s.amount), 0) FROM settlements s '
    'WHERE s.transaction_id = t.id)';

// 실제 부담 금액 = 결제액 - 정산액
static const String netAmountExpr = '(t.amount - $settledSumExpr)';

// 나가는 돈만(자산 이동 포함). 현금 흐름에 쓴다.
static const String expenseOnly = "t.direction = 'expense'";

// 들어오는 돈만.
static const String incomeOnly = "t.direction = 'income'";

// 소비 지표: 자산 이동 제외 + 수입 제외
static const String spendingOnly = 't.is_asset_transfer = 0 AND $expenseOnly';

// 자산 이동만. 종류는 asset_kind 로 나눈다.
static const String assetTransferOnly = 't.is_asset_transfer = 1 AND $expenseOnly';

// 계좌 잔액에 더할 부호 있는 금액. 수입 +, 지출 -, 자산 이동 0.
static const String balanceDeltaExpr = 'CASE '
    'WHEN t.is_asset_transfer = 1 THEN 0 '
    "WHEN t.direction = 'income' THEN t.amount "
    'ELSE -t.amount END';

// AI 분석을 기다리는 거래
static const String aiPendingOnly = "t.ai_status = 'pending'";
```

> ⚠️ **수입은 양수로 저장되고 `direction` 으로만 구분된다.**
> 집계에서 방향 조건을 빼면 수입이 지출에 더해진다. 실제로 300,000원 입금 + 15,000원 결제가 **315,000원**으로 표시되던 버그가 이것이었다(Round 11).

### `transactions` 핵심 컬럼

| 컬럼 | 의미 | 주의 |
|---|---|---|
| `merchant_raw` | 알림 원본 거래명 | **사용자 수정으로 절대 덮어쓰지 않는다.** 이체에서는 상대방 이름 |
| `brand` | 브랜드명 | 가맹점 결제에서만 학습 대상 |
| `display_name` | 사용자 지정 표시 이름 | 원본을 보존한 채 다르게 보여주기 위함 |
| `amount` | 결제 금액 | 취소는 음수. **정산으로 고치지 않는다** |
| `direction` | `expense` \| `income` | 수입은 소비 통계 제외 |
| `is_asset_transfer` | 1이면 자산 이동 | 소비 제외, 현금 흐름 포함 |
| `asset_kind` | 저축/청약/투자/기타 | `is_asset_transfer = 1` 일 때만 의미 |
| `entry_source` | `notification` \| `manual` | |
| `account` / `account_id` | 표시용 이름 / 잔액 반영 대상 | 이름으로 매칭하면 이름 변경 시 어긋난다 |
| `project_id` | 프로젝트 연결 | |
| `fingerprint` | **UNIQUE.** 중복 저장 방지 | 알림 재수신 대비 |
| `needs_review` | 1이면 "분류 필요" 노출 | 사용자가 한 번 고르면 0 |
| `ai_status` | AI 대기열 상태 | v9 |
| `classification_source` | `seed`/`rule`/`llm`/`user`/`pending` | |

---

## 5. AI 파이프라인

### 분류 우선순위

```
결제 알림
   ↓
① 사용자 규칙 / 학습된 가맹점         ← DB, 즉시
   ↓ (없으면)
② 내장 브랜드 사전 (brand_rules)      ← DB, 즉시
   ↓ (없으면)
③ 카카오 장소 API (브랜드당 1회)      ← 선택, 캐시 우선
   ↓ 성공 → 카테고리 저장 · 학습 · 끝
   ↓ 실패
④ AI Pending Queue 저장 (ai_status = 'pending')
   ↓  ... 저장은 여기서 끝난다. 거래는 이미 기록되어 통계에 들어간다 ...
   ↓
   ─────── 나중에, 노트북이 켜졌을 때 ───────
   ↓
⑤ Ollama 연결 확인
   ↓
   브랜드로 묶기 → 브랜드 캐시 확인 → (없으면) LLM 1회
   ↓
   brand_metadata 갱신 + 가맹점 학습 + 브랜드 규칙 승격
   ↓
   같은 브랜드 거래 전체 갱신 · pending 해제
   ↓
⑥ 그래도 못 하면 사용자 직접 선택 (항상 존재하는 최종 수단)
```

**위쪽에서 해결되면 아래는 호출하지 않는다.** 사전에 있는 브랜드는 ③을 절대 호출하지 않고(테스트로 호출 횟수를 센다), ③이 성공하면 ④~⑤가 없다.

### 계층별 구현

| 단계 | 클래스 |
|---|---|
| ①② | `MerchantRepositoryImpl.lookup` → `BrandExtractor` (가맹점 캐시 → 브랜드 사전) |
| ③ | `LookupBrandIndustry` + `PlaceApiDataSource` + `PlaceCategoryMapper` |
| ④ | `RecordPaymentNotification._resolveUnknown` → `ai_status = 'pending'` |
| ⑤ | `ProcessAiPendingQueue` + `ClassifierRepositoryImpl` + `OllamaRemoteDataSource` |
| ⑥ | `ReviewQueueScreen` + `ApplyUserCorrection` |

### LLM 응답 검증

LLM 이 만들어낸 값이 그대로 DB 에 들어가는 경로는 **없다.**

- `OllamaRemoteDataSource` — 응답을 **JSON 만** 받는다
- `ClassifierRepositoryImpl` — 파싱 실패 / 타임아웃 / 체계 밖의 값은 전부 `미분류` 로 떨어뜨린다
- `CategoryTaxonomy.coerce` — 없는 카테고리를 안전한 값으로 보정
- 확신도가 `minConfidenceToLearn` 미만이면 학습하지 않는다

---

## 6. AI Pending Queue

### 왜 만들었나

이전에는 처음 보는 브랜드를 만나면 **결제 순간에** Ollama 를 호출했다. 문제:

1. 노트북이 꺼져 있으면 매 결제마다 타임아웃(최대 25초)을 기다린다
2. 그 시간 동안 알림 처리가 막히고 배터리를 쓴다
3. 밖에서는 Ollama 가 거의 항상 꺼져 있다 — 즉 **대부분의 경우 헛수고**

그래서 저장과 AI 를 분리했다. 결제 순간에는 저장만 하고, AI 는 가능할 때 몰아서 한다.

### 장점

- 노트북이 없어도 앱이 완전히 동작한다
- 실시간 AI 호출이 없어 저장이 빠르고 배터리를 쓰지 않는다
- 같은 브랜드는 AI 를 **한 번만** 호출한다
- 브랜드 캐시가 쌓일수록 AI 호출량이 계속 줄어든다
- 개인정보를 외부 AI 서버로 보내지 않는다 (Ollama 는 사용자 본인 로컬)

### 동작 방식

`ProcessAiPendingQueue` (`lib/features/classification/domain/usecases/`)

```
1. AI 가 꺼져 있으면 → 실행 안 함
2. 대기 건수 0이면 → 연결 확인조차 안 함 (헬스체크도 낭비다)
3. Ollama 헬스체크 → 실패하면 대기 그대로 남김
4. 대기 거래를 브랜드로 묶는다
5. 브랜드마다:
   a. BrandLearningPolicy 재확인 (이체·사람 이름은 건너뜀 → ai_status = none)
   b. ai_status = 'processing' 표시
   c. brand_metadata 캐시 확인 → 있으면 LLM 호출 안 함 (cacheHits++)
   d. 없으면 LLM 1회 (llmCalls++)
   e. 실패 → ai_status = 'failed'
   f. 성공 → brand_metadata 저장 + 가맹점 학습 + 브랜드 규칙 승격
             + 같은 브랜드 거래 전체 갱신 → ai_status = 'completed'
6. 결과 반환 (브랜드 수 / 거래 수 / LLM 호출 수 / 캐시 히트 / 실패 수)
```

### 상태

| 상태 | 의미 |
|---|---|
| `none` | AI 가 필요 없다(이미 분류됨) 또는 대상이 아니다(이체 등) |
| `pending` | 분석 대기 |
| `processing` | 분석 중. **같은 브랜드를 두 번 집어오지 않기 위한 표시** |
| `completed` | 분석 완료 |
| `failed` | 분석 실패. 언제든 재시도 가능 |

`aiPendingOnly` 조건은 `processing` 을 포함하지 않는다. 처리 중인 것을 다시 집어 오면 같은 브랜드를 두 번 호출한다.

### 실패 처리

- 분류 실패 / 확신도 미달 / 예외 → `failed`
- **조용히 사라지지 않는다.** 실패로 남으므로 왜 미분류인지 알 수 있고 언제든 다시 시도할 수 있다
- 한 브랜드가 예외로 죽어도 루프는 끝까지 돈다 (테스트로 확인)

### 브랜드당 1회

이 기능의 핵심 약속이다. `행복반점` 을 15번 결제해도 LLM 호출은 1회다.

```
행복반점 15건 → 브랜드로 묶기 → LLM 1회 → 15건 일괄 갱신
```

테스트가 "동작한다" 가 아니라 **"몇 번 불렀나"** 를 검증한다 (`test/ai_pending_queue_test.dart`).

### 안전장치

- 사용자가 직접 분류한 거래는 AI 결과로 덮지 않는다 (SQL `WHERE classification_source != 'user'`)
- 이체/송금·사람 이름은 대기열에 넣지 않는다 (AI 로도 분류 불가 → 매번 실패하며 건수만 늘어난다)
- 한 번에 40개 브랜드까지만 처리한다 (`maxBrandsPerRun`). 로컬 LLM 은 브랜드당 수 초라서 수백 개를 한 번에 돌리면 끝나지 않는 작업이 된다. 남은 것은 다음 실행에서

### UI

`AI 분석 대기 23건 [지금 분석]` 배너 — 대시보드 최상단 + 설정 화면.

- 배너는 **Ollama 에 닿을 때만** 나타난다. 노트북이 꺼져 있으면 사용자가 할 수 있는 일이 없다
- 대기 건수는 설정 화면에서 항상 확인 가능
- 앱 시작 시 `aiQueue.initialize()` 를 **await 하지 않는다.** 헬스체크가 수 초 걸릴 수 있는데 기다리면 첫 화면이 늦게 뜬다
- 분석 중에도 거래 목록·통계를 그대로 쓸 수 있다 (**AI 는 UI 를 막지 않는다**)

---

## 7. Ollama

### 로컬 AI 를 선택한 이유

1. **비용 0원.** 클라우드 LLM 은 토큰당 과금이다. 가계부는 거래가 쌓일수록 호출이 늘어난다
2. **개인정보.** 가맹점 이름과 소비 패턴은 민감하다. 외부 서버로 보내지 않는다
3. **선택 가능.** 없어도 앱이 완전히 동작한다

### 모델

기본값은 **`gemma3:4b`** 다 (`AppSettings.defaultOllamaModel`).

- 4B 급 모델을 쓰는 이유: 이 작업은 "가맹점 이름 → 업종 분류" 라는 좁은 분류 문제다. 큰 모델이 필요하지 않고, 노트북에서 CPU 로도 수 초 안에 답한다
- 모델 이름은 **설정에서 바꿀 수 있다.** Ollama 에 설치된 어떤 모델이든 쓸 수 있다
- 설정에서 "연결 테스트" 를 누르면 서버 연결과 모델 설치 여부를 함께 확인한다

### 모델에 따라 요청이 달라진다

사용자가 아무 모델이나 넣을 수 있으므로 `OllamaRemoteDataSource` 가 적응한다.

| 모델 | `think` 필드 | 프롬프트 `/no_think` |
|---|---|---|
| `gemma3`, `llama3.2`, `mistral`, `phi4`, `qwen2.5` | 보내지 않음 | 없음 |
| `qwen3*`, `*deepseek-r1*`, `*-r1*`, `*thinking*` | `think: false` | 붙임 |

**틀렸을 때의 손해가 비대칭이다.**

- 추론 모델을 못 알아보면 `<think>` 블록이 섞여 오는데, 응답 정리 단계에서 어차피 제거한다 → 회복 가능
- 반대로 일반 모델에 `think` 를 보내면 최신 Ollama 가 `does not support thinking` 으로 **요청 전체를 거절한다** → 분류 실패

그래서 `isThinkingModel` 은 **확실한 것만** 추론 모델로 판단한다.
`<think>` 블록 제거는 모델과 무관하게 항상 수행한다(방어적).

### 노트북이 꺼져 있을 때

- 헬스체크 실패 → 대기열은 그대로 남는다
- 배너를 띄우지 않는다 (사용자가 할 수 있는 일이 없다)
- **거래 기록·통계·검색·수정은 전부 정상 동작한다**

### 노트북이 켜졌을 때

```
앱 시작 (또는 사용자가 [지금 분석] 탭)
  ↓
대기 건수 확인 → 0이면 끝
  ↓
Ollama 헬스체크
  ↓ 연결됨
브랜드별 일괄 분석 → 캐시 갱신 → 거래 전체 갱신
  ↓
"거래 23건 분류 · AI 호출 7회" 스낵바
```

### 주소 설정

| 환경 | 주소 |
|---|---|
| Android 에뮬레이터 | `http://10.0.2.2:11434` (기본값) |
| 실제 기기 | `http://<PC 의 LAN IP>:11434` (예: `http://192.168.0.10:11434`) |

실기기에서 쓰려면 노트북에서 Ollama 를 외부 접속 허용으로 띄워야 한다:

```bash
# Windows (PowerShell)
$env:OLLAMA_HOST="0.0.0.0:11434"; ollama serve
ollama pull gemma3:4b
```

### 캐시 전략

```
LLM 결과 → brand_metadata (브랜드 단위)
         → merchants      (원본 거래명 단위)
         → brand_rules    (패턴 단위, 아직 본 적 없는 지점까지 커버)
```

세 층에 저장하므로, 같은 브랜드는 물론이고 **처음 보는 지점**도 다음부터 AI 없이 분류된다.

---

## 8. 카카오 장소 API

### 무엇을 하나

브랜드 이름으로 장소를 검색해 **업종**을 알아낸다.

```
"동네작은카페" → 카카오 검색 → "음식점 > 카페 > 커피전문점" → 식비/카페
```

`PlaceCategoryMapper` 가 업종 계층 문자열을 앱의 분류 체계로 옮긴다. **오른쪽(가장 구체적)부터 검사한다** — 왼쪽부터 보면 `음식점` 에 걸려 정보가 사라진다.

### 후보 다수결 (`resolveConsensus`)

**후보 5개를 한 번의 호출로 받아 업종이 일치하는지 본다.** 한 건만 믿으면
`본가` 처럼 흔한 이름에서 엉뚱한 분류가 사용자에게 묻지도 않고 확정된다.

| 후보 업종 | 결과 |
|---|---|
| (0개) | 판단 불가 → AI 대기열 |
| 1개 | 그대로 자동 분류 |
| 한식 · 한식 · 한식 | 만장일치 → 자동 분류 |
| 한식 · 한식 · 한식 · 중식 | 다수 → 자동 분류 |
| 카페 · 병원 · 약국 · 세탁 | 판단 불가 → AI 대기열 |
| 한식 · 한식 · 중식 · 중식 | 동점 → 판단 불가 |

판단 기준: 후보가 1개면 그대로, 2개 이상이면 **최다 득표가 2표 이상이고
2위보다 많아야** 한다. 자동 분류는 사용자 확인 없이 확정되므로 애매하면 넘긴다.

우리 체계로 옮길 수 없는 후보는 투표에서 제외한다(`mappable` 로 셈).

**API 호출 횟수는 1회로 같다.** `size` 만 1 → 5 로 바뀌었다.
판단 실패도 캐시하므로 재조회로 할당량을 쓰지 않는다 —
다시 물어도 같은 후보가 오기 때문이다.

> LLM 은 최후의 수단이다. 앱이 충분히 판단할 수 있으면 Ollama 를 부르지 않는다.
> 응답 속도·전력·정확도가 모두 이 방향으로 개선된다.

### 위치 기반 검색을 쓰지 않는 이유

GPS 좌표로 주변 가게를 찾는 방식은 쓰지 않는다.

- 백화점·푸드코트·역사에서는 한 좌표에 수십 개 가게가 있다
- 결제 알림에 이미 가맹점 이름이 있다. 이름이 좌표보다 정확하다
- 위치 권한을 요구하지 않으므로 개인정보 노출도 없다

### 무료 사용 전략 (비용 방지)

**사용자에게 비용이 발생하면 안 된다** 는 것이 이 프로젝트의 가장 강한 제약이다.

| 장치 | 내용 |
|---|---|
| 사용자 본인 키 | 앱에 개발자 키를 심지 않는다. 심으면 추출되어 오용되고 할당량이 전체 사용자에게 공유된다 |
| 무료 API | 카카오 로컬 API 는 무료이고 카드 등록이 필요 없다 → 과금 경로가 구조적으로 없다 |
| 브랜드당 1회 | 캐시 우선. 같은 브랜드를 두 번 조회하지 않는다 |
| **실패도 캐시** | `found = false` 로 저장. 없으면 업종을 못 찾는 브랜드를 결제마다 재조회해 할당량이 순식간에 사라진다 |
| 429 자동 중단 | 한도 초과를 받으면 **24시간 자동으로 쉰다** (`placeApiBlockedUntilMillis`) |
| 키 없으면 비활성 | 기능이 그냥 꺼진 상태로 동작한다 |
| 개인정보 최소 | **브랜드 이름만** 보낸다. 금액·카드·날짜는 보내지 않는다 |
| 이체 제외 | 상대방 이름은 절대 보내지 않는다 (아래 참고) |

### 429 대응

```
429 수신
  ↓
placeApiBlockedUntilMillis = now + 24h  저장
  ↓
그 사이 모든 조회 요청은 호출 없이 즉시 null
  ↓
앱은 정상 동작 (AI 대기열 또는 사용자 선택으로 넘어간다)
  ↓
설정 화면에 "호출 한도 초과로 쉬는 중 · [지금 재시도]" 표시
```

일시적 실패(네트워크 오류, 타임아웃)와 한도 초과는 **캐시하지 않는다.** "못 찾았다" 와 "지금 못 물어봤다" 는 다르다.

### 캐시 정책

| 상황 | 캐시? |
|---|---|
| 업종 찾음 | ✅ `found = true` + 분류 |
| 결과 없음(notFound) | ✅ `found = false` — 재조회 방지 |
| 업종은 찾았지만 체계로 못 옮김 | ✅ `found = false` + 업종 문자열 보존 |
| 네트워크 실패 | ❌ 다시 시도할 수 있어야 한다 |
| 429 한도 초과 | ❌ 일시적 상태다 |
| 사용자가 직접 수정 | ✅ `user_modified = 1` — 자동 조회가 덮지 못한다 |

### 키 발급

`developers.kakao.com` → 내 애플리케이션 → 앱 키 → **REST API 키**
앱의 설정 → "카카오 REST API 키" 에 입력 → "키 확인" 으로 검증

---

## 9. 알림 처리 흐름

```
[Android] 카드사 앱이 알림 게시
   ↓
PaymentNotificationListenerService.onNotificationPosted
   ↓ ① PAYMENT_KEYWORDS 1차 필터
   ↓    (승인 결제 출금 취소 이체 지불 송금 보냈 입금 받았)
   ↓ ② NotificationSourceStore.recordSeen   — 앱 발견 기록
   ↓ ③ NotificationSourceStore.shouldCollect — 대상 아니면 여기서 끝
   ↓
NotificationQueueStore → JSONL 파일에 append
   ↓
EventChannel 로 "큐에 뭔가 들어왔다" **신호만** 전송 (내용 없음)
   ↓
[Flutter] NotificationIngestService
   ↓ drainQueue() — 읽기+삭제를 네이티브 한 lock 안에서
   ↓
RecordPaymentNotification (파싱 → 분류 → 저장)
```

### 왜 이렇게 나눴나 (바꾸면 안 되는 이유)

**알림 내용은 오직 파일 큐로만 전달된다. EventChannel 은 신호만 보낸다.**

- Flutter 엔진은 앱이 백그라운드에서 종료되면 사라지지만 리스너 서비스는 살아 있다. 파일에 쌓아 두면 **앱이 죽어 있는 동안의 알림도 유실되지 않는다**
- 실시간 스트림과 파일 큐 **양쪽으로 내용을 받으면 같은 알림이 두 번 처리된다.** 경로를 하나로 못박아 중복을 구조적으로 없앴다

**네이티브 키워드 필터는 Dart 파서보다 항상 넓어야 한다.** 네이티브에서 버린 알림은 Dart 가 볼 기회조차 없다. (`송금`/`입금` 이 빠져 있어 송금·입금이 조용히 사라지던 버그가 실제로 있었다)

**수집 대상 앱 설정의 원본은 SQLite, 네이티브 SharedPreferences 는 캐시다.** 리스너는 Flutter 엔진 없이 돌기 때문에 DB 를 읽을 수 없다. 저장할 때마다 양쪽을 갱신하고, 앱 시작 시 `syncToNative()` 로 맞춘다.

**아무 앱도 선택하지 않았으면 전체 수집한다.** 설정 전에 아무것도 안 쌓이면 사용자는 앱이 고장난 줄 안다.

### 중복 저장 방지 (2단)

| 단계 | 기준 |
|---|---|
| 1. 지문(UNIQUE) | `(merchantRaw, signedAmount, 분 단위 시각, cardName)` — 같은 알림 재수신 |
| 2. 근접 중복 | 금액·브랜드·결제수단 동일 + 시각 **±30초** — 다른 앱이 같은 결제를 알린 경우 |

지문에 카드명이 들어가고 시각이 분 단위로 잘리므로, KB 앱과 토스 앱이 문구를 다르게 주거나 `14:30:59` / `14:31:01` 로 분 경계를 넘으면 지문이 갈린다. 그래서 2단이 필요하다.

직접 입력은 근접 중복 검사를 **하지 않는다.** 사용자가 의도적으로 추가한 거래를 조용히 버리면 "저장했는데 없어졌다" 가 된다. (같은 현금 결제를 두 번 하는 것도 정상이다)

---

## 10. 브랜드 학습 정책

가장 크게 다뤄진 문제다. `BrandLearningPolicy` (순수 함수, DB 접근 없음)가 **학습을 허용할지 판단하는 유일한 지점**이다.

### 왜 필요한가

`000 스마트폰` 에게 보낸 송금을 "메가커피" 로 고치고 학습하면, **이후 그 상대방에게 보내는 모든 송금이 메가커피가 된다.** 송금의 *목적*은 매번 달라지지만 *상대방 이름*은 그대로이기 때문이다.

### 판단 표

| 거래 유형 | 학습 |
|---|---|
| 카드 / 체크카드 | ✅ 허용 |
| 네이버페이·카카오페이 **가맹점 결제** | ✅ 허용 |
| 배달의민족 등 가맹점 | ✅ 허용 |
| 현금(직접 입력) | ✅ 허용 (사용자가 직접 가맹점을 적었다) |
| 계좌이체 / 송금 | ❌ 금지 (`blocked`) |
| 결제 수단 미확인 | ❌ 금지 |
| 전화번호 / 계좌번호 / 마스킹된 이름 | ❌ 금지 |
| 성씨로 시작하는 2~3글자 한글 | ⚠️ `discouraged` — 막지 않고 사용자에게 맡긴다 |

`discouraged` 인 이유: `이마트`, `김밥천국` 처럼 성씨로 시작하는 실제 상호가 많다. 자동으로 막으면 정상 브랜드를 학습하지 못한다.

### 이 정책을 통과하는 경로 (4곳)

1. `RecordPaymentNotification._learn` — 자동 분류 결과 학습
2. `RecordPaymentNotification._lookupIndustry` — **외부 API 전송 게이트**
3. `ApplyUserCorrection` — 사용자 수정 학습
4. `ProcessAiPendingQueue` — AI 일괄 분석

**새 경로를 만들면 반드시 이 정책을 붙여야 한다.**

2번은 학습이 아니라 **개인정보 전송**을 막는다. `홍길동` 을 카카오 장소 검색에 보내면 (a) 사람 이름이 기기 밖으로 나가고 (b) `홍길동` 이라는 가게가 검색되어 엉뚱하게 자동 확정된다. 애매할 때(`discouraged`)도 보내지 않는다 — 확실하지 않을 때 외부로 보내지 않는 쪽이 되돌릴 수 없는 실수를 막는다.

### 이름의 3층 분리

| 필드 | 뜻 | 예 |
|---|---|---|
| `merchant_raw` | 알림 원본. 불변 | `메가MGC커피 춘천후평점` / `000 스마트폰` |
| `brand` | 학습 단위 | `메가커피` |
| `display_name` | 사용자가 보고 싶은 이름 | `친구 대신 결제` |

---

## 11. 정산 · 자산 · 프로젝트

### 정산 (더치페이)

**원본 거래 금액을 절대 고치지 않는다.** 돌려받은 돈은 `settlements` 에 따로 쌓는다.

```
30,000원 결제 (transactions.amount = 30000, 그대로)
  ├─ settlement 10,000원 (친구 A)
  └─ settlement 10,000원 (친구 B)
→ 통계에 잡히는 금액 = 30000 - 20000 = 10,000원
```

- 계산은 SQL 의 `netAmountExpr` 이 한다. Dart 에서 다시 계산하지 않는다
- `settledAmount` / `netAmount` / `settlementStatus` 는 **계산 프로퍼티**다 (저장 컬럼이 아니다)
- 초과 입금도 허용한다 (원본은 유지)
- 취소 거래(음수)에서도 부호가 깨지지 않는다

**입금 → 정산 자동 연결**: 입금 알림은 거래로 만들지 않고 `deposits` 에 정산 후보로만 남는다. `LinkDepositToTransaction` 이 금액·시점으로 후보를 찾아 제시한다. **입금자 이름은 브랜드로 학습하지 않는다.**

### 자산

**계좌 잔액은 저장된 값이 아니라 파생값이다.**

```
현재 잔액 = accounts.balance (기준) + Σ(balance_as_of 이후 이 계좌 거래의 부호 있는 금액)
```

잔액을 직접 증감시키지 않는 이유는 **어긋난 상태를 만들 수 없게 하기 위해서**다. 저장 도중 앱이 죽거나 거래를 수정/삭제할 때 차액을 되돌리는 데 실패하면 잔액이 영구히 틀어지고 사용자는 알 방법이 없다. 파생값이면 거래를 지우면 잔액이 자동으로 되돌아온다.

| 지표 | 자산 이동 포함? |
|---|---|
| 소비 통계 | ❌ (`spendingOnly`) |
| 현금 흐름 | ✅ |
| 자산 현황 | ✅ (자산으로 쌓인다) |
| 계좌 잔액 | ✅ 나간 계좌 `-`, 받는 계좌 `+` (합계는 불변) |

**알림으로 수집된 거래는 카드 이름만 안다.** `account_id` 가 없으면 잔액에 잡히지 않으므로
`card_account_links` 로 카드를 계좌에 한 번 연결한다. 연결하는 순간 **과거 거래에 소급 적용**되고
(이미 계좌가 지정된 거래는 덮지 않는다), 이후 수집되는 거래는 `RecordPaymentNotification` 이
저장 시점에 계좌를 붙인다. 해제하면 그 연결로 붙은 거래만 되돌린다.

잔액 계산에는 **`amount`** 를 쓴다(`netAmountExpr` 아님). 카드에서 빠져나간 돈은 정산과 무관하고, 돌려받은 돈은 입금으로 따로 들어온다. net 을 쓰면 환급이 두 번 반영된다.

### 프로젝트

카테고리와 **직교하는** 묶음이다. "제주 여행" 에는 식비·교통·숙박이 섞여 들어간다.

- `transactions.project_id` (nullable)
- 프로젝트 삭제 시 거래는 `ON DELETE SET NULL` — **거래를 같이 지우지 않는다**
- 합계와 건수가 **같은 기준**(`spendingOnly`)을 쓴다. 기준이 다르면 "5건 450,000원" 인데 5건을 더해도 450,000원이 안 된다

---

## 12. InsightFacts / InsightNarrator

원칙 "숫자는 앱이, 문장만 LLM" 의 구현체다.

```
InsightFacts
├── range, total, previousTotal, transactionCount, dailyAverage
├── categories     : List<ItemFact>   // 카테고리별
├── subcategories  : List<ItemFact>   // 세부항목별
├── brands         : List<ItemFact>   // 브랜드별
└── weekdayPatterns: List<WeekdayPattern>

ItemFact       { name, parent, amount, count, previousAmount, previousCount, changeRate }
WeekdayPattern { weekday, subcategory, averageAmount, occurrences, weeksObserved }
SavingScenario { target, currentCount→reducedCount, averageAmount, 절약액 }
```

`InsightRepositoryImpl` 이 **두 기간(현재/이전)을 한 번에 집계**하고 요일 버킷을 만든다. 모두 SQL 이다.

`InsightNarrator` 는 결정론적 템플릿으로 사실을 문장으로 바꾼다. **Ollama 없이 동작한다.** 입력은 `InsightFacts` 뿐이므로 여기 없는 숫자는 문장에 나올 수 없다.

### 왜 이 구조인가

LLM 에게 "이번 달 지출 분석해줘" 라고 시키면 그럴듯한 **가짜 금액**을 만들어낸다. 가계부에서 그건 치명적이다. 사실 계산을 완전히 분리하면 LLM 이 틀릴 수 있는 범위가 **문장의 표현**으로 제한된다.

---

## 13. UI 화면

### 하단 탭 5개 (`home_shell.dart`, IndexedStack)

| 탭 | 화면 | 내용 |
|---|---|---|
| 대시보드 | `dashboard_screen` | AI 대기 배너 · 분류 필요 · 입금 연결 · 수입/지출/순증가 · 총 소비 · 상위 카테고리/브랜드 · 하이라이트 · 예정 정기결제 |
| 거래 | `transaction_list_screen` | 기간 헤더(순증가) · 날짜 바(수입/지출 분리) · 날짜 안에서 지출→수입 그룹화 |
| 통계 | `statistics_screen` | 돈이 어디로 갔나(소비/저축/청약/투자) · 수입 통계 · 카테고리 도넛 · 카테고리 트리 · 소비 추이 · 브랜드 목록 |
| 설정 > 브랜드 재정규화 | `settings_screen` | 저장된 거래의 브랜드를 지금 사전 기준으로 재계산. 미리보기 후 확인 |
| 월 선택 | `month_picker_sheet` | 연도 이동 + 12개월 그리드. 월 보기에서만 열린다 |
| 자산 | `assets_screen` | 총 자산 · 오늘/이번 주/이번 달 변화 · 종류별 계좌 묶음 · 계좌별 현재 잔액 · 카드 연결 |
| 카드 연결 | `card_link_screen` | 거래에 등장한 카드 이름 → 계좌. 연결 시 과거 거래 소급 반영 |
| 설정 | `settings_screen` | 알림 권한 · **알림 수집 앱** · 처리 현황 · 파싱 실패 보관함 · 카카오 API · **AI 분석 대기** · Ollama · 학습 · 데이터 |

### 하위 화면

```
검색 (search_screen)              — 브랜드·메모·태그 검색
분석 (insights_screen)            — 사실 기반 분석/절약 제안
프로젝트 목록/상세                 — 목표 금액, 진행률, 카테고리·브랜드 내역
카테고리 상세 / 브랜드 상세         — 드릴다운
분류 필요 큐 (review_queue_screen) — 처음 보는 브랜드 한 번에 정리
정기결제 (recurring_screen)        — 규칙 목록, 후보 등록
입금 연결 (deposit_link_screen)    — 정산 후보 매칭
직접 추가 (manual_entry_screen)    — 현금·수입 입력
```

### 시트 / 다이얼로그

```
transaction_edit_sheet   — 거래 전체 항목 수정
classify_sheet           — 분류만 빠르게
settlement_sheet         — 정산 추가/삭제
asset_transfer_sheet     — 자산 이동 표시 + 종류 선택
notification_sources_sheet — 수집 앱 토글
text_setting_dialog      — 값 하나 입력 (StatefulWidget, 컨트롤러 소유)
ingest_failures_sheet    — 파싱 실패 목록
```

### 색상 규칙

- **카테고리 색** (`CategoryColors`) — 9개 고정 hue + 예약 중립색. 색각 이상(protan/deutan/tritan) 분리도와 명도/채도 하한을 검증기로 통과한 조합. 순위가 아니라 **항목**에 색이 붙으므로 필터를 걸어도 색이 바뀌지 않는다
- **수입/지출 의미색** (`FlowColors`) — 파랑↔빨강 양극 쌍 (한국 금융 앱 관례와 일치). 라이트 CVD 최악 ΔE 21.6, 다크 19.2
- **색만으로 정보를 전달하지 않는다.** 부호(`+`/`-`)와 라벨을 항상 함께 표시한다

---

## 14. 개발 히스토리 (라운드별)

### Round 1 — 기반 구축

**요구**: 알림 수집 → 파싱 → 브랜드 DB 조회 → LLM(미등록 브랜드만) → 로컬 저장 → 통계.

- 추가: Clean Architecture 골격, feature-first 구조, `db_schema.dart` 단일 소스
- 추가: NotificationListenerService + MethodChannel/EventChannel
- 추가: 결제 알림 파서, 브랜드 시드, Ollama 연동, 기본 통계
- DB: **v1** (`merchants`, `brand_rules`, `transactions`, `settings`, `ingest_failures`)
- 설계: sqflite 선택(build_runner 코드 생성 회피), Entity/DTO 분리, Repository 패턴

### Round 2 — 통계·분석 확장

**요구**: 카테고리/브랜드 분석, 대시보드, 기간 필터, **"LLM 은 초기 버전에서 필수가 아니다"**, "기타 대신 미분류".

- 추가: 브랜드/카테고리 상세 화면, 대시보드, 브랜드 검색
- 추가: 기간 필터(오늘/이번 주/이번 달/올해/사용자 지정)
- 변경: LLM 기본값을 **꺼짐**으로. 미등록 브랜드는 사용자가 1회 선택 → 이후 자동
- 변경: 미분류 상태 이름을 `미분류` 로 통일
- DB: **v2** (`needs_review` + 인덱스)

### Round 3 — 계좌이체 처리

**요구**: `000 스마트폰 → 메가커피` 문제. 이체 거래명은 상대방이므로 브랜드를 학습하면 안 된다.

- 추가: `BrandLearningPolicy` — 학습 허용 판단의 **유일한 지점**
- 추가: raw_name / display_name / brand / type 역할 분리
- 추가: 이체 거래에서 학습 토글 **비활성화 + 이유 표시**
- 추가: 메모/태그
- DB: **v3** (`display_name`, `tag`)

### Round 4 — 더치페이 정산

**요구**: 원본 거래 금액을 절대 수정하지 않고 정산을 표현.

- 추가: `settlements` 테이블, `ManageSettlements`
- 추가: `netAmountExpr` — 통계는 실제 부담 금액을 쓴다
- 추가: 입금 알림을 `deposits` 에 정산 후보로 저장 + 자동 연결
- 원칙: 이체는 브랜드를 학습하지 않지만 **정산 후보로는 쓸 수 있다**
- DB: **v4** (`settlements`, `deposits` + 인덱스 3개)

### Round 5 — 정기결제 · 자산 이동

**요구**: 정기결제 자동 감지, 적금을 소비 통계에서 제외.

- 추가: `recurring_rules` + `RecurringDetector` (같은 브랜드 + 유사 금액 + 규칙적 주기)
- 추가: `asset_transfers` + `is_asset_transfer` 플래그
- 추가: `spendingOnly` 공통 조건 (자산 이동 제외)
- 원칙: **거래 타입을 늘리지 않는다.** Transaction 위에 메타데이터를 얹는다
- DB: **v5**

### Round 6 — 카테고리 체계 개편 → **취소**

사용자가 진행 직후 취소를 요청했다. git 이 없어 **110 파일 / 18,584 줄을 손으로 되돌리고** 원상태와 일치하는지 확인했다.

> 이 라운드가 "git 을 쓰지 않는 것의 비용" 을 보여준다. 이번 Round 12 에서 git 을 도입한 이유다.

### Round 7 — AI 재무비서 로드맵

13개 기능 로드맵 중 **1~3 + 사실 계산 레이어**를 선택. 방식은 **"숫자는 앱이, 문장만 LLM"**.

- 추가: 직접 입력(`AddManualTransaction`), 프로젝트, 자산 계좌
- 추가: `InsightFacts` / `InsightRepositoryImpl` / `InsightNarrator`
- DB: **v6** (`projects`, `accounts`, `account_snapshots` + `entry_source`, `direction`, `account`, `project_id`)

### Round 8 — 빌드 실패 수정

**보고**: `Transaction` 이 도메인 엔티티와 sqflite 양쪽에서 import 되어 빌드 실패.

- 수정: `import 'package:sqflite/sqflite.dart' hide Transaction;`
- 전수 조사: 정확히 `recurring_repository_impl.dart`, `project_repository_impl.dart` 두 파일. sqflite 의 `Transaction` 타입을 쓰는 코드는 없었다(전부 `DatabaseExecutor`)

### Round 9 — 빌드 가능한 상태 우선

**요구**: "문서보다 빌드 가능한 상태를 우선한다." analyze → test → 실기기 실행 순.

- 수정: `flutter analyze` 오류 1건(`MyApp` 참조하는 카운터 템플릿 테스트) 삭제
- 수정: info 24건 → `dart fix --apply` 로 19건, `use_build_context_synchronously` 2건은 수동 (`if (!mounted) return;` — 실제 버그)
- 추가: `database_smoke_test.dart` — `sqflite_common_ffi` 로 데스크톱에서 실제 SQLite 검증
- 결과: analyze 무경고, 177개 테스트 통과, debug APK 빌드 성공

### Round 10 — 스마트 브랜드 분류 + 알림 수집 관리

**요구**: (1) 어느 금융 앱을 수집할지 선택 (2) 장소 API 로 브랜드 업종 자동 조회. **"절대로 사용자에게 비용이 발생하면 안 된다."**

- 추가: `NotificationSourceStore.kt` + `notification_sources` 테이블 + 설정 UI
- 추가: `LookupBrandIndustry` + `PlaceApiDataSource` + `PlaceCategoryMapper` + `brand_metadata`
- 추가: 비용 안전장치 전부 (사용자 키, 브랜드당 1회, 실패 캐시, 429 24시간 중단)
- **스펙에 없던 안전장치**: 이체/사람 이름을 외부 API 로 보내지 않는 정책 게이트
- DB: **v7**
- 결과: analyze 무경고, 221개 테스트 통과

### Round 11 — 실사용 피드백 반영

실기기에서 발견된 문제들.

**Priority 1**
- 🐛 **수입/지출 합산 버그**: 수입 300,000 + 지출 15,000 이 315,000 으로 표시. 원인은 `cashOutflowInRange` 에 `direction` 필터가 없었던 것. `expenseOnly`/`incomeOnly` 공통 조각을 만들어 한 번에 고쳤다
- 추가: 대시보드에 수입 / 지출 / **순증가** 3값 분리 표시
- 추가: **거래 → 계좌 잔액 자동 반영** (기준 잔액 + 거래 합 파생 방식)
- 추가: 거래 전체 항목 수정 (날짜/시간/금액/수입지출/분류/브랜드/프로젝트/계좌/메모)

**Priority 2**
- 추가: 수입/지출 막대 분리, 자산 화면 기간별 변화
- 추가: 소비/저축/청약/투자 4분할 (`asset_kind`)
- 추가: 수입 전용 분류 체계(급여/용돈/장학금/부수입) + 월별 추이

**Priority 3**
- 검증: `NotificationSourceStore` 는 정상 연결되어 있었다. 중복의 진짜 원인은 지문의 카드명·분 단위 절삭
- 추가: 근접 중복 차단 (금액·브랜드·수단 동일 + ±30초, **저장 단계에서**)

- DB: **v8**
- 결과: analyze 무경고, 288개 테스트 통과

### Round 11-후속 — 수입 오염 경로 전수 감사

"1번 잘 작동하는지 확인" 요청으로 전체 집계를 감사해 **4곳을 더 찾았다.**

1. 🐛 **정기결제 감지** — 월급이 "회사 2,000,000원 매달 결제 예정" 으로 잡힐 수 있었다. 월급은 이 앱에서 가장 규칙적인 데이터다
2. 🐛 **정기결제 소급 연결** — 수입을 정기"결제" 규칙에 묶을 수 있었다
3. 🐛 **정산 후보** — 월급·용돈이 입금 정산 후보로 떴다. 붙이면 net 이 깎여 통계가 틀어진다
4. 🐛 **프로젝트 건수** — 합계는 소비 기준인데 건수는 전체를 세어 기준이 어긋났다

대조군 테스트를 함께 넣었다 (넷플릭스 구독은 여전히 감지되는지, 지출은 정산 후보로 뜨는지).

### Round 11-후속2 — 거래 화면 Dart 합산 + 실기기 레이아웃

- 🐛 **거래 페이지 합산**: SQL 은 고쳤지만 `periodTotal` 이 Dart 에서 방향 구분 없이 `fold` 하고 있었다. 날짜별 소계도 동일
- 🐛 **날짜 바 부호 누락**: 지출이 양수로 저장되므로 `signedWon` 이 부호를 안 붙여 `+300,000원  15,000원` 으로 구분 불가
- 🐛 **대시보드 레이아웃 크래시** (실기기): `_TopRow` 의 `Row(crossAxisAlignment: stretch)` 가 스크롤 안에서 non-flex 자식에게 tight 무한 높이를 넘겨 `BoxConstraints forces an infinite height`. `IntrinsicHeight` 로 수정
- 결과: 316개 테스트 통과

### Round 11-후속3 — 설정 입력 크래시

**보고**: Ollama 주소 / 카카오 키 입력 시 `'_dependents.isEmpty': is not true` 크래시. Ollama·카카오 무관 → 공통 경로.

- 🐛 원인: `text_setting_dialog.dart` 의 `showDialog(...).whenComplete(controller.dispose)`. Future 는 pop 즉시 완료되지만 위젯 트리는 퇴장 애니메이션 동안 살아 있다
- 수정: 컨트롤러를 **위젯이 소유**하도록 `StatefulWidget` 전환
- 🐛 추가 발견: `SettingsController` 가 네트워크 await 후 `finally` 에서 `notifyListeners()` → dispose 후 호출 가능. `_notify()` 가드 추가
- 결과: 321개 테스트 통과

### Round 12 — UI 그룹화 + AI 일괄 처리

**요구**: (1) 같은 날짜 안에서 지출/수입 그룹화 (2) AI Pending Queue 로 오프라인 일괄 처리.

- 추가: `DaySection` — 날짜 안에서 지출 → 수입 순 그룹화, `지출`/`수입` 구분 라벨
- 추가: 금액 부호+색 (지출 빨강 / 수입 파랑 / 자산이동 중립)
- **제거: 실시간 LLM 호출.** `RecordPaymentNotification` 에서 `classifier`/`classifyMerchant` 의존성 자체를 걷어냈다 — 이제 수집 경로에 LLM 이 구조적으로 닿을 수 없다
- 추가: `ProcessAiPendingQueue` — 브랜드별 묶기, 캐시 우선, 브랜드당 LLM 1회
- 추가: `AiQueueController` + `AiQueueBanner` — `AI 분석 대기 N건 [지금 분석]`
- 추가: 앱 시작 시 비차단 대기열 확인
- DB: **v9** (`ai_status`, `ai_processed_at` + 인덱스 + 기존 미분류 편입)
- 결과: analyze 무경고, **340개 테스트 통과**, 실기기 v8→v9 마이그레이션 확인

---

## 15. 버그 수정 이력

| # | 버그 | 원인 | 라운드 |
|---|---|---|---|
| 1 | **`Transaction` import 충돌** — 빌드 실패 | sqflite 도 `Transaction` 을 export | R8 |
| 2 | `flutter analyze` 오류 1건 | 카운터 템플릿 테스트가 없는 `MyApp` 참조 | R9 |
| 3 | `use_build_context_synchronously` 2건 | await 뒤 context 사용 (실제 버그) | R9 |
| 4 | **`송금`/`입금` 키워드 누락** | 네이티브 필터에 없어 송금·입금이 조용히 사라졌다 | R1~ |
| 5 | `_resolveMethod` 순서 오류 | easyPay 를 이체보다 먼저 검사해 `카카오페이 송금 홍길동` 이 가맹점 결제로 | R1~ |
| 6 | 파서 stopword 과다 | 가맹점 이름이 잘려나갔다 | R1~ |
| 7 | `stripBranchSuffix` 무동작 | 정규식이 아무것도 잡지 않았다 | R1~ |
| 8 | `_sep` 제어문자 빈 문자열 | 구분자가 사라져 필드가 붙었다 | R1~ |
| 9 | `showDateRangePicker` assert | 진행 중인 달의 lastDay 가 미래 | R2~ |
| 10 | 팔레트 CVD 검증 실패 | 주거/통신 vs 교통 ΔE 0.7 (deutan) | R2~ |
| 11 | 추이 차트 라벨 슬롯 | 일부 막대에만 있어 높이가 안 맞았다 | R2~ |
| 12 | `clamp()` 반환형 | 정적 타입이 `num` 이라 `double` 자리에 못 들어간다 | R9 |
| 13 | Kotlin `'packages'` | 단일 인용부호는 Char 리터럴 | R10 |
| 14 | Python heredoc `$` 이스케이프 | Dart 문자열 보간이 깨져 SQL 이 무효가 됐다 | R10 |
| 15 | **수입/지출 합산 (315,000원)** | `cashOutflowInRange` 에 `direction` 필터 없음 | R11 |
| 16 | **월급이 정기결제 후보로** | `RecurringDetector` 가 수입을 걸러내지 않았다 | R11 |
| 17 | 정기결제 소급 연결이 수입을 포함 | `backfillTransactions` 에 방향 조건 없음 | R11 |
| 18 | **수입이 정산 후보로** | `findSettlementCandidates` 에 `amount > 0` 만 있었다 | R11 |
| 19 | 프로젝트 건수/합계 기준 불일치 | `cnt` 에 `spendingOnly` 미적용 | R11 |
| 20 | **거래 페이지 Dart 합산** | `periodTotal` 이 방향 구분 없이 `fold` | R11 |
| 21 | 날짜 바 부호 누락 | 지출이 양수 저장이라 `signedWon` 이 부호를 안 붙임 | R11 |
| 22 | **`BoxConstraints forces an infinite height`** | `Row(stretch)` + 스크롤 안 non-flex 자식 | R11 |
| 23 | **`'_dependents.isEmpty': is not true`** | `whenComplete(controller.dispose)` 가 퇴장 애니메이션 중 dispose | R11 |
| 24 | dispose 후 `notifyListeners` | 네트워크 await 후 `finally` | R11 |
| 25 | 앱 간 중복 저장 | 지문에 카드명 포함 + 분 단위 절삭 | R11 |
| 26 | 위젯 테스트 10분 정지 | `testWidgets` 의 FakeAsync 존에서 실제 SQLite I/O await | R11 |

### 조작 실수 (기록)

| 실수 | 결과 | 대응 |
|---|---|---|
| `flutter install` 이 release APK 를 찾다 실패하며 **기존 앱을 먼저 삭제** | 기기의 거래 데이터 손실 | 이후 `adb install -r` 로 데이터 유지 설치 |
| `_TopRow` 추출 시 클래스 순서를 잘못 가정 | `_Message` 클래스가 중복 생성되어 파일 손상 | 즉시 복구 + analyze 확인 |
| 좌표를 모른 채 기기 UI 자동 조작 | 직접 추가 화면에 오타 입력, 홈 화면 스크린샷 촬영 | 캡처 파일 삭제, 기기 자동 조작 중단 |

---

## 16. 테스트

```powershell
flutter analyze     # 무경고 상태를 유지한다
flutter test        # 340개 통과
flutter test test/database_smoke_test.dart   # 특정 파일
```

### 테스트 파일 (21개 / 약 6,200줄)

| 파일 | 검증 대상 | 종류 |
|---|---|---|
| `payment_notification_parser_test.dart` | 카드사별 알림 문구 파싱 | 단위 |
| `database_smoke_test.dart` | **실제 SQLite 로 스키마 + 집계 SQL** | SQLite |
| `brand_learning_policy_test.dart` | 이체/사람이름 학습 차단 | 단위 |
| `settlement_test.dart` | 정산 net 계산, 원본 불변 | 단위 |
| `recurring_detector_test.dart` | 주기 판정, 월말 날짜 보정 | 단위 |
| `insight_facts_test.dart` | 사실 계산 | 단위 |
| `classification_dto_test.dart` | LLM 응답 검증/보정 | 단위 |
| `core_utils_test.dart` | 정규화, 포맷 | 단위 |
| `date_range_test.dart` | 기간 계산 | 단위 |
| `brand_industry_lookup_test.dart` | 업종 조회 캐시·429·매핑 | 단위 + Mock HTTP |
| `notification_sources_storage_test.dart` | 수집 앱 저장, **v7/v8 마이그레이션** | SQLite + Migration |
| `ingest_place_lookup_test.dart` | **분류 사슬 + API 호출 횟수 + 개인정보 유출** | 통합 |
| `income_expense_split_test.dart` | **수입/지출/순증가 분리** (315,000원 버그) | SQLite |
| `account_balance_test.dart` | 거래 → 잔액 반영, 멱등성, 기준 시각 | SQLite |
| `transaction_edit_test.dart` | 거래 수정 + 원본/지문 불변 | Repository |
| `flow_breakdown_test.dart` | 소비/저축/청약/투자, 수입 통계 | Repository |
| `duplicate_transaction_test.dart` | 앱 간 근접 중복 차단 | Repository |
| `transaction_list_totals_test.dart` | 기간 합계, 그룹화, 화면 문구 | Controller + Widget |
| `round11_widget_layout_test.dart` | **스크롤 안 레이아웃 크래시** | Widget |
| `text_setting_dialog_test.dart` | **다이얼로그 컨트롤러 수명** | Widget |
| `ai_pending_queue_test.dart` | **브랜드당 LLM 1회**, 상태 전이, 정책 | 통합 |

### 이 프로젝트에서 중요한 테스트 방식

**1. 집계 SQL 은 실제 SQLite 로 돌린다**

손으로 쓴 SQL 문자열이 많고 위젯 테스트로는 닿지 않는다.

```dart
sqfliteFfiInit();
databaseFactory = databaseFactoryFfi;
```

**2. 외부 API 는 호출 횟수를 센다**

"동작한다" 만으로는 할당량 낭비를 잡을 수 없다.

```dart
expect(apiCallCount, 1, reason: '브랜드당 최대 1회여야 한다');
```

**3. 개인정보 유출은 보낸 쿼리를 기록해 검증한다**

```dart
expect(sentQueries, isEmpty);  // 사람 이름을 장소 검색에 보내면 안 된다
```

**4. 대조군을 함께 둔다**

"월급은 정기결제 후보가 아니다" 가 감지기가 아무것도 못 찾아서 통과하는 게 아님을 확인하려면, 같은 조건의 넷플릭스 구독이 **정상 감지되는지** 함께 검사해야 한다.

**5. 버그 수정 테스트는 수정을 되돌려 실패를 확인한다**

`IntrinsicHeight` 를 임시로 빼고 테스트가 실패하는 것을 본 뒤 복구했다. 통과하는 테스트가 실제로 그 버그를 잡는지 확인하는 유일한 방법이다.

**6. 위젯 테스트에서 DB 는 `runAsync` 안에서**

`testWidgets` 는 FakeAsync 존에서 돌기 때문에 실제 SQLite I/O 를 그냥 `await` 하면 완료 통보가 오지 않아 **10분 타임아웃까지 멈춘다.**

```dart
await tester.runAsync(() async {
  await insert(...);
  await controller.load();
});
```

**7. `pumpAndSettle` 로 퇴장 애니메이션을 끝까지 돌린다**

pop 직후만 확인하면 다이얼로그 teardown 버그를 놓친다.

### 실기기 테스트

| 항목 | 결과 |
|---|---|
| 기기 | Galaxy S24+ (SM-S926N), Android 16 (API 36) |
| 설치 | `adb install -r` (데이터 유지) |
| 마이그레이션 | v8 → v9 정상 적용 확인 (로그) |
| 시작 로그 | `의존성 초기화 완료`, `알림 수집 시작`, 예외 0건 |
| 거래 화면 | 헤더 `순 +270,000원`, 날짜 바 `+300,000원 -30,000원` 확인 |

**아직 실기기에서 확인하지 않은 것**: Ollama 일괄 분석 실제 동작(노트북에서 Ollama 실행 필요), 카카오 API 실호출, 실제 카드 결제 알림 수집.

---

## 17. 개발 철학

### 1. 계산 가능한 값은 저장하지 않는다

계좌 잔액, 실제 부담 금액, 순증가는 모두 파생값이다. 저장하면 **어긋난 상태**가 만들어질 수 있고 사용자는 그것을 알 수 없다. 파생값이면 거래를 지우면 잔액이 자동으로 되돌아온다.

### 2. AI 는 필수가 아니다

기본값은 꺼짐이다. 꺼져 있어도 모든 결제가 정상 기록되고, 처음 보는 브랜드만 사용자가 **한 번** 고른다. AI 는 그 한 번의 선택을 대신하는 편의 기능일 뿐이다.

### 3. 개인정보를 외부로 보내지 않는다

- 모든 데이터는 로컬 SQLite. 서버 없음, 동기화 없음, 분석 도구 없음
- LLM 은 사용자가 지정한 로컬 Ollama 로만
- 장소 API 로는 **브랜드 이름만**. 금액·카드·날짜는 보내지 않는다
- **이체/송금 거래명(상대방 이름)은 어떤 외부 요청에도 넣지 않는다**

### 4. 사용자 수정이 AI 보다 우선이다

`classification_source = 'user'` 인 거래는 AI 결과로 덮지 않는다. `brand_metadata.user_modified = 1` 은 자동 조회가 덮지 못한다. 사용자가 고친 것을 기계가 되돌리면 신뢰가 끝난다.

### 5. 비용이 발생하지 않는 구조를 기본으로 한다

사용자가 명시한 가장 강한 제약이다.

- 무료 할당량 안에서만. 카드 등록이 필요한 서비스는 쓰지 않는다
- API 키는 **사용자 본인 키**. 앱에 개발자 키를 심지 않는다
- 한도 초과를 받으면 **자동으로 멈춘다**
- API 없이도 앱은 정상 동작해야 한다

### 6. AI 는 저장을 방해하지 않는다

결제 순간에는 AI 를 부르지 않는다. 저장을 먼저 끝내고 AI 는 나중에 몰아서 한다. 분석 중에도 UI 는 그대로 쓸 수 있다.

### 7. 항상 사람이 수정 가능해야 한다

자동 분류가 틀릴 수 있다는 전제로 만들었다. 모든 자동 분류는 수정 가능하고, 수정은 학습된다. `needs_review` 는 "AI 가 실패함" 이 아니라 **"사용자에게 한 번 물어볼 것"** 이라는 정상 상태다.

### 8. 원본은 절대 수정하지 않는다

`merchant_raw`(알림 원본 거래명), `raw_notification`(알림 전문), `amount`(결제 금액), `fingerprint`(중복 방지 키)는 사용자 수정으로도 바뀌지 않는다. 카드 명세서와 대조할 수 있어야 하고, 정산을 취소하면 원래 상태로 정확히 돌아가야 한다.

### 9. 거래 타입을 늘리지 않는다

"적금 거래", "정산 거래" 같은 새 타입을 만들지 않는다. `Transaction` 은 하나이고 플래그와 별도 테이블로 표현한다. 타입이 늘면 모든 집계 쿼리가 분기되고 하나를 빼먹는 순간 통계가 틀린다.

### 10. 통계는 공통 SQL 조각을 재사용한다

`spendingOnly`, `netAmountExpr`, `expenseOnly` 를 각 화면이 다시 쓰지 않는다. 화면마다 다른 값이 나오는 버그의 유일한 예방책이다. (실제로 이걸 어긴 곳에서 315,000원 버그가 나왔다)

### 11. 중복은 저장 단계에서 막는다

저장해 두고 화면에서만 걸러내면 모든 집계가 두 배가 되고, 골라내는 일이 사용자 몫이 된다.

### 12. 색만으로 정보를 전달하지 않는다

색각 이상 사용자를 위해 부호(`+`/`-`), 아이콘, 라벨을 항상 함께 표시한다. 팔레트는 검증기로 CVD 분리도를 확인한 조합만 쓴다.

---

## 18. 실행 방법

### 전제

- Flutter 3.44.8+ / Dart 3.12.2+
- Android SDK 36, JDK (Gradle Kotlin DSL, Gradle 9.1)
- **Android 실기기 또는 에뮬레이터** (데스크톱·웹은 불가 — 알림 리스너가 Android 전용)

### 빌드 · 실행

```powershell
flutter pub get
flutter devices                 # Android 기기가 보이는지 확인
flutter run                     # 디버그 실행
flutter build apk --debug
flutter build apk --release
```

플랫폼 폴더가 비어 있거나 깨졌을 때:

```powershell
./tools/bootstrap.ps1           # 임시 flutter create 에서 없는 파일만 복사(기존 파일 보존)
```

### 기기에 다시 설치할 때 (중요)

```powershell
# ✅ 데이터를 유지한다
adb install -r build/app/outputs/flutter-apk/app-debug.apk

# ❌ flutter install 은 기존 앱을 먼저 삭제한다 → DB 가 사라진다
```

### 앱 최초 설정

1. **설정 → 알림 접근 권한** — 시스템 설정에서 허용 (없으면 아무것도 수집되지 않는다)
2. **설정 → 알림 수집 앱** — 카드/은행 앱에서 알림이 한 번 오면 목록에 나타난다. 수집할 앱만 켠다
3. (선택) **설정 → 카카오 REST API 키** — `developers.kakao.com` 에서 무료 발급 → "키 확인"
4. (선택) **설정 → AI 자동 분류** — 아래 참고

### Ollama 연결

노트북에서:

```bash
# 외부 접속을 허용해서 띄운다(실기기에서 접속하려면 필요)
# Windows PowerShell
$env:OLLAMA_HOST="0.0.0.0:11434"; ollama serve

# 모델 설치
ollama pull gemma3:4b
```

앱에서:

1. 설정 → **Ollama 주소** → `http://<노트북 LAN IP>:11434`
2. 설정 → **모델** → `gemma3:4b`
3. 설정 → **연결 테스트** → 서버·모델 확인
4. 설정 → **AI 자동 분류 사용** 켜기
5. 대시보드에 `AI 분석 대기 N건 [지금 분석]` 배너가 나타난다

> 방화벽에서 11434 포트 인바운드를 허용해야 할 수 있다. 노트북과 폰이 같은 Wi-Fi 에 있어야 한다.

---

## 19. 앞으로 구현 예정

### 곧 할 만한 것

| 기능 | 비고 |
|---|---|
| **예산 설정 / 초과 알림** | 카테고리별 월 예산, 초과 예측 |
| **자산 이동 받는 계좌 연결** | 지금은 총자산만 정확하고 적금 계좌 잔액은 손으로 갱신해야 한다 |
| 입금 근접 중복 검사 | 거래에는 있고 `deposits` 에는 없다 |
| 카드사별 전용 파서 | `notification_sources` 에 파서 지정 필드를 붙일 자리를 남겨 뒀다 |
| 백업 / 복원 | DB 파일 내보내기·가져오기. 앱 삭제로 데이터를 잃는 일을 막는다 |

### 로드맵 (Round 7 의 13개 중 미착수)

- 소비 습관 분석
- What-if 시뮬레이션 ("배달을 절반으로 줄이면?")
- 잔액 예측
- 채팅 재무 코치
- 예산 초과 예측
- 소비 점수
- 목표 기반 AI
- 재무 건강 리포트

**모두 `InsightFacts` 위에 얹는다.** 새 기능이 직접 SQL 을 쓰기 시작하면 숫자가 갈라진다.

### 그 외 아이디어

- OCR 영수증 입력
- 지도 기반 소비 분석
- Sankey Diagram (돈의 흐름 시각화)
- 홈 화면 위젯
- 반복 결제 관리 강화 (구독 해지 리마인더)
- 다중 통화

---

## 20. 현재 알려진 한계

| # | 한계 | 영향 | 비고 |
|---|---|---|---|
| 1 | **Ollama 일괄 분석 실기기 미검증** | 코드·테스트는 통과했지만 실제 Ollama 로는 아직 안 돌렸다 | 노트북에서 Ollama 실행 필요 |
| 2 | 카카오 API 실호출 미검증 | Mock 으로만 테스트 | 사용자 키 필요 |
| 3 | 실제 카드 알림 수집 미검증 | 파서는 단위 테스트만 | 실제 결제 발생 필요 |
| 4 | 자산 이동의 **받는 계좌**는 잔액이 늘지 않는다 | 적금 계좌 잔액을 손으로 갱신해야 한다 | 총자산은 정확(양쪽 모두 0 처리) |
| 5 | 중복 판정은 **브랜드가 같을 때만** | 두 앱이 가맹점명을 다르게 주면 2건 남을 수 있다 | 요구사항이 정한 기준 |
| 6 | 입금(`deposits`)은 근접 중복 검사 없음 | 분 경계에서 같은 입금이 2건 될 수 있다 | 지문이 분 단위라 대부분 걸러진다 |
| 7 | 데스크톱·웹 실행 불가 | 알림 리스너가 Android 전용 | 테스트는 `sqflite_common_ffi` 로 대체 |
| 8 | 파서는 국내 주요 문구 기준 | 새 문구는 `ingest_failures` 에 쌓인다 | 보관함을 보고 규칙 추가 |
| 9 | 이체 거래는 자동 분류가 원리적으로 불가 | 매번 사용자가 지정 | 의도된 동작 |
| 10 | 백업 기능 없음 | 앱을 삭제하면 데이터가 사라진다 | 우선순위 높은 후속 작업 |

---

## 21. 다음 작업자가 반드시 알아야 하는 것

### 절대 어기면 안 되는 제약 (사용자 원문)

> "가장 중요한 원칙은 사용자에게 비용이 발생하지 않는 것이다."
> "절대로 사용자에게 비용이 발생하면 안 된다."
> "개인정보를 외부 서버로 보내지 않는 로컬 중심 구조"
> "원본 거래는 절대 수정하지 않는다."
> "계좌이체는 브랜드를 절대 학습하지 않는다. 하지만 Settlement 후보로는 사용할 수 있다."
> "기타 대신 미분류"
> "초기 버전에서는 LLM을 필수 요소로 사용하지 않는다."
> "숫자는 앱이, 문장만 LLM"
> "Transaction은 원본 거래를 나타낸다. Settlement, Deposit, Recurring, AssetTransfer는 Transaction을 보완하는 독립 기능으로 관리한다."
> "AI는 UI를 막지 않는다."
> "실패한 거래는 재시도 가능해야 한다."
> "동일 브랜드는 AI를 반복 호출하지 않는다."

### 작업 규칙

1. **집계를 만들 때 `db_schema.dart` 를 먼저 읽는다.** 공통 SQL 조각이 이미 있다
2. **스키마를 바꾸면 `databaseVersion` 을 올리고 `migrations` 에 추가한다.** `IF NOT EXISTS` / `ADD COLUMN` 형태로 **두 번 실행해도 안전하게**
3. **네이티브를 건드리면 `flutter build apk --debug` 로 Kotlin 컴파일을 확인한다.** `flutter test` 는 Kotlin 을 컴파일하지 않는다
4. **끝내고 `flutter analyze` + `flutter test` 를 돌린다.** 새 기능에는 테스트를 함께 만든다
5. **버그를 고쳤으면 수정을 되돌려 테스트가 실패하는지 확인한다**
6. **기기에 설치할 때 `adb install -r` 를 쓴다.** `flutter install` 은 데이터를 지운다
7. **스펙에 없어도 위험이 보이면 막고 이유를 설명한다.** Round 10 에서 스펙대로면 이체 상대방 이름이 카카오로 전송됐다
8. 사용자는 한국어로 스펙 문서를 준다. 응답도 한국어로

### 자주 헷갈리는 지점

- **소비 ≠ 현금 흐름.** 적금 납입은 소비가 아니지만 통장에서는 나간다. `spendingOnly` 를 붙일 곳과 안 붙일 곳을 구분한다
- **`amount` ≠ 통계 금액.** 통계는 `netAmountExpr`(정산 차감 후). **잔액은 `amount`** (정산 환급이 두 번 반영되면 안 된다)
- **수입은 양수 + `direction`.** 방향 조건을 빼면 지출에 더해진다
- **`accounts.balance` 는 현재 잔액이 아니라 기준 잔액.** 화면에는 `Account.currentBalance`
- **수입과 지출은 분류 체계가 다르다** (`tree` vs `incomeTree`). `categoriesFor` / `coerceFor` 를 쓴다
- **`merchant_raw` ≠ `brand` ≠ `display_name`**
- **네이티브 키워드 필터가 Dart 파서보다 넓어야 한다**
- **`found = false` 인 `brand_metadata` 도 캐시 히트다.** 재조회하면 할당량이 녹는다
- **`aiPendingOnly` 는 `processing` 을 포함하지 않는다.** 포함하면 같은 브랜드를 두 번 호출한다
- **`needs_review`** 는 정상 상태다. 실패가 아니다
