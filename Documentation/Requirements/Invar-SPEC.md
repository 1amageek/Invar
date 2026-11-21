# Invar — 統合バグ探索・検証ツール 実装仕様書

**仕様バージョン：0.2（Invar名称確定版）**  
**作成日：2026-11-16**  
**改訂日：2026-11-17**  
**状態：実装Agent向け要求仕様。実装・実行試験は未実施。**  
**製品名・リポジトリ名・Swift Package名：Invar（確定）**  
**CLI：`invar`（確定）**

> ArchitectureExplorerとswift-formalを依存に持ち、構造解析、ルール検査、モデル検査、証明、テスト、Fuzzingを統合する。プロジェクト全体から根拠付きの調査候補を見つけ、指定された性質と予算の範囲で検証し、再現可能な証跡を残す。
>
> **探索・優先順位・検証計画・再検証・総合判定は本パッケージが所有する。ArchitectureExplorerは構造探索と拡張表示、swift-formalは対応する実行意味の形式化と検証を所有する。**

## 0. 資料と要求の扱い

本書は、既存のArchitectureExplorer-SPEC.md v1.0と、同梱のArchitectureExplorer-EXTENSIONS-SPEC.md v1.2（Extension API 1.0）を基礎にする。ArchitectureExplorerに検証エンジンを戻す仕様ではない。

ユーザーが提示した「プロジェクト全体の構造と振る舞いを理解し、潜在的なバグを継続探索する」という目的を採用する。ただし、その説明中の「ArchitectureExplorerが優先度を付け検証を回す」という責務配置は、直前に合意したパッケージ分離に従いInvarへ置き換える。この置き換えは意図的な設計変更である。

本書のMUST／禁止は要求、SHOULDはADRで理由を説明した変更を許す指針。仕様・上流の公開機能・実装済み・試験済みを分ける。製品名はInvar、CLIはinvarに確定した。本改訂は名称と文書間参照の統一であり、責務、検証範囲、データ契約、拡張APIの意味は変更しない。

### 0.1 確定した命名契約

| 対象 | 正式名称 |
|---|---|
| 製品名・リポジトリ名 | `Invar` |
| Swift Packageの`name` | `Invar` |
| executable product・target・実行コマンド | `invar` |
| executableのソースディレクトリ | `Sources/invar/` |
| 本仕様書 | `Invar-SPEC.md` |
| 実装Agent向け引き継ぎ | `Invar-AGENT-HANDOFF.md` |
| 統合検証の受け入れ試験ID | `INV-001`〜`INV-048` |

`Package.swift`、README、CLI help、診断中の実行例、ドキュメント、テストの呼び出し名を上記へ統一する。旧CLI名の互換エイリアスは初期実装の要件に含めない。

`VerificationCore`等のライブラリモジュール名、`VerificationUnit`等のモデル名、`verification.json`、`verification-policy.json`、`verification-run/`は役割・データ用途を表す既存名称として維持する。製品名の変更を理由に、これらの契約を無断で変更しない。

Explorerの拡張APIは汎用のままとし、Invar専用の依存・分岐を追加しない。Invarは同APIを利用する一つの外部Providerである。

本版は旧版を置き換える現行仕様。既存48項目の試験は接頭辞だけを変更し、番号・合格条件を一対一で保持する。変更履歴は同梱の`CHANGELOG.md`に記載する。上流実装に関する§4・§25の記述は、2026-11-16に確認した内容を保持しており、本改訂で最新状態を再調査したものではない。

## 1. 目的・非目的

### 1.1 目的

- プロジェクト全体と複数モジュールの関係から、検証対象と根拠を列挙する。
- 異なる手法を共通の入力世代・契約・証跡モデルで運用する。
- 静的な疑い、モデル上の反例、実コードでの再現、証明を区別する。
- 編集に追従し、影響がある検証だけを保守的に再実行する。
- 人間はExplorerの拡張GUI、AgentはCLI／MCPから同じ結果を調べる。
- 処理した範囲、未処理、未対応、予算超過、前提を一覧できる。

### 1.2 非目的

全バグの不存在を無条件に保証すること、任意言語の任意コードを自動証明すること、AIの意味推測で形式モデルを補完すること、ツールの多数決で正しさを決めること、未対応範囲を黙って検証済みにすること、ソースの自動修正・自動deployを行うこと。

循環依存や未使用らしいコードを、常にバグとして扱わない。設計ルールや到達可能性の根拠に応じて、設計違反・保守性の指摘・調査候補を分ける。

## 2. 依存方向

```text
Invar
    ├── ArchitectureExplorer（headless library products）
    │       └── source / project / graph / events / extension contract
    ├── swift-formal（public library products）
    │       └── FormalCore / FormalIR / FormalCompiler / FormalValidation
    ├── Static Rule Backend
    ├── Native Test Backend
    └── Fuzz Backend

ArchitectureExplorer Web helper ──→ swift-web

禁止：ArchitectureExplorer → Invar / swift-formal
禁止：swift-formal → Invar / ArchitectureExplorer
```

Invarは両パッケージを必須のbuild依存とする。TLC／Lean／Fuzzerのruntimeが導入されていなくても、計画・静的調査・既存結果閲覧は動く。必要runtime不在のジョブは未実行と報告し、自動downloadで補わない。

公開APIを使い、CLI内部の実装やパーサ・証明runtimeを複製しない。必要なAPIが未公開なら、その所有パッケージに最小の公開契約を追加する。CLIを利用する互換Backendは版付きJSONと明示的なprocess契約を使い、人間向けログをスクレイピングしない。

## 3. 各パッケージの責務

| 所有者 | 所有する責務 | 所有しない責務 |
|---|---|---|
| ArchitectureExplorer | 構造索引、Query、差分、入力識別、汎用拡張表示 | 検証優先順位、再検証、総合合否 |
| swift-formal | 対応入力の変換、IR、TLA+／Lean成果物、検証結果 | 全プロジェクトのwatch・GUI・複数検証器統括 |
| Invar | 探索、Obligation、切り出し、Scheduler、結果統合、再現、CI | 下位解析器・形式化エンジンの重複実装 |
| Backend | 自身の対応範囲、実行・結果・依存情報 | 他Backendの結論の書き換え |

Invarはプロジェクト全体の索引を独自に再構築しない。ArchitectureExplorerの同じdaemonを利用する。検証に必要な原本・依存閉包を別途固定することは、索引の二重実装とは区別する。

## 4. 現在の基盤と目標の区別

2026-11-16に確認したswift-formal READMEとVerification設計は、生成モデルに対する明示的な有限スカラーケースの検査を提供し、一般のsource-to-model意味保存はUNVALIDATEDとする。Actor／asyncや一般のアプリケーション全体は対応範囲外と記載されている。[R1][R2]

したがって、次を分ける。

| 範囲 | 本仕様の扱い |
|---|---|
| 既存Backendでできるもの | 対応スカラー入力・明示ケースのTLC／Lean実行、結果・証跡の保持 |
| Invar側で新規実装するもの | 計画、静的ルール、テスト・Fuzzアダプター、世代管理、表示連携 |
| 要求全体の後段目標 | モジュール間・Actor間の意味を保った切り出しと形式検証 |
| 下位Backendが未対応のとき | 必要能力を記録し、UNSUPPORTED／BLOCKEDとする。手作りモデルへ黙って迂回しない |

初期実用版の完成と、要求全体の完成は別に報告する。統合しただけでActor検証が可能になったと記述してはいけない。

## 5. 実行パイプライン

```text
ArchitectureExplorerの固定snapshot / 変更イベント
            ↓
Scope Inventory（対象と未取得範囲の列挙）
            ↓
Rule / Contract Discovery（調査候補・明示契約の取得）
            ↓
Obligation Registry（何を確かめるか）
            ↓
Planner + Capability Match + Dependency Closure
            ↓
Immutable Verification Input + Harness / Scenario
            ↓
Scheduler
    ├── Static Rules
    ├── swift-formal: TLC / Lean
    ├── Native Tests
    └── Fuzzing / Sanitizer
            ↓
Evidence Store → Finding Assessment → Policy Report
            ↓
Explorer拡張GUI / invar CLI / 上位MCP / CI
```

モデルの生成、性質の検査、実コードへの対応、業務上の正しさを一つのPASSへ潰さない。

## 6. データモデル

| モデル | 意味・必須情報 |
|---|---|
| ScopeInventory | workspace、snapshot、context、対象entity、未解決・除外・未知範囲 |
| Hypothesis | 疑う内容、発見rule、根拠、推論の限界、対象、優先理由 |
| Obligation | property ID、命題／oracle、量化範囲、前提、対象、承認状態 |
| VerificationPlan | 入力manifest、job DAG、選択Backend、予算、未計画理由 |
| VerificationInput | 原本bytes／artifact、hash、依存閉包、context、変換情報 |
| Attempt | 実行ID、Backend／tools版、開始終了、予算、ログ、実行状態 |
| Evidence | model／native等のdomain、結果、scope、再現情報、信頼前提 |
| Finding | 問題候補の識別、関連Evidence、状態・確度・重大度・適用状態 |
| PolicyReport | 対象、policy版、判定、指摘、未実行、coverageと根拠 |

### 6.1 IDと適用状態

EntityIDはArchitectureExplorerのものを参照する。ただし同じEntityIDであることだけでは結果を再利用しない。

ObligationIDは、rule／契約の版、対象のidentity、命題の正規形、前提、scopeから安定に定める。本文・依存・toolchain等の変更は別のinput fingerprintとAttemptに記録する。

Findingの重複統合は同じproperty・対象・入力・witness等の根拠がある場合だけ行う。似たメッセージや同じ行番号で一つのバグと決めない。関連候補はまとめて表示できるが、個々のEvidenceを保持する。

### 6.2 依存とcache key

source bytes、ビルド構成、依存lock、環境モデル、property、scenario、harness、Backend／tool／runtime／変換規則の版、seed、予算、計測設定を含む。依存が不明な範囲を空集合にしない。

同じ実行命令でもoraclesが変われば再評価する。プロパティを弱めて前回の失敗を消す場合は契約変更としてdiffを記録する。

## 7. 何を検証するか：Oracleと契約

正しさの条件は次の由来を持つ。

| 由来 | 許す扱い |
|---|---|
| 言語仕様に基づく条件 | 対応する版・型・入力domainを明示したbuiltin rule |
| 開発者の契約／assert／仕様 | source range・承認版・build contextを付けたproperty |
| 既存テスト・golden data | 期待値を独立入力として保持 |
| 参照実装との比較 | 参照実装・版・対応・前提を保持。差異だけで片側を正解と断定しない |
| property mining・heuristic・AI案 | 未承認のHypothesis。製品の正しさの基準へ自動昇格しない |

**検証対象の実装と同じ計算から期待値を生成し、その一致だけで仕様への正しさを主張してはいけない。** そのような試験はBackend間の整合性試験として別に記録できる。

Swiftのtrapが常にバグとは限らない。入力domainや前提違反を表す正当なtrapと、仕様内入力での予期しないtrapを区別する。assert等の扱いは実際のbuild構成と合わせる。

命題が常に真になる、事前条件が到達不能、入力集合が空、必要なケースが一件も走らない、といった空虚な成功を検出・報告する。契約と前提を弱めて自動的にPASSへ変えない。

## 8. 探索・優先順位

### 8.1 Scope Inventoryを先に作る

宣言された対象のmodule／entity／関係／能力／除外をsnapshotに固定して列挙する。ページング上限で取得できなかった範囲は未探索として記録する。最初の500 nodesだけを「全体」と報告しない。

### 8.2 Ruleの出力

Ruleは根拠付きHypothesisまたは明示契約に基づくObligationを生成する。rule ID／版、必要Factの種別、完全性要求、読んだ依存集合、診断、無効化条件を持つ。

例：禁止されたレイヤー依存、同じresourceへの更新候補、入力検証と使用の間の中断候補、複数境界を通る値、未処理らしいエラー。pattern検出と実際に起きる違反を区別する。

### 8.3 優先順位

変更近接性、実際の失敗履歴、明示的に重要な契約、外部入力境界、共有状態、解析の確かさ、見積コストを用いる。初期版は決定論的なruleと説明可能な優先順位とし、根拠のない「バグ確率85%」等を作らない。

優先順位は順番を変えるだけで、低優先度をPASSにしない。時間切れはDEFERRED／NOT_RUN。ユーザーの明示要求と必須CI契約をheuristic探索より優先する。

## 9. ArchitectureIRと実行意味

ArchitectureIRは「どこを調べるか」とsource bindingの根拠であり、FormalIRへの意味を復元する材料だけとしては不十分である。

Invarは同じsnapshotに属する元ソース／SIL／build情報を取得し、対応するswift-formal frontendへ渡す。構成図だけから`await`、atomicity、整数幅、副作用、例外、FFIの意味を推測しない。

取得できないデータフローやaliasは不明とする。未対応部分を無視したプログラムを「元コード」として検証しない。

## 10. モジュール横断・Actor横断

### 10.1 構造から必要になる追加情報

呼び出し元・calleeだけでなく、引数／戻り値、共有resource identity、read／write、alias精度、同期・非同期境界、message、状態所有、エラー・キャンセル、外部I/O、契約を必要に応じて取得する。

これらは言語別解析Provider・コンパイラ情報・明示契約から取得する。通常のCall Graphがあるだけでは、値の伝播や実行順序が解決したとは扱わない。

### 10.2 検証単位

単一関数だけでなく、propertyに関係する関数群・shared resource・actor群を`VerificationUnit`として束ねる。最小化は意味を保てる根拠がある場合に限る。最小化不能なら範囲を広げる。

切り出し外の処理は、対象propertyに十分な契約、検査可能な抽象化、元本体を含む範囲拡大のいずれかで扱う。何もしないstub／固定の成功値で置き換えない。

### 10.3 抽象化の証跡

抽象化ごとに関係、保存する観測・property、無視する範囲、仮定を記録する。過大近似モデル上の反例は実コードで不可能なことがあるため、native replayまたはwitnessの実装への持ち上げの根拠がなければ、実装で再現済みとしない。

モデルでpropertyが成立しても、実装の振る舞いが適切に含まれること・propertyが対応すること・前提が満たされることが未検証なら、実装の保証へ移さない。

### 10.4 合成検証

Assume–Guaranteeを利用する場合、各moduleの前提を誰が満たすかを明示し、前提依存をDAGまたは正当化された同時証明として扱う。Aの証明がBの結論を仮定し、Bの証明がAの結論を仮定するだけではシステムの証明にならない。

各関数が単体で成功したことを、複数Actorの相互作用の安全性へ自動昇格しない。未対応Actor semanticsは上流の能力不足として残す。

### 10.5 並行性の仮定

スケジューリング、公平性、message配送、キャンセル、deadlockと正当な待機／終了を明示する。モジュールの依存cycleを実行時deadlockと混同しない。詳細な意味を持たない`await`の構文patternは調査候補までとする。

## 11. Backend契約

```text
capabilities(toolchain, profile, targetContext)
    -> supported inputs / properties / modes / restrictions
plan(obligation, immutable inputs, budget)
    -> executable plan or explicit unsupported / blocked
run(plan, cancellation)
    -> progress + attempt + evidence + actual dependencies
replay(evidence, matching inputs)
    -> reproduction evidence or explicit unsupported
```

能力照合は実行前に行う。UI上で選べることと、その入力に対応することは別。機能不足は`UNSUPPORTED`、不明な能力は`UNKNOWN_CAPABILITY`、環境不在は`BLOCKED`。

TLA+を「Actor専用」、Leanを「数式専用」に固定しない。property、入力モデル、対応profileをもとに選択する。同じpropertyを複数手法で調べても、同じruntimeや翻訳を共有する結果を独立証拠として数えない。

### 11.1 Static Backend

ArchitectureExplorerのFactsと宣言済み設計policyを評価する。v1は少なくとも禁止依存とpolicy指定cycleを検出し、具体的なedge witnessと根拠を返す。構造cycleを表示する機能はExplorer、許容policyに照らして違反とするのは本Backend。

不完全graphで違反edgeが見つかったという肯定的根拠と、違反が一つもないという否定的結論の条件を分ける。欠けた辺に違反が存在し得る場合、後者を完全なチェック結果にしない。

### 11.2 Formal Backend

swift-formalの公開FormalCompiler／FormalValidation等を使用する。[R3] 実際のAPIと能力を固定版で確認し、想像したメソッドを実装契約と混同しない。

有限ケースの出力`MODEL_CHECKED`／`PROVED`は、指定した生成モデルとケースへの結果として取り込む。`translation: UNVALIDATED`は必ず併記し、コード全体の証明と表示しない。[R1][R2]

Timeout、fuel、stack、状態探索上限、cancel、tool errorは未完了でありPASSではない。SANYが通ること、データdecode一致、Leanが命題を証明したこと、source-to-model対応の保証は別に記録する。

Leanの証跡は命題、前提、実際の公理依存、生成物、toolchain、カーネル検査結果を保持する。現在のBackendの公理監査を回避しない。任意のlakefileや未承認のproperty codeを新ツール側から迂回実行しない。[R2][R4]

### 11.3 Native Test Backend

明示されたテストターゲット／ケースを、固定入力からbuildした対象で実行する。test runner、build命令、環境、oracle、artifact hash、stdout／stderr、exit／signalを保存する。

expected return、assertion、仕様内trap、予期しないcrash、runner errorを分ける。テスト失敗とtool起動失敗を同じ分類にしない。失敗したoracleや環境を無視してバグ箇所を断定しない。

### 11.4 Fuzz Backend

初期は、明示されたharness／input encoding／corpus／oracle／予算を持つローカルFuzzerアダプターを提供する。特定のエンジンにcore schemaを依存させない。LLVM libFuzzerを選ぶ場合は固定したtoolchainとinstrumentationを試験する。[R5]

任意のSwift／RustプロジェクトをそのままFuzzできると主張しない。対応する境界型なら決定論的なharness生成規則を追加できるが、未対応型・所有権・副作用は明示的に拒否する。

crash input、seed、corpus digest、harness、入力domain、sanitizer設定、対象binary、実行環境を保存する。失敗入力の縮小は、同じoracle違反が維持されることを確認し、元入力も残す。random seedだけで並行実行の再現を保証しない。

Fuzzを一定時間回して失敗が出なかった結果は`noViolationObservedWithinBudget`。全入力の安全性や証明として扱わない。

## 12. 結果を複数の軸で保持する

| 軸 | 値の例 |
|---|---|
| Attemptの実行状態 | queued、running、completed、cancelled、timeout、resourceLimited、toolError、unsupported、blocked |
| propertyに対する結果 | holdsWithinScope、violatedWithinScope、unknown、notEvaluated |
| 証跡のdomain | architecture、abstractModel、generatedModel、nativeExecution |
| 証拠の種類 | staticPattern、policyWitness、modelCounterexample、modelProof、nativeFailure、sanitizerReport、nativeReplay |
| translationの状態 | validatedForProfile、unvalidated、notApplicable |
| 現入力への適用 | matchesInputs、stale、unmatched、unknown |
| Findingのtriage | candidate、needsReview、confirmedForContract、resolved、suppressed |

`confirmedForContract`は、指定された契約に対する根拠が成立したことを表す。ユーザーの意図した業務仕様が正しかったことまで自動保証しない。

モデル反例を実装の違反へ昇格できるのは、同入力でのnative再現、または当該witnessを実装へ持ち上げる十分な対応関係を検査できた場合。単なる過大近似へのforward simulationだけで任意のモデル反例が実現可能だとはしない。

証明失敗はバグの証明ではない。テスト成功は一般定理の証明ではない。複数ツールの結果が矛盾した場合は、翻訳・property・環境差を調査する未解決事項として残す。

## 13. Snapshotと入力固定

ArchitectureExplorerのsnapshot／InputManifest／leaseから取得したbytesを、Invarのprivateなimmutable input workspaceへコピーし、digestを再確認する。コピー中に変化すれば再採取または明示失敗。

manifest、dependency lock、compiler flags、target triple、generated files、imported artifacts、runtime contract等を検証対象に応じて含める。buildが新たな依存・生成物を作る場合はそのdigestを記録して入力契約を完成させ、未把握のまま再現可能と表示しない。

コンパイル・実行時に元のlive workspaceを混在して読まない。特定のbuild systemで隔離できない場合はcapabilityとlimitationを記録し、強い保証やcache再利用を行わない。

未保存バッファは初期必須ではない。将来対応してもdisk snapshotと同一世代に混ぜない。

## 14. 差分再検証

### 14.1 管理対象

検証ごとのDependency Manifestを保持する。コード依存だけでなく、property、前提、environment summary、contract、toolchain、Backend、runtime、scenario、harnessを含める。

ArchitectureExplorerの`graph.impact`は候補取得に使うが、これだけを再検証不要の証拠にしない。Backendが実際に読んだ情報と未解決範囲を加えて無効化する。

### 14.2 更新処理

```text
入力変更通知
  → 関連結果のapplicabilityをstale / unknownへ
  → 既知の依存閉包で再検証対象を決定
  → 未解決がある場合はmodule／workspaceへ保守的に拡大
  → debounceして最新入力を取得
  → job DAGを作り、同一cache keyの実行を統合
  → 予算内で順次実行
  → 完了結果の依存fingerprintを比較
  → 一致する対象だけ現入力へ適用
```

実行中に別ファイルが変わっても、当該jobの全依存が不変だと確認できれば結果を再利用できる。逆にEntityIDや対象ファイルだけ一致しても依存が変われば無効。

旧jobはキャンセルできる範囲で停止し、止められない結果は履歴へ保存する。永続編集による飢餓には表示・手動snapshot固定を提供する。必ず最新まで瞬時に証明できると保証しない。

自身のAnnotation更新やGUI座標の変更は入力変更扱いにしない。eventsのorigin／causationを使いループを防止する。

## 15. Schedulerと実行隔離

workspaceごとに計画・queueの所有者を一つにする。複数GUI／Agentセッションから同じ入力・propertyを要求した場合は共有実行し、セッションを閉じたから他利用者のjobまでkillしない。

予算はwall time、CPU、memory、process count、workspace size、出力量、状態数／fuel／seed等を分ける。ユーザー操作、既知の再現、必須契約、変更付近の候補、残り探索の順を初期方針とする。優先理由をAPIで取得可能にする。

入力由来の文字列をshellへ連結しない。実行ファイル・引数・環境を明示し、process group・timeout・cancel・cleanupを管理する。ライブラリ呼び出しで重い検証を行う場合も、GUI／索引processと隔離した所有workerを利用できる構成にする。

テスト・Fuzzer・build scriptはユーザーコードを実行する。workspace trust、許可root、ネットワーク、資格情報、OSの隔離profileを確認する。別processだけでsandboxと称さない。要求された隔離を実現できなければ`ISOLATION_UNAVAILABLE`で止め、無断でhost実行へfallbackしない。明示的な隔離緩和はユーザー承認とレポートに残す。

正常なscan／watch中にツールや依存をdownloadしない。取得・インストールは別の明示操作とする。

## 16. GUI拡張と人間の操作

ArchitectureExplorer-EXTENSIONS-SPEC.mdに従う。Invarが起動し、ユーザーが許可したProviderとして登録する。

| Contribution | 内容 |
|---|---|
| Findings一覧 | candidate／model violation／native再現、範囲・前提・状態 |
| Inspector section | 対象の契約、Attempt、Evidence、未対応理由 |
| Risk overlay | 探索優先順位と根拠。証明済み色と混同しない |
| Counterexample graph | 実行順、状態変化、ソースbinding、モデル／nativeの区別 |
| Timeline | Actor・task・event。観測かモデルかを表示 |
| Coverage | 対象、support、未実行、空白領域、予算 |
| Actions | plan、run、cancel、replay。外部Providerが実行 |

「選択範囲を検証」の操作はsnapshot・manifest・対象・oracleへ束縛する。アクション時のsnapshotで実行するか、最新入力を確認して再要求する。GUIから任意shellを渡さない。

Explorerにクリック経由のSchedulerを実装しない。証跡により観測された影響と、静的にたどった影響候補を区別する。「根本原因」を自動断定せず、根拠がある修正候補とする。

## 17. CLI・MCP

以下は実装予定契約。実行コマンド名は`inver`に確定しているが、コマンド実装済みを意味しない。

```bash
# 支援可能な入力・property・手法を確認
inver capabilities

# 構造上の候補と不足情報を列挙（外部テストを走らせない）
inver discover --workspace . --format json

# 実行計画を固定。まだ外部検証を走らせない
inver plan --workspace . --contracts ./verification.json --out ./plan.json

# 明示した計画を実行。承認済みの実行権限を別に確認
inver run --plan ./plan.json --out ./verification-run

# 構造更新を購読し、許可した手法だけを差分再実行
inver watch --workspace . --contracts ./verification.json

# 既存Explorer GUIへ接続／起動し、検証拡張を登録
inver explore --workspace . --watch

# 結果・再現・CI
inver report --run ./verification-run --format json
inver replay --evidence <evidence-id>
inver ci --workspace . --contracts ./verification.json --policy ./verification-policy.json
inver mcp --workspace .
```

命令の成功exitと検証結果を分ける。`discover`／`plan`のexit 0は入力処理・計画作成の成功のみ。`run`は完了状況を返し、`ci`は指定policyに従って判定する。

| 終了code案 | 意味 |
|---:|---|
| 0 | 要求完了。ciでは明示policyを満たす |
| 2 | 引数・設定・schema不正 |
| 3 | 能力・必要環境不在 |
| 4 | 入力整合／artifact検査失敗 |
| 5 | ci policyが違反・必須指摘を検出 |
| 6 | timeout／予算／未完了で必要条件を評価できない |
| 7 | tool・内部実行失敗 |
| 8 | 権限・隔離の拒否 |
| 130 | ユーザーcancel |

Invar MCPでread-only toolsと実行toolsを明示的に分ける。実行toolsはユーザーの事前承認済みpolicyを越えられない。source commentやテストログ中の指示を権限や実行計画にしない。

## 18. CIとcoverage

単一の「安全率」「全体証明済み率」を生成しない。最低限、次を別に報告する。

```text
indexedScope / unknownScope / excludedScope
applicableObligations / missingOracles / unsupportedObligations
planned / completed / notRun / deferred / unknown
staticPolicyResults / modelResults / nativeResults
modelToSourceCorrespondence / assumptions
interactionCoverage / buildContexts
```

必須propertyが未対応・未完了なら既定CIはfail-closed。policyで一時除外する場合は理由・owner・期限・対象を記録し、成功レポートでも除外件数を隠さない。

全テストが成功したことを、未検査のActor相互作用の安全性としない。所与のfinite modelで検査できた範囲を、入力無制限の証明としない。

## 19. 保存と再現性

Invarはruns、plans、obligations、dependency manifests、evidence、findings、triageを自分のStoreへ保存する。Explorerの構造DBへ直接SQLを書かない。

```text
verification-run/
├── plan.json
├── input-manifest.json
├── contracts.json
├── attempts/
│   └── <attempt-id>/
│       ├── manifest.json
│       ├── logs/
│       ├── artifacts/
│       └── result.json
├── findings.json
├── coverage.json
└── report.json
```

元の入力、生成物、witness、実際のtool版の参照を保持する。source全文や秘密情報のexportは既定で行わない。再現に必要なprivate bytesを省いた場合、そのレポート単体では再現できないことを示す。

環境・タイミング依存の失敗が再現しなければflaky／unreproducedと記録し、成功した1回で過去の反例を消さない。seed、時刻、scheduler、外部サービス等の再現限界を記録する。

## 20. AIの扱い

抽出、変換、判定、優先順位の基本動作にLLMを必要としない。決定論的規則、版付きProvider、検査された契約を利用する。

将来AIがテスト案や命題を提案しても、提案はHypothesisとして別保管する。承認・型検査・対応範囲・oracle確認・実検証を通さずに、Facts、assumptions、model、PROVEDへ書き込めない。

実装Agentがコードを作ることと、製品の信頼境界にLLMを入れることは別。実装のバグは、独立期待値、mutation、異常系、実工具のE2Eで検査する。

## 21. パッケージ構成

```text
Invar/
├── Package.swift
├── Sources/
│   ├── VerificationCore/         # IDs, Hypothesis, Obligation, Evidence
│   ├── VerificationDiscovery/    # scope inventory, rules, priorities
│   ├── VerificationPlanner/      # capability match, closure, job DAG
│   ├── VerificationRuntime/      # scheduling, snapshot, process isolation
│   ├── VerificationBackends/     # static / formal / test / fuzz adapters
│   ├── VerificationStore/        # attempts, evidence, findings
│   ├── VerificationExplorer/     # Extension API binding; no parser copies
│   └── invar/                    # CLI / MCP composition
├── Schemas/
├── Fixtures/
├── Tests/
├── Documentation/
└── PROGRESS.md
```

下位依存はアダプターへ限定する。rootにswift-webは加えず、ExplorerのWeb helperと宣言的拡張を使う。専用Web Appが後で必要なら別Packageで合成する。

最初に依存revision、公開API、resources、toolchain、ライセンスを固定する。ArchitectureExplorerは今回の基礎仕様時点で実装未確認のため、存在しない公開製品や統合成功を仮定しない。

## 22. 実装順序と要求全体

| Phase | 内容 | 完成判定 |
|---|---|---|
| V0 | SDK／schemas／Backend契約／入力識別 | mockで異常系と依存境界が試験可能 |
| V1 | discovery／static rules／plan／result store | 実projectの跨module policy違反と未解析範囲を記録 |
| V2 | swift-formal adapter | 実TLC／Leanで明示有限ケース・反例・UNKNOWNを区別 |
| V3 | native tests／Fuzzer／replay | 実binaryで失敗再現・縮小・ログ・scopeを保存 |
| V4 | watch／Explorer拡張／CI／MCP | 編集・切断・旧job・権限のE2Eが通る |
| V5 | 高度な跨module／Actor semantics | 下位意味解析とモデル対応を含む専用fixtureで実証 |

V0–V4が初期実用版。V5は依頼の「相互作用の継続探索」の重要な到達目標として残す。V5未達で要求全体が完成したとは報告しない。v1のActor未対応をInvar内のAI生成モデルで隠すことは禁止する。

V3では少なくとも、2つ以上のnative moduleをまたぐ契約違反の実テストと、宣言した1つのFuzz profileの実harnessを検証する。モデルによるActor全状態探索が未対応でも、native integration testという別種の証拠を取得できることを示す。

V5では2つ以上のActor、共有resource、キャンセル／失敗／再試行、複数スケジュール、正例・負例を含める。単一のsleep依存テストで形式的な相互作用検証の完成としない。

## 23. 受け入れテスト

| ID | 合格条件 |
|---|---|
| INV-001 | InvarがAEとswift-formalへ依存し、逆依存・cycleがない |
| INV-002 | AE単独が検証runtimeなしで起動・探索できる |
| INV-003 | 同じworkspaceの索引daemonを共有し二重構造解析をしない |
| INV-004 | inventoryが全page・除外・未解析を区別する |
| INV-005 | 禁止依存の具体的edge witnessを取得する |
| INV-006 | policyのないcycleを自動で実行時バグにしない |
| INV-007 | pattern候補を実コードで再現済みと誤表示しない |
| INV-008 | oracle不在・未承認propertyを合格条件へ自動採用しない |
| INV-009 | 同じ実装で期待値を作った試験を独立の仕様検証としない |
| INV-010 | 空入力・未実行・到達不能前提等を空虚な成功として診断する |
| INV-011 | Backend能力不足をUNSUPPORTEDとして残す |
| INV-012 | ArchitectureIRから未知の実行意味を補完しない |
| INV-013 | snapshot取得中の変更で混在入力を実行しない |
| INV-014 | immutableな同入力を全Backendへ渡す |
| INV-015 | 入力固定不能な環境を再現性・保証へ無断昇格しない |
| INV-016 | 実TLC／Leanで正しいケース・誤期待・資源上限を区別する |
| INV-017 | finite PROVEDとtranslation UNVALIDATEDを同時に保持する |
| INV-018 | Lean admission／runtime改ざんを下位のauditどおり拒否する |
| INV-019 | model反例をnative再現なしで実装バグ確定としない |
| INV-020 | 抽象化のspurious witnessを検出し、証跡を保存する |
| INV-021 | 単体contractの循環仮定をシステム証明として受理しない |
| INV-022 | 2 native moduleをまたぐ失敗を実テストで再現する |
| INV-023 | Fuzz crash入力・seed・harness・binaryを保存し再現する |
| INV-024 | Fuzz入力縮小後も同じoracle違反が維持される |
| INV-025 | Fuzz時間終了を全入力の安全性と報告しない |
| INV-026 | tool crash、対象crash、timeout、cancelを区別する |
| INV-027 | 未承認build・テスト・Fuzz・ネットワークが実行されない |
| INV-028 | 隔離profile非対応時に無断host実行しない |
| INV-029 | process／memory／disk／output予算とcleanupが機能する |
| INV-030 | 依存・contract・toolchain変更でcacheを無効化する |
| INV-031 | 不完全call graphでは再検証範囲を保守的に拡大する |
| INV-032 | 旧jobが新入力の保証として表示されない |
| INV-033 | 無関係変更で全依存が同一の結果だけ再利用できる |
| INV-034 | Annotation通知から自己再実行ループを作らない |
| INV-035 | 複数利用者で同一jobを共有し他sessionを破壊しない |
| INV-036 | GUIで疑い／モデル違反／native再現／未対応を区別する |
| INV-037 | ActionIntentの重複・世代違い・cancelを契約どおり扱う |
| INV-038 | 削除・rename不明・staleの結果を別entityへ移植しない |
| INV-039 | CIで必須Obligation未実行をPASSにしない |
| INV-040 | 除外・suppressionの理由・owner・期限を表示する |
| INV-041 | 意図的な条件／算術／順序mutationで検出・拒否能力を確認する |
| INV-042 | Backend間不一致を多数決で解決しない |
| INV-043 | 検出消失が再解析失敗の場合、resolvedとしない |
| INV-044 | 同じsnapshotのCLI／GUI／MCP結果が一致する |
| INV-045 | V5：複数Actorの誤interleavingと修正版を意味対応込みで区別する |
| INV-046 | V5：キャンセル・外部失敗・再試行・liveness前提を保持する |
| INV-047 | V5未達でもcoverageにBLOCKEDを残し全体完成としない |
| INV-048 | fresh runと有効cache再利用が同じproperty／範囲／判定を保持する |

INV-001〜044・047〜048は初期実用版の対象。INV-045〜046は要求全体の完成gate。NOT_RUN／BLOCKEDをPASSへ読み替えない。テスト件数ではなく実ログとfixtureを紐付ける。

## 24. 実装Agentへの必須成果物

実Swift Package、固定依存、公開SDK適合、各schema、実CLI／MCP、実Backend integration、Explorer拡張、予算・権限・世代競合のE2E、再現可能なfixture、実測付きPROGRESS／SUPPORT／TRUSTを納品する。

上流未対応やAPI不足はblocking requirementとして別記する。本パッケージへ場当たり的な言語意味実装や検証runtimeの複製を追加して隠さない。

## 25. 調査資料・根拠・現状

以下は2026-11-16に確認。外部事実と、本書の新規設計要求を区別する。

- [B1] ArchitectureExplorer-SPEC.md v1.0。構造探索・formal非依存・外部Annotation・部分graph・世代管理を規定。
- [B2] ArchitectureExplorer-EXTENSIONS-SPEC.md v1.2 / Extension API 1.0（同梱）。新規の型付き拡張契約。まだ実装されているとは主張しない。
- [R1] swift-formal README。生成モデルへのfinite cases、Actor／async未対応、一般の意味保存未認証。取得blob：`7c2831f6b9e989bb917896125513681a1dd500c9`。`https://github.com/1amageek/swift-formal/blob/main/README.md`
- [R2] FormalValidation/Verification/DESIGN.md。明示scenario、bounds、controlled Lean、audit、translation UNVALIDATEDの契約。取得blob：`7138a4dbac9e07799f30310295f0ace348ef775d`。`https://github.com/1amageek/swift-formal/blob/main/Sources/FormalValidation/Verification/DESIGN.md`
- [R3] swift-formal Package.swift。4つの公開library製品とformal executable。取得blob：`907aa6297ab894bbf5b6935e929343d3e7e8089f`。`https://github.com/1amageek/swift-formal/blob/main/Package.swift`
- [R4] Lean公式「Validating a Lean Proof」。命題・前提・証明依存の監査、admissionとの区別。`https://lean-lang.org/doc/reference/latest/ValidatingProofs/`
- [R5] LLVM公式「libFuzzer」。harness／corpus／coverage-guided executionの契約を参照。採用版や統合成功は未確定。`https://llvm.org/docs/LibFuzzer.html`

本書の作成ではアプリケーション実装、リポジトリ変更、tool install、実コードの検証を行っていない。
