# ArchitectureExplorer 実装仕様書

**仕様バージョン：1.0**  
**作成日：2026-11-16**  
**状態：実装エージェント向け要求仕様。実装済み・動作検証済みを意味しない。**  
**リポジトリ／ルートSwift Package名：ArchitectureExplorer**  
**公開CLI：`architecture`**

> ソースコードの構造・依存・振る舞いを、言語非依存のArchitectureIRに記録し、コードの変更に追従しながら、人間とAIエージェントが階層的に調査できるローカル開発ツール。
>
> **ArchitectureExplorerは形式検証器ではない。`swift-formal`には依存しない。両者を組み合わせた検証の実行計画・結果評価は、将来の別パッケージが担当する。**

---

## 0. 仕様の読み方と優先順位

本書のMUST／禁止は受け入れ条件、SHOULDは理由を記録した変更を許す設計指針とする。「将来拡張」はv1の完成条件に含めない。

本書では以下を分ける。

- **確定方針**：この会話で決まった製品名、責務分離、階層探索、変更追従、Web GUI、CLI／AI連携。
- **本仕様の設計決定**：具体的なAPI、保存方式、パッケージ境界、v1範囲、制限、受け入れテスト。実装担当はこの契約を実装する。
- **確認した外部事実**：既存ライブラリの公開契約。末尾の[R1]〜[R9]を参照。上流機能の存在は本製品との統合成功を意味しない。

優先順位は「本書の責務境界 → データ／更新／安全性の契約 → 公開インターフェース → 実装詳細」。以前の議論にある `formal explore`、ArchitectureExplorerからswift-formalへの必須依存、FormalIRとArchitectureIRの統合は採用しない。

実装担当は、実装上の変更をADRに記録する。MUSTの緩和、依存方向の変更、対応範囲の縮小は無断で行わない。未達はPROGRESSに残し、完成と報告しない。

## 1. 目的と利用場面

### 1.1 答える問い

1. このプロジェクトは、どのシステム・パッケージ・モジュール・型・関数で構成されるか。
2. 各要素は何に依存し、どこから参照・呼び出しされるか。
3. 選択した関数の制御フローはどうなっているか。
4. いま編集した箇所によって、構造上どの要素が影響候補になるか。
5. 設計者が定義した責務・レイヤーと、実際に抽出された構造はどう対応するか。
6. 表示した情報はどのソース、解析器、ビルド構成、リビジョンに基づくか。
7. 外部ツールの結果が付いている場合、どの対象・入力に対する結果か。

### 1.2 利用者

人間はブラウザGUIで全体から細部へ掘り下げる。Claude CodeなどのエージェントはCLI／MCPを使い、必要な部分グラフと根拠だけを取得する。両者が別の解析を重複実行せず、同じサービスとスナップショットを共有する。

### 1.3 中核原則

- 構成図はソースの代替ではない。全ノード・全関係から根拠へ戻れること。
- 構造の取得に、TLA+、Lean、SIL生成、形式検証の完了を要求しない。
- 構文で見えた事実、意味解析で解決した事実、設計者の指定、外部の観測を混同しない。
- 未解決は未解決として表示する。名前の類似やAIの推測で接続を確定しない。
- HTMLを変更のたびに再生成するのではなく、起動中のGUIへグラフの変更を配信する。
- 全言語を同じ精度で解析できると主張しない。能力を言語・解析器・機能単位で宣言する。

## 2. 責務と非スコープ

### 2.1 ArchitectureExplorerが持つ責務

ソース／プロジェクト構成の収集、言語別Frontend、ArchitectureIR、差分索引、グラフの階層化と問い合わせ、永続キャッシュ、解析の世代管理、ローカル常駐サービス、Web GUI、CLI、MCP、エクスポート、汎用外部結果の関連付け。

解析スケジューラは「構造・意味情報・CFGを取得する解析ジョブ」だけを管理する。

### 2.2 持たない責務

| 除外対象 | 担当する場所／扱い |
|---|---|
| TLA+／Lean生成、TLC／Lean実行 | swift-formal等の独立パッケージ |
| 複数検証器の実行計画、再証明、CIの総合合否 | 将来の統合検証パッケージ |
| FormalIRの定義・実行意味・意味保存の証明 | 形式検証側 |
| 実行中プログラムの自動トレース収集 | 将来の専用Provider。v1では外部結果として表示可能にする |
| 任意コードの完全なCall Graph／alias解析 | 保証しない。能力と不確実性を表示 |
| 自動リファクタリング、ソースの書き換え | v1対象外 |
| AIによる責務の自動確定・推測した依存の登録 | 禁止 |
| クラウド送信、アカウント、共有サーバー | v1対象外。ローカル動作が標準 |

依存禁止は直接依存だけでなく、`ArchitectureFormal`のような連携モジュール、暗黙の`formal`サブプロセス起動、インストール時のJava／Lean取得にも適用する。

### 2.3 将来の統合パッケージとの境界

```text
統合検証パッケージ［本書では実装しない］
    ├── ArchitectureExplorerのライブラリ／API
    └── swift-formalのライブラリ／CLI

ArchitectureExplorer ──×── swift-formal
```

上位パッケージは変更イベントとソース識別情報を読み、別途検証を行い、汎用Annotationを返す。Explorerは外部ステータスを勝手に格上げせず、入力との一致状態を表示する。

## 3. 外部依存とパッケージ境界

### 3.1 採用方針

| 依存 | 使用場所 | 方針 |
|---|---|---|
| swift-skeleton | Frontendの構造索引アダプター | Swift／Rustの宣言抽出に再利用。意味解決やCFGの根拠にはしない |
| swift-web | Webホスト用の別Swift Package | HTTP、WebSocket、HTML配信に採用 |
| SwiftHTML | Webパッケージ | HTMLシェルとページ構成 |
| SwiftWebUI | Webパッケージ | 必要なSSR部品に利用可。v1はWASM実行を必須にしない |
| Cytoscape.js | Webアセット | 対話型グラフの初期レンダラー |
| ELK.js | Webアセット／Worker | 階層型配置。表示部分グラフに限定して実行 |
| Mermaid | エクスポート | GUIの正本や主描画エンジンにはしない |
| SourceKit-LSP／rust-analyzer | 明示設定されたローカル解析プロセス | 参照・意味解決の補強。未導入でも構造探索は動作 |
| swift-formal／TLC／Lean | なし | 依存・自動起動しない |

swift-skeletonは本文を保持せず、型解決、意味的な到達可能性、正しさを証明しないと明記している[R1]。既存の短いskeletonテキストを再パースしてCall Graphを「復元」する実装は禁止する。

Cytoscape.jsはグラフ表示と操作、ELK.jsは配置を担当する既存ライブラリであり[R6][R7]、ArchitectureIRの意味や階層を決めるものではない。

### 3.2 モジュール分割だけでなく、ビルド境界を分ける

swift-webの確認済みPackage.swiftはSwift tools 6.4、macOS 26.2を要求する[R3]。同じmanifestに全依存を入れたまま「Webターゲットをimportしないので影響しない」と扱ってはいけない。

**同一リポジトリ内の2つのSwift Package**とする。

```text
ArchitectureExplorer/
├── Package.swift                    # Headless本体。swift-web依存なし
├── Sources/
├── Tests/
├── Apps/
│   └── ArchitectureExplorerWeb/
│       ├── Package.swift            # 本体 + swift-web + SwiftHTMLに依存
│       ├── Sources/
│       └── WebAssets/
├── Schemas/
├── Fixtures/
├── Documentation/
└── Tools/
```

- ルートPackage：製品名`ArchitectureExplorer`。Swift tools 6.2を最低設計値、macOS 13を最低宣言値とする。実際の対応はCI実測を条件とし、未試験環境をサポート済みにしない。
- Web Package：Swift tools 6.4、macOS 26.2以上。公開されている整合したhost toolchainを固定する。
- 完全版配布は初期macOS arm64を対象とする。Linux／Windows版はv1の完成条件ではない。
- 本体CLIはWeb helperを別プロセスとして起動する。SwiftPMの依存方向はWeb → 本体だけ。
- `ArchitectureIR`や問い合わせだけを使う上位パッケージはWeb Packageを解決・ビルドしない。
- WASMを後で使う場合はhost／SDKの組を固定する。上流資料は既定snapshotと明示的Swift 6.4.0の組を区別する[R4]。

### 3.3 依存の固定

確認時の参照点：

```text
swift-skeleton: fb10ef666a30e892b9f3a4ca0740702c6c621d80
swift-web:      6edadb6cfa92e3a4b26a1e669329be38f45212f4
```

これは調査の参照commitであり、統合済みの保証ではない。P0で実ビルドし、採用commit、推移依存、ツールバージョン、アセットのハッシュとライセンスをlockへ記録する。移動する`main`に依存した再現不能なリリースは禁止する。

## 4. v1の提供範囲

### 4.1 必須機能

| 機能 | v1の契約 |
|---|---|
| 入力 | ローカルworkspace、ソース、設定、汎用ArchitectureIR JSON |
| 初期言語 | SwiftとRust。両方でIRの汎用性を検証 |
| 構造 | workspace、package、module、file、type、callable、member |
| プロジェクト構成 | SwiftPM／Cargoの構成。実行許可のないmanifestは未解決として扱う |
| 意味情報 | Swift／RustのProvider連携。能力が得られる範囲のdefinition／reference／call hierarchy |
| CFG | §9の限定構文について両言語で生成。未対応関数は明示的に不完全とする |
| ライブ更新 | 保存済みファイルの変更、追加、削除、rename、設定変更 |
| GUI | 階層展開、絞り込み、検索、依存探索、CFG、詳細、履歴差分 |
| AI利用 | CLI JSON／MCP stdio。問い合わせ量に上限 |
| 出力 | JSON、Mermaid、SVG、単体HTML |
| 外部連携 | generic Annotationと外部部分グラフの受け入れ・表示 |

### 4.2 必須ではないが、拡張可能な形を保つもの

未保存エディタバッファ、全言語での高度な意味解析、精密なalias解析、実行時計測、完全なデータフロー、全SIL命令、任意のRPC接続の自動同定、証明グラフの自動抽出、リモート共同編集。

swift-skeletonの他言語パーサを取り込んだだけで同じ機能レベルを名乗らない。追加言語はcapability matrixとテストを追加して公開する。

### 4.3 「全部見える」の定義

全件を1枚の巨大図に描くことではない。**上位の構成から必要な型・関数・振る舞いへ到達でき、取得できない情報には理由が表示されること**を意味する。

## 5. システム構成と責務の所在

```text
ファイル／プロジェクト設定
          │
          ▼
変更監視 → 入力snapshot → Language Frontends
                               │
                               ▼
                     ArchitectureIR facts
                               │
                               ▼
                  Store + Graph Query Service
                     │         │          │
                     ▼         ▼          ▼
                   CLI       MCP       Web Host ──→ Browser
                                             HTTP / WebSocket

外部統合ツール ──→ 汎用Annotation API ──→ Store
```

### 5.1 論理モジュール

| モジュール | 所有する責務 | 禁止する依存 |
|---|---|---|
| ArchitectureCore | ID、診断、版識別、共通転送型 | Web、言語パーサ、formal |
| ArchitectureIR | entity、fact、evidence、snapshot契約 | Web、実行意味IR、検証器 |
| ArchitectureFrontend | Provider契約、Skeleton／意味解析／CFGアダプター | GUI、検証器 |
| ArchitectureGraph | 投影、階層、集約、探索、diff | 解析プロセス起動 |
| ArchitectureStore | 永続化、索引、transaction、履歴 | Web、Frontendの実行 |
| ArchitectureIndexer | 監視、入力snapshot、解析ジョブ、再解析範囲 | 検証ジョブ |
| ArchitectureService | 上記の合成、daemon、問い合わせ・購読・annotation境界 | swift-formal |
| ArchitectureClient | daemonへの接続、型付きクライアント | Web、具象解析器 |
| ArchitectureMCP | MCPからClientへの変換 | 独自グラフ、独自解析 |
| architecture | 引数、起動・終了、出力、Web helper起動 | 解析ロジックの複製 |
| ArchitectureServer（Web Package） | HTTP／WS、認証、Clientへの変換 | 直接DB書き換え |
| ArchitectureWeb（Web Package） | ページ、アセット、GUI | ローカルソースの直接探索 |

モジュールをまたぐ契約は公開されたimmutable／Sendable値を基本とする。単一の巨大なグローバル辞書に状態を集めない。細かいアダプターは同一モジュール内のコンポーネントにしてよい。

### 5.2 常駐プロセス

正規化したworkspaceとユーザーごとに1つのdaemonを基本とする。GUI、CLI、複数MCPセッションはそれへ接続する。起動競合はlockで処理し、PIDだけで生存判定しない。socket応答とprocess identityを確認する。

HeadlessのIPCは同一ユーザー限定のUnix domain socketと版付きJSON-RPCを採用する。WebホストはこのClientを利用する別プロセスとする。MCPのプロトコルと内部IPCは混同しない。

## 6. 階層とビュー

### 6.1 表示上の5段階

| 段階 | 主な表示対象 | 情報源 |
|---|---|---|
| L1 System | workspace、service、外部システム | workspace設定・明示的接続情報 |
| L2 Module | package、target、module、crate、依存 | project model／意味解析 |
| L3 Component | 型、Actor、interface、設計上のまとまり | 宣言と明示的なdesign group |
| L4 Function | 関数、method、呼び出し元／先 | 宣言、call site、意味解決 |
| L5 Behavior | basic block、CFG edge、対応する根拠 | 対応する振る舞いProvider |

階層数を実データの固定深さにしない。nested module、自由関数、ファイル内の複数型、extension、匿名closureなどを表現できること。L1〜L5は表示投影であり、全ノードに5段の祖先を強制しない。

### 6.2 3つの関係を分離

- **包含**：実際の宣言所有・module所属など。`contains`で表現。
- **依存**：imports、calls、references、usesTypeなど。包含を変更しない。
- **設計責務**：Presentation、Domain、認証など。明示的なdesign group／`memberOf`で表現。

ファイルシステムの木、宣言所有の木、設計レイヤーは別の投影とする。design groupへの所属は多対多を許す。表示用primary parentに多重所属の意味を押し込まない。

### 6.3 グラフの集約

上位ノード間の線は、下位の根拠edgeから導出する。edge種別別の件数、ユニーク対象数、参照する元edge ID、範囲、完全性を持つ。集約線を選ぶと具体的な呼び出し・参照へ降りられること。

循環依存はSCC等でまとめて表示できるが、元edgeを削除しない。レイヤー配置は設計上の依存禁止ルールを意味しない。ルールへの違反判定は上位統合ツールの責務とする。

## 7. ArchitectureIRの契約

### 7.1 正本

版付きのArchitectureIRデータモデルと、そのfact storeを正本とする。JSONは交換表現、SQLiteは永続化の実装、Mermaid／SVG／HTMLは投影・成果物である。UIの座標や描画ライブラリ固有の形式を解析の正本にしない。

### 7.2 データ要素

| 要素 | 必須フィールドの概要 |
|---|---|
| Workspace | ID、root mapping、設定digest |
| Entity | ID、kind、language、名前、identity key、任意のsource anchors、namespaced attributes |
| Fact | ID、producer、scope、関係／属性、sourceとtarget、revision、evidence IDs |
| Evidence | 解析器と版、入力digest、build context、位置、根拠種別、診断 |
| Snapshot | ID、workspace、入力version vector、graph revision、producer coverage |
| View | snapshot、query、投影ノード／edge、集約内訳、上限・切り捨て情報 |
| Annotation | 外部結果、対象、入力fingerprint、前提／範囲、外部状態、Explorerによる適用状態 |

Entity kindは、workspace、system、package、module、file、type、interface、actor、function、method、property、field、parameter、callSite、basicBlock、designGroup、externalSymbol、unresolvedSymbolを基本とする。未知の言語拡張はnamespace付きで保持する。

Edge kindは、contains、memberOf、imports、dependsOn、declares、references、calls、candidateCalls、usesType、inherits、conformsTo、implements、reads、writes、controlFlow、dataFlow、exposes、externalLinkを基本とする。

`calls`、`candidateCalls`、実行時観測による呼び出しは区別する。`reads`／`writes`が構文上の名前なのか、解決したstorageなのかもEvidenceに残す。

### 7.3 IDと内容バージョンを分離

`EntityID`を行番号や本文ハッシュだけで生成してはいけない。

意味解析器のUSR等がある場合は、workspace／module／言語／producer identityを含めて識別する。構文段階では、相対パス、宣言所有、kind、正規化signature、衝突区別と永続identity registryを用いる。

空白や本文だけの変更では可能な限り同じIDを維持する。overload、同名型、別package、extensionを誤って統合しない。rename／moveの対応が一意に確認できない場合は、新IDと明示的な削除・追加として扱い、古い結果を流用しない。

意味解析後に構文ノードを照合するときも、一意の根拠がある場合だけalias mapを作成する。曖昧な対応を確定しない。

内容の変更は別の`entityRevision`で扱う。ソース、依存する宣言、ビルド設定、Provider版はキャッシュkeyと適用判定に含める。

### 7.4 SourceAnchor

workspace-relative path、元ソースのdigest、UTF-8 byte offsetによる半開区間を正準表現とする。UI用line／columnは1-basedでencodingを明示する。LSPの0-based／UTF-16等はProvider境界で変換する。

Unicode、CRLF、絵文字、結合文字、空ファイルのテストを持つ。本文がないartifactでは範囲だけを捏造しない。位置が不明ならnullと理由を返す。

### 7.5 3軸の状態

| 軸 | 値の例 |
|---|---|
| 根拠 | syntax、semantic、designDeclared、runtimeObserved、externalReported |
| 鮮度 | current、pending、stale、unknown |
| 完全性 | completeWithinScope、partial、unsupported、failed、truncated |

「意味解決済み」は「実際に必ず呼ばれる」や「正しい」を意味しない。「current」は入力fingerprintが対象と整合する意味であり、証明済みを意味しない。

`completeWithinScope`には必ず宣言したscope、除外、ビルド構成、能力を付ける。全プログラムについての完全性を暗黙に主張しない。

### 7.6 Factの所有と削除

各Factはproducerとscopeに所属する。再解析時は同一producer／scopeの前回結果をtransactionで置換する。構文Providerが意味Providerや設計設定のFactを削除してはいけない。

解析失敗では、前回結果を最新の空集合に置換しない。last-known-goodをstaleとして残し、現世代の失敗と不完全性を登録する。正しく解析して存在しないことを確認できた場合にだけ削除Factを確定する。

### 7.7 外部形式

`Schemas/architecture-ir.schema.json`、`graph-view.schema.json`、`graph-delta.schema.json`、`annotation.schema.json`、`configuration.schema.json`を実装成果物に含める。schema majorが違う入力を黙って読まない。未知の拡張属性は保存できるが、意味が必要な未知のenumを既知の値に置換しない。

### 7.8 整合性・再現性

公開transactionでは、全edgeの端点が存在するか、明示的なexternal／unresolved entityを参照すること。包含関係はその投影内で非循環とし、依存・callの循環と区別する。重複ID、同一IDの異なる意味、異なるworkspaceの無断混在は拒否する。

hashはSHA-256を標準とする。ソースは元のbytesを対象とし、改行やUnicodeを勝手に正規化しない。構造データのdigestには、schemaで定めたkey順・集合の安定sort・UTF-8 encodingの正準シリアライズを使う。hash値、表示名、timestampをidentityの代用にしない。

外部ツールが対象を共有できるよう、`InputManifest`をAPIで取得可能にする。workspace、scope、相対pathとsource digestの一覧、build context、依存lock、関連する設定digest、manifest schema版を含む。digestの比較方式をProducerごとに暗黙に変えない。

同一入力・設定・Provider版の再解析は、意味上同じfactsと診断を生成する。時刻・job ID・一時process IDを除いた正規化比較をテストする。graph viewのsortとpagination順は安定させる。

## 8. Language Frontend

### 8.1 Providerインターフェース

各Providerは少なくとも以下を公開する。

```text
identity: provider名 + バージョン + 言語 + profile
capabilities(context) -> 機能と条件、unsupported理由
analyze(immutable input snapshot, scope, budget) -> facts + evidence + coverage + diagnostics
cancel(jobID)
```

解析結果はGUIやグラフDBを直接変更しない。副作用を隔離し、入力snapshotに紐付く値として返す。結果のcommit可否はIndexer／Serviceが判断する。

### 8.2 高速経路

保存済みファイルを決定論的に解析し、宣言・位置・lexical ownershipを更新する。swift-skeletonはこのProviderの一つとして使う[R1]。

その公開APIから取得できない自由関数や細部を、既存機能として仮定しない。P0でSwift／Rustの実fixtureを確認し、不足は元ソースの構文木から抽出する独立の補助アダプターで埋める。本文の正規表現走査だけで型、呼び出し、CFGを確定することは禁止する。

上流改変を初期導入の前提にしない。構文木にアクセスできるAPI・文法を採用した場合は、その版と対応構文をlockとcapabilityに記録する。

### 8.3 意味解析経路

SwiftはSourceKit-LSP等、Rustはrust-analyzer等のローカルProviderで補強する。実際のserver capabilitiesを確認し、未対応methodを「空の結果」に変換しない。

LSPはCall Graphの完全性を保証するものとして扱わない。definitionが取れたこととcall hierarchyが得られたことは別能力とする。closure、protocol／trait dispatch、dynamic loading、reflectionは必要に応じて候補・未解決を残す。

Providerのビルド／索引更新状況は別に追跡する。SourceKit-LSPは設定・版によってbackground indexingの挙動が変わるため[R5]、応答が返った時刻だけで最新と判定しない。依存入力の整合を確認できなければfreshnessをunknown／staleとする。

### 8.4 プロジェクト構成

実行許可があるworkspaceではSwiftPM／Cargoの公式なmetadata取得経路を利用し、選択target、features、compile defines、platform、toolchain、依存lockを記録する。

manifestの評価や意味解析の準備がユーザーコードを実行し得るため、§20のworkspace trustを先に確認する。未許可状態ではファイル・宣言を表示し、package dependency等を未解決とする。ディレクトリ名から正しいbuild targetを推測しない。

条件コンパイル（Swiftの`#if`、Rustの`cfg`等）は、条件をFactに記録する。active build contextで選択できない場合は、全branchを「実際に有効な依存」として統合しない。macroや生成ソースを取得できない範囲はcoverageに残す。

### 8.5 クロス言語

共通IRに複数言語を載せることと、言語境界の意味を自動解決することを分ける。FFI／RPC／生成binding等は接続情報やProvider根拠がある場合だけ関連付ける。単なる同名関数は結び付けない。手動mappingはdesignDeclaredとして保持する。

## 9. Call Graph・CFG・データフロー

### 9.1 Call Graph

call siteを第一級要素として保持し、caller → callSite → calleeの根拠を残す。図ではcaller → calleeへ集約してよい。

候補が複数なら候補集合、解決不能ならunresolvedSymbol、外部実装ならexternalSymbolを保持する。引数評価中の呼び出し、再帰、overload、別moduleの同名関数を区別する。

`references`を全て`calls`へ変換しない。関数値の取得、型の参照、property access等は別の関係とする。ネットワーク接続先やDI bindingを名前から推測しない。

### 9.2 CFGの必須部分集合

SwiftとRustで、通常の同期関数について以下を必須とする。

- 順次実行、局所宣言・代入・式文、直接call site。
- `if`／`else`、`while`、早期`return`、対象を解決できる`break`／`continue`。
- Swiftの対応する`guard`と、条件のtrue／false分岐。
- entry、normal exit、各basic blockと元ソース範囲。

条件は元式と根拠範囲として持ち、実際に実行可能かは推論しない。短絡演算などで制御が変わる場合は明示的にモデル化するか、その関数を未対応／partialとする。演算子のoverloadやcallの副作用を勝手に消去しない。

`defer`、例外・unwind、`await`、coroutine、macro展開、Rustの`?`、複雑なpattern matching等は、対応規則とテストがない限りcomplete CFGに含めない。未知の文を素通りするedgeを作らず、opaque regionと不完全性を表示するか、その関数のCFG生成をunsupportedとする。

CFGは構造的な制御フローであり、経路の充足可能性・状態空間・安全性の証明ではない。TLA+の状態遷移図と同一視しない。

### 9.3 詳細解析の実行時期

全関数のCFGを起動時に生成しない。関数選択、CLI `cfg`、上位ツールの要求でオンデマンド生成する。キャッシュは関数本文だけでなく、必要な解析profileと依存情報を含めて無効化する。

SIL入力Providerを後で追加してよいが、SIL生成は通常の構造表示の前提にしない。swift-formalのパーサを依存経由で取り込まない。

### 9.4 データフロー等

v1は型・参照・対応できるreads／writesを中心とする。値の由来、heap alias、ネットワークや永続化まで含む完全なデータフローは必須ではない。取得可能なものだけ、scopeと精度付きで表示する。

実行トレース、状態遷移、証明グラフは外部部分グラフとして表示可能にするが、Explorer自身で探索・証明しない。

## 10. 差分更新・世代管理

### 10.1 3つの時点

| 時点 | 意味 |
|---|---|
| DesiredRevision | 監視で把握した、ユーザーが現在編集している入力 |
| PublishedSnapshot | GUI／CLIへ公開した構造と根拠の集合 |
| ProducerRevision | 各解析器が実際に処理した入力version vector |

一つの「更新日時」だけで全情報の鮮度を表現しない。新しい構文と古い意味情報を併記できるが、古い情報をcurrentと表示しない。

### 10.2 更新手順

```text
ファイルイベント
  → 対象をdirty化しDesiredRevisionを更新
  → 関連する古い根拠をstale化して通知
  → 250 msを初期値とするdebounce／同一対象のイベント統合
  → immutableな入力snapshotを採取
  → 高速構文解析を実行
  → producer／scope単位でatomic commit
  → 表示中Viewを無効化／差分更新
  → 必要な意味解析・CFGを別ジョブで実行
  → 入力がまだ一致する結果だけ現世代へcommit
```

監視通知は欠落・重複し得るものとして設計する。起動時、overflow、directory rename、ブランチ切替、休止復帰ではreconciliation scanを行い、保存済みの内容digestと比較する。

### 10.3 無効化

本文だけの変更、signature変更、module追加、依存lock変更、features／defines変更、Provider更新を区別する。

本文だけでもcallerの意味解析に影響しないと常に仮定しない。Providerの依存関係とバージョン情報で限定できるときだけ範囲を狭める。不明ならファイル／module単位に広げる。

構造上の影響候補は返してよいが、それを上位検証ツールの再検証要否の完全な証拠としない。

### 10.4 古い結果の扱い

ジョブにはinput fingerprintとgenerationを付ける。新しい変更後に届いた旧ジョブは、入力の依存閉包が一致すると確認できない限り現世代へ採用しない。キャンセルに間に合わない結果は履歴／cacheへ置くか破棄する。

providerが入力snapshotを固定できず、編集中のファイルを混在して読んだ可能性がある場合は、意味情報の鮮度をunknownとする。静かな時間に完了したことだけで一致を認定しない。

### 10.5 優先度と負荷

優先度は、ユーザーの表示操作 → 表示対象の構文 → 変更ファイルの構文 → 表示対象の意味情報／CFG → 周辺意味解析 → 全体reconciliationを基本とする。

worker数、CPU／メモリ、外部process、応答サイズ、実行時間に予算を設ける。timeoutはempty resultではなく診断付きpartial／failed。UIを重いジョブの完了待ちにしない。

未保存バッファ対応を将来追加する場合、disk snapshotとeditor session／document versionを別の入力branchとして保持する。他の利用者に未保存内容を混ぜない。

## 11. 保存・キャッシュ・整合性

### 11.1 永続化

v1の保存実装はSQLiteを基本とし、transactionによる更新と読み取りsnapshotを提供する。最低限entities、facts、evidence、snapshots、coverage、diagnostics、annotations、identity map、view settingsを索引する。

全文ソースの恒久保存は既定で行わない。解析中の入力は必要な期間だけ保持し、cache／snapshotの保持量と削除方針を設定可能にする。古いソースを表示できない場合は、その事実を返す。

### 11.2 キャッシュkey

入力bytes／content digest、module context、build config、依存lock、Provider identity/version、解析profile、schema version、関連するdesign configを含む。

表示cacheはsnapshot、query、フィルター、集約、layout versionで識別する。見た目だけの変更でソース解析をやり直さない。ソース変更をlayoutだけの変更として隠さない。

### 11.3 再起動・破損

起動直後はcacheを表示してよいが、diskとの照合前はstale／checkingとする。DBのschema migrationに失敗したら退避・再構築を案内し、失敗を無視して別の意味で解釈しない。

daemon強制終了、書き込み中断、外部プロセス異常終了後も、半分だけのsnapshotを公開しない。cache再構築は入力ソースや設定を変更しない。

## 12. Graph Query API

GUI／CLI／MCPは同じquery serviceを利用する。全グラフを毎回JSON化して渡す設計は禁止する。

### 12.1 必須問い合わせ

| API | 内容 |
|---|---|
| `workspace.status` | generation、dirty範囲、能力、解析進捗、診断 |
| `graph.overview` | 指定階層の集約図 |
| `graph.children` | 包含／design groupの子と件数 |
| `graph.node` | node詳細と根拠 |
| `graph.neighbors` | edge種別・方向・depthを指定した周辺 |
| `graph.search` | 名前、kind、言語、責務、source path |
| `graph.path` | 表示対象の関係を用いた経路。実行経路とは限らない |
| `graph.impact` | 記録された依存上の影響候補と不完全性 |
| `graph.cfg` | 対応関数のCFG。未取得ならjobと状態 |
| `graph.diff` | 同じworkspaceの2 snapshot間の変化 |
| `graph.explain` | 選択node／edgeの根拠付き定型説明 |
| `graph.evidence` | source anchors、Provider、範囲、前提 |
| `graph.annotations` | 外部結果と適用状態 |
| `graph.capabilities` | 言語／Provider／機能別の対応 |

`graph.explain`は既存factsからのテンプレート出力とする。LLMへの通信、未記録の責務説明、推測による根拠補完は行わない。

### 12.2 共通レスポンス

```json
{
  "schemaVersion": "1.0",
  "workspaceID": "workspace-example",
  "snapshotID": "snapshot-42",
  "queryID": "query-example",
  "freshness": "current",
  "completeness": "partial",
  "coverage": {
    "scope": "module:Auth",
    "unresolvedRelations": 2,
    "excludedScopes": ["external-dependency-bodies"]
  },
  "data": { "nodes": [], "edges": [] },
  "truncated": false,
  "nextCursor": null,
  "diagnostics": []
}
```

空配列は例示であり、上のpartialな応答から「依存がない」と結論してはいけない。実応答では未解決の詳細へ参照できること。

### 12.3 ページングと予算

snapshotに固定したcursorを使用する。page取得中に世代が変わっても、ページ間で異なる集合を混ぜない。snapshotが失効したら`SNAPSHOT_EXPIRED`を返して再取得させる。

既定は最大500 nodes／1500 edges／深さ2、応答4 MiBを上限とする。検索既定50件、最大200件。過大要求は制限値とともに拒否または明示的truncateし、黙って途中を落とさない。

集約件数は「取得済みだけの件数」か「scope内の全件数」かを区別する。全件数を計算していない場合はunknownとする。

## 13. 差分購読プロトコル

### 13.1 データと表示を分離する

グローバルには`inputInvalidated`、`factsCommitted`、`analysisStatusChanged`、`annotationChanged`を通知する。表示中のview購読には、そのqueryに対応するpatchまたは`viewInvalidated`を送る。

初回はsnapshot＋viewを取得し、そのsnapshot以降を購読する。snapshot取得と購読開始の間の更新を取りこぼさないよう、再送可能なsequence／resume tokenを発行する。

### 13.2 Patch

```json
{
  "schemaVersion": "1.0",
  "type": "viewPatch",
  "workspaceID": "workspace-example",
  "streamEpoch": "epoch-example",
  "sequence": 104,
  "queryID": "query-example",
  "baseSnapshotID": "snapshot-42",
  "targetSnapshotID": "snapshot-43",
  "upsertNodes": [],
  "removeNodeIDs": [],
  "upsertEdges": [],
  "removeEdgeIDs": [],
  "coverageChanged": true
}
```

patchはatomicに適用する。途中のdangling edgeを見せない。base mismatch、sequence gap、epoch変更、history期限切れでは`resyncRequired`とする。クライアントは同じqueryの新snapshotを取得する。

遅いクライアントのqueueを無制限に増やさない。連続patchはcoalesceし、上限超過時は最終世代への再同期を要求する。WebSocket切断中の図には「接続なし／古い可能性」を表示する。

## 14. Web GUI

### 14.1 表示構成

```text
┌ workspace / snapshot / live状態 / search ───────────────┐
│ Navigator       │ Graph / CFG               │ Inspector │
│ system          │                          │ role      │
│  module         │ 階層の展開・縮約          │ source    │
│   component     │ 部分グラフ               │ evidence  │
│    function     │                          │ callers   │
├─────────────────┴──────────────────────────┴───────────┤
│ 解析進捗・診断・未解決数・外部結果・snapshot差分       │
└───────────────────────────────────────────────────────┘
```

初期画面はL1／L2。全nodeを先にブラウザへ送らない。展開対象と周辺依存だけを要求する。

### 14.2 必須操作

展開／折りたたみ、drill-down／戻る、パン／ズーム／fit、focus、検索、関係の方向・種別・言語・根拠での絞り込み、循環の表示、根拠への移動、snapshot diff、現在viewのexport。

更新によって選択node、展開状態、ズーム、固定位置を無条件にリセットしない。削除された選択対象は消えた理由を示し、最寄りの有効な祖先に移れるようにする。

Source inspectorは範囲限定で取得する。ソースを開く操作はread-only。外部エディタを起動するときは固定した引数配列を使い、ソース由来の文字列をshell commandにしない。

### 14.3 レンダリング

v1はSwiftWeb＋SwiftHTMLで配信するページシェルと、同梱JavaScriptのグラフUIで構成する。Swift WASMは初期必須にしない。SwiftWebUIを使う場合も、このグラフ描画境界を維持する。

Cytoscape.jsをRenderer Adapterの背後に置く。ELK.jsはWeb Worker上で配置計算する。レイアウト結果にはquery／snapshot／request世代を付け、遅れて返った旧配置で新しい図を上書きしない。

通常描画はnode上限で制御する。巨大な集合は集約nodeと件数で示す。WebGLへの変更は将来可能だが、IR契約やqueryの意味を変えない。

### 14.4 状態表示

色だけで区別せず、syntax／semantic／declared、current／stale、partial／unsupportedをテキスト・アイコン・詳細で確認できるようにする。解析成功を「安全」「証明済み」と表示しない。

外部結果の表示は、例えば「外部Provider報告：PROVED／対象入力一致／指定ケースのみ」とする。Explorer自身の保証に読み替えない。

GUIの文言・labelはplain textとしてescapeする。source comment、node name、Annotationに含まれるHTML／scriptを実行しない。

### 14.5 アクセシビリティ

キーボードによる選択・階層移動、検索focus、色に依存しない状態、Inspectorのテキスト情報、グラフと同じ内容の一覧表示を用意する。図だけに情報を閉じ込めない。

## 15. CLI

以下はこれから実装する公開契約であり、現時点で存在するコマンドの説明ではない。

```bash
# 明示的に設定ファイルを作る。既存ファイルを上書きしない
architecture init --workspace .

# 一度解析し、機械可読な結果を取得
architecture index --workspace . --format json

# 常駐し、必要なWebホストを起動してブラウザを開く
architecture explore --workspace . --watch

# ブラウザを自動で開かずURL等を取得
architecture explore --workspace . --watch --no-open

# 上位構成図
architecture graph --workspace . --view hierarchy --level module --format mermaid

# node IDはsearchから取得する
architecture search --workspace . --query AuthService --format json
architecture graph --workspace . --view calls --focus <node-id> --depth 2 --format json
architecture cfg --workspace . --symbol <node-id> --format json
architecture explain --workspace . --entity <node-id> --format json
architecture diff --workspace . --from <snapshot-id> --to <snapshot-id> --format json

# 解析の対応範囲と鮮度。証明coverageではない
architecture status --workspace . --format json
architecture capabilities --workspace . --format json
architecture coverage --workspace . --format json

# 表示／共有
architecture export --workspace . --view hierarchy --format html --out architecture.html
architecture export --workspace . --view hierarchy --format json --out architecture-graph.json

# MCPはstdio専用出力で起動
architecture mcp --workspace .

# daemon管理
architecture daemon start --workspace .
architecture daemon status --workspace .
architecture daemon stop --workspace .

# 環境・設定・依存状態を点検
architecture doctor --workspace . --format json
```

`architecture check`／`verify`／`prove`や、形式検証を自動起動する引数は追加しない。

### 15.1 共通挙動

`--workspace`省略はcwd。設定は明示path → workspaceの`architecture.json` → builtin defaultの順。入力として正しくない引数を無視しない。`--help`と`--version`を必須にする。

stdoutは要求されたデータ、stderrはログ。JSONモードに進捗表示を混ぜない。`explore --watch`は通常foregroundで持続し、Ctrl-Cで当該セッションとWeb helperを終了する。共有daemonは他セッションが使用中なら止めない。Web helperを含めた所有プロセス以外をkillしない。

既存daemonを利用するときも、要求したworkspace／contextと一致するか確認する。複数contextは明示的に区別する。

### 15.2 終了コード

| code | 意味 |
|---:|---|
| 0 | 要求を正常処理。解析の完全性はレスポンスで別途示す |
| 2 | 引数・設定・schema不正 |
| 3 | 未対応の要求／必要なProvider・Web helper不在 |
| 4 | 入力読み取りまたは解析が要求を完了できず失敗 |
| 5 | trust、アクセス、認証・ポリシーによる拒否 |
| 6 | timeout、resource limit、接続不能 |
| 7 | snapshot期限切れ、版不一致、整合性不成立 |
| 130 | ユーザーキャンセル |

`--require-complete`を問い合わせ／exportに用意し、要求scope内でpartial／stale／unsupportedがある場合は非0とする。これは品質保証の合否ではなく、要求された情報が揃わなかったという意味である。

## 16. MCP・エージェント連携

### 16.1 Transportと版

v1のMCPはstdioとする。初期互換profileはMCP 2025-11-25を固定し、その仕様のlifecycle／capability negotiationに従う[R8]。将来版への対応は別profileと実クライアント試験で追加する。「最新の全MCPクライアントに対応」と表示しない。

stdin／stdoutにはプロトコルmessageだけを流す。ログはstderr。内部daemonへの接続はArchitectureClientを共有する。各Agentが独自に全体索引を作らない。

### 16.2 必須tools

`architecture_overview`、`architecture_search`、`architecture_node`、`architecture_neighbors`、`architecture_cfg`、`architecture_impact`、`architecture_diff`、`architecture_evidence`、`architecture_status`、`architecture_capabilities`。

全toolsはread-onlyを基本とする。未取得の解析をscheduleする場合はローカル内部状態のみを更新し、ソース変更、build trust昇格、ネットワーク取得、検証器実行を行わない。

既定返却予算は64 KiB。上限超過を示し、cursorと追加取得方法を返す。source全文の無条件返却は禁止する。根拠として相対path、range、digest、snapshot、evidence IDを返す。

### 16.3 エージェントの探索経路

```text
status / capabilities
  → overview
  → search / children相当のneighbors
  → node / dependencies / callers
  → cfg / evidence
```

巨大なIRを毎回Agentへ読ませない。queryごとのsnapshotと不完全性を失わず、回答の根拠を追跡できるようにする。

MCPクライアントが非対応版の場合は明確な診断で終了する。Claude Code等との実接続確認では、クライアント版、protocol版、問い合わせと出力を試験記録に残す。

## 17. 汎用外部結果の契約

### 17.1 目的

将来の統合検証パッケージ、テストツール、lint、profiler等が結果を関連付けられるようにする。ただし、Explorerはそれらを起動・管理しない。

外部結果は通常のFactとは別namespace／store領域に保存する。外部データから解析済みのedgeを上書きしたり、ノードの意味解決状態を昇格させたりしない。

### 17.2 Annotationの概念例

```json
{
  "schemaVersion": "1.0",
  "id": "annotation-example",
  "provider": {
    "name": "external-tool-example",
    "version": "1.0",
    "runID": "run-example"
  },
  "subject": {
    "workspaceID": "workspace-example",
    "entityIDs": ["entity-example"],
    "snapshotID": "snapshot-42"
  },
  "inputFingerprint": {
    "sourceDigest": "example-source-digest",
    "contextDigest": "example-context-digest",
    "dependencyDigest": "example-dependency-digest"
  },
  "category": "external-analysis",
  "reportedStatus": "PROVED",
  "claim": "外部ツールが検査した命題・対象",
  "scope": "外部ツールが明示する入力・ケース・範囲",
  "assumptions": [],
  "evidence": [],
  "createdAt": "2026-11-16T00:00:00Z"
}
```

値はschema説明用の例であり、実際の証明結果ではない。`reportedStatus`はProviderの文字列であり、Explorer共通の真偽判定enumにはしない。

Explorer側は別に`applicability = matchesInputs | stale | unmatched | unknown`を計算する。digestの一致は対象同定の補助であり、外部結果の正しさを証明しない。依存digestを確かめられなければunknownとする。

### 17.3 APIと版管理

認可されたClientに`annotations.upsert`／`annotations.remove`を公開する。既定のMCP toolsには書き込みを公開しない。Providerごとのnamespace所有権、サイズ、件数、artifact pathを検査する。

外部部分グラフは`extensionGraphs`として取り込めるようにする。表示種別、root、nodes、edges、対象entityへのbinding、入力snapshotを持つ。証明・状態遷移・実行トレースというラベルは外部の分類として保持し、その意味をExplorerが検査したと表示しない。

artifactは許可したroot内の相対pathとdigestで参照する。任意の絶対path、shell命令、HTML script、ブラウザからの自由なファイル読み取りを受け付けない。対応entityが削除された結果はorphanとして履歴に残せるが、別entityへ自動で付け替えない。

### 17.4 上位パッケージに任せるもの

何を証明するか、どの変更で再検証するか、複数結果をどう総合評価するか、CIを通すか、証跡の暗号学的検証、ツールチェーンのインストール。これらの判断はAnnotation APIへ混ぜない。

## 18. エクスポート

### 18.1 形式

| 形式 | 用途と契約 |
|---|---|
| JSON | schema付きIR／query結果。ID、根拠、snapshot、coverageを保存 |
| Mermaid | 指定view／範囲のテキスト図。node IDとsource対応表を併記 |
| SVG | 現在viewのベクター図。描画adapterに依存しないexport sceneから生成 |
| HTML | snapshotと必要なアセットを含む、サーバーなしのread-only viewer |

Mermaid／SVGは意味を保持した元IRへの参照を含める。ラベルをescapeし、Mermaid構文やSVGへのコード注入を防ぐ。

headlessのSVGは、有界な既定配置または保存したExportSceneから生成する。GUIでのexportは現在viewの座標をExportSceneへ変換する。PNGのスクリーンショットをSVGと称しない。

単体HTML用の固定テンプレート・rendererアセットは本体のexport用resourceにも同梱し、`swift-web`やWeb helperのbuild／起動なしで書き出せるようにする。GUIとの共有アセットは同じlock／hashで管理する。通常のCLI起動時にnpmやWASMのビルドを実行しない。

### 18.2 単体HTML

Cytoscape等の必要なJS、style、データを同梱し、`file://`で開いても外部fetchを要求しない。WASM／CDN／ローカルサーバーを必須にしない。画面には「保存済みsnapshot」「取得日時」「liveではない」を明示する。

単体HTMLでも階層移動、検索、zoom、Inspectorを使える。ただし含まれていない下位階層は「未同梱」と表示し、全件があると装わない。実行時の再解析や外部ツールの再実行は行わない。

レイアウト用Workerが`file://`やCSP制約で利用できない場合は、export時の座標か、小さなグラフ向けのboundedなfallbackを使う。無限に再計算しない。

### 18.3 範囲と秘匿

既定exportは表示viewだけ。全workspace出力は明示指定と予算確認を要求する。source全文、絶対path、環境変数、認証情報は既定で含めない。ユーザーが明示したsource snippetだけを必要範囲で含められる。

exportはimmutable snapshotに固定する。出力中に編集されても世代を混ぜない。上書きは既定で拒否し、`--force`を明示した場合だけatomic replacementする。

## 19. 設定

workspaceに`architecture.json`を置く。例：

```json
{
  "schemaVersion": "1.0",
  "languages": ["swift", "rust"],
  "include": ["Sources/**", "src/**", "Packages/**"],
  "exclude": [".git/**", ".build/**", "target/**", "node_modules/**"],
  "analysis": {
    "syntax": true,
    "semantic": "onDemand",
    "cfg": "onDemand",
    "debounceMilliseconds": 250,
    "maxWorkers": 4,
    "maxSourceFileBytes": 5242880
  },
  "views": {
    "initialLevel": "module",
    "maxVisibleNodes": 500,
    "maxVisibleEdges": 1500
  },
  "designGroups": [
    {
      "id": "domain",
      "label": "Domain",
      "description": "設計者が指定するドメイン処理",
      "selectors": [{ "pathGlob": "Sources/Domain/**" }]
    }
  ],
  "externalLinks": []
}
```

これは構成例であり、特定プロジェクトの自動検出結果ではない。

include／excludeはworkspaceの許可範囲内で適用する。未知keyはversion付きのextension以外は診断する。excludeされたコードがある場合はcoverageに残す。designGroupの重複所属を許し、同じ実体をコピーしない。

workspace trust、実行可能ファイルの承認、認証tokenは、リポジトリから供給される設定だけで有効化できない。ユーザー側の別設定に保存する。外部依存のソースは許可した解析rootだけを参照する。

## 20. 安全性・ローカル運用

### 20.1 workspace trust

初回はread-onlyのfilesystem／syntax解析のみを許可する。SwiftPM manifest評価、Cargoの準備、build script、proc macro、SourceKit-LSP等のbackground preparation、プラグイン実行は、workspaceの明示承認後に限る。

CLIの`--trusted-workspace`またはGUIの権限確認で、実行し得るprocess／build作業を説明し、承認をroot identityに結び付ける。リポジトリ内設定やAgentのtool引数だけで恒久trustを上げない。

trustがない状態でも構造GUIは開く。未取得のmodule／call情報には理由を表示する。未導入toolの自動download、package解決の暗黙ネットワーク利用はしない。依存取得を伴う操作は別の明示許可とする。

### 20.2 ネットワークと認証

Webホストは既定で`127.0.0.1`と自動選択portへbindする。v1は外部interfaceへの公開をサポートしない。

Host／Originを検査し、セッション認証、WS upgradeの認可、書き込み操作のCSRF対策を行う。loopbackであることだけを認証の代わりにしない。

起動tokenは短寿命の一回用とし、クエリ文字列やaccess logに長期資格情報を残さない。ブラウザのsessionはHttpOnly／SameSite等の適切なcookie方針で扱う。ローカルHTTPとHTTPSの属性差をテストする。

Unix socketはユーザー専用directory／permissionで作り、別ユーザーが接続できないようにする。workspaceやannotationの任意pathをURLパラメータから開くAPIは作らない。

### 20.3 プロセス・入力

subprocessはshellを介さずexecutableと引数配列で起動する。入力／出力、timeout、子process、cancel、exit statusを管理する。環境変数は必要なものに限定し、sourceから任意の実行引数を作らない。

symlink、path traversal、大小文字差、root外参照を処理し、許可root外の内容を勝手に収集しない。archiveやHTMLに秘密情報を埋め込まない。

source commentや外部Annotationに書かれた「指示」はデータとして扱う。AI向け出力にも根拠データとして区分し、ツール操作命令へ変換しない。

## 21. 性能・リソース目標

以下は設計・試験の目標であり、実測値や全環境の保証ではない。リリース時には実測機種、OS、toolchain、fixture、cold／warm条件、p50／p95を記録する。

### 21.1 基準負荷

| fixture | 規模 |
|---|---|
| Small | 100 files、10k LOC、1k entities |
| Medium | 1k files、100k LOC、10k entities |
| Large graph | 100k entities、500k edgesの合成IR |
| Large source | 10k files、1M LOC相当。索引時間とmemoryを別測定 |

基準機はApple Silicon、32 GB RAM、SSD。特定機種への最適化を正しさの前提にしない。

### 21.2 目標

| 項目 | 目標／条件 |
|---|---|
| Warm時の小さな1ファイル構文変更 | Medium、2k LOC以下、debounceを含むp95 1秒以内 |
| 既存部分グラフquery | 最大500 nodes／1500 edges、warm p95 200 ms以内 |
| commit後のGUI反映 | 受信側が追従可能な状況でp95 250 ms以内 |
| インタラクション | 上限内の表示でpan／zoomを阻害しない。基準30 fps以上 |
| Large graphの操作 | 全件転送なし。query予算で打ち切り、メモリが無制限に増えない |

cold build、依存解決、意味解析、CFGの複雑度には上記1秒を適用しない。それらは進捗・cancel・状態表示で扱う。根拠を落として速度目標を達成してはいけない。

### 21.3 運用制限

既定source file上限5 MiB、API response上限4 MiB、MCP既定64 KiB、query上限は§12。設定で引き上げる場合もhard limitと警告を設ける。

ログはローテーションし、cache／履歴の容量上限を設定する。解析対象の生成ディレクトリを既定excludeし、自己生成したcacheを監視して無限再解析しない。

## 22. エラーと診断

診断はcode、severity、phase、workspace、snapshot／job、Provider、source range、原因、回復方法を含む。最低限以下を区別する。

```text
UNSUPPORTED_LANGUAGE / UNSUPPORTED_CAPABILITY
SOURCE_PARSE_FAILED / PARTIAL_PARSE
PROJECT_CONTEXT_UNAVAILABLE / WORKSPACE_TRUST_REQUIRED
SYMBOL_UNRESOLVED / AMBIGUOUS_BINDING
STALE_ANALYSIS / INPUT_CHANGED_DURING_ANALYSIS
SNAPSHOT_EXPIRED / RESYNC_REQUIRED
RESOURCE_LIMIT / ANALYSIS_TIMEOUT / ANALYSIS_CANCELLED
WEB_HOST_UNAVAILABLE / TOOLCHAIN_MISMATCH
SCHEMA_MISMATCH / INVALID_GRAPH / ARTIFACT_OUTSIDE_ROOT
```

部分失敗でも他scopeのGUIは利用可能にする。一方、不正schema、scope混在、存在しないnodeへの不正edgeなど、整合性違反のあるtransactionを公開しない。

エラーの発生を「依存なし」「問題なし」「検証済み」と表現しない。

## 23. 実装工程とAgentへの作業指示

### P0：契約・依存の実確認

本書を配置し、root／Web packageの境界、schema、Provider能力、上流依存の固定を実証する。swift-skeletonのSwift／Rustで取得できる宣言をfixtureで確認する。swift-webのhost起動とアセット配信を小さなprobeで確認する。

完成条件：両Packageを独立build可能。本体の依存グラフにswift-webとswift-formalがない。toolchainとdependency lockを記録。構文補助アダプターの選択と根拠をADRへ記録。

### P1：IR・Store・問い合わせ

Entity／Fact／Evidence／Snapshot、SQLite、Graph Query、CLI JSON、外部からのfixture IR取り込みを実装する。GUIより先にqueryと整合性のテストを固める。

完成条件：Swiftに固有な型を必要とせず、合成した複数言語graphを問い合わせ・exportできる。

### P2：ライブ構造解析

Swift／Rust宣言、project model、監視、invalidation、generation、identity対応、daemon共有を実装する。

完成条件：変更・削除・エラー・連続編集・再起動に追従し、旧結果を最新として表示しない。

### P3：Web Explorer

SwiftWeb host、Graph Renderer Adapter、階層GUI、Inspector、patch／再同期、layout worker、read-only source表示を実装する。

完成条件：実コードの変更がページ全体reloadなしで反映される。全グラフをブラウザへ押し込まない。

### P4：意味解析・Call Graph・CFG

Swift／Rustの意味Provider能力、Call Site、unresolved／candidate、限定CFG、contextと依存fingerprintを実装する。

完成条件：対応profileの正例・反例で正しく抽出／拒否し、意味Provider不在でもP2／P3が動作する。

### P5：MCP・Export・外部結果

MCP、JSON／Mermaid／SVG／単体HTML、AnnotationとextensionGraphs、public Client APIを実装する。

完成条件：AgentとGUIが同じsnapshotを問い合わせる。外部結果はmock Providerで試験し、swift-formalを導入しない。

### P6：堅牢化・配布

安全性、負荷、process cleanup、offline、schema migration、受け入れ試験、ドキュメントと配布bundleを完成させる。

作業中は各phaseの実装と実証を分けてPROGRESSへ記録する。stubや固定fixtureの表示だけを製品のライブ解析完成と扱わない。

## 24. 受け入れテスト

以下のIDを実装テスト／E2E／実測記録へ対応付ける。結果はPASS／FAIL／NOT_RUNと根拠を記録する。NOT_RUNをPASSへ読み替えない。

| ID | 試験 | 合格条件 |
|---|---|---|
| AE-001 | formal非依存 | 直接・推移依存と実行processにswift-formal／TLC／Leanがなくても全構造機能が動く |
| AE-002 | 本体のWeb非依存 | root Packageだけをbuild／testし、swift-webを解決しない |
| AE-003 | Web helper分離 | Web未導入時もindex／query／MCPが動き、exploreだけが明確に診断する |
| AE-004 | IR多言語 | SwiftとRustが共通IR／同じqueryとGUIで表示される |
| AE-005 | Provider追加 | mock第三言語を追加してCore／GUIの意味処理を変更しない |
| AE-006 | 階層 | module、nested type、自由関数、extensionを無理な固定深さなしで表示 |
| AE-007 | 設計group | 多重所属と物理包含を区別し、元entityを複製しない |
| AE-008 | 根拠追跡 | node／edge／集約線から元source range・Provider・snapshotへ移動可能 |
| AE-009 | ID維持 | 空白・行挿入・本文変更で同一宣言の識別を可能な範囲で維持 |
| AE-010 | 同名／overload | 別module・別signature・別ownershipを誤統合しない |
| AE-011 | rename曖昧 | 対応が不明なrenameで古いAnnotationを新entityへ移さない |
| AE-012 | Unicode | UTF-8／LSP位置変換とCRLFでsource範囲が正しい |
| AE-013 | Fact所有 | 構文更新が意味Provider／設計groupのFactを消さない |
| AE-014 | parse失敗 | last-known-goodをstale化し、空の最新graphへ置換しない |
| AE-015 | 削除 | 削除確定時は関連edge／集約／検索を整合的に更新 |
| AE-016 | 監視欠落 | event overflowとbranch切替後のreconciliationで追い付く |
| AE-017 | 旧ジョブ競合 | A解析中にBへ編集し、A完了がBを上書きしない |
| AE-018 | context変更 | toolchain、features、defines、依存lockの変更で必要なcacheを無効化 |
| AE-019 | index整合 | incremental結果が同一入力のfresh rebuildと意味上同じになる |
| AE-020 | 世代の併記 | 最新構文と旧意味情報を区別して表示・queryする |
| AE-021 | 再起動 | cacheを即時表示してもdisk照合前はcurrentとしない |
| AE-022 | DB中断 | 強制終了後に半端なsnapshotを公開しない |
| AE-023 | daemon共有 | GUI、CLI、複数MCPからの接続で全体索引を重複起動しない |
| AE-024 | 起動race | 同時起動からdaemonが1つに収束し、他workspaceを止めない |
| AE-025 | query予算 | 上限超過がtruncated／cursor／診断に反映される |
| AE-026 | pagination | snapshot固定で重複・欠落なし。期限切れを検出 |
| AE-027 | 集約 | 上位edgeの件数・種類・元edgeへの展開が一致 |
| AE-028 | cycle | 循環を表示でき、探索が停止し、元edgeが残る |
| AE-029 | call site | referenceとcallを区別し、caller／callee／位置を追跡 |
| AE-030 | dispatch未解決 | protocol／trait／closureの未確定先を直接callと捏造しない |
| AE-031 | 意味Provider不在 | 構文GUIが動作し、意味情報未取得を表示 |
| AE-032 | CFG正例 | 両言語で順次、if、while、return、break／continueとSwift guardが正しい |
| AE-033 | CFG未対応 | defer／async／例外／未対応演算を無視してcompleteにしない |
| AE-034 | CFGとSTGの区別 | CFGを到達可能状態・形式保証として表示しない |
| AE-035 | 表示範囲 | 大規模fixtureで全graphを初期転送せず、展開時に取得 |
| AE-036 | UI保持 | 更新後もfocus／zoom／展開状態を維持し、削除を説明する |
| AE-037 | layout競合 | 旧Worker応答が新queryの配置を上書きしない |
| AE-038 | patch正常系 | snapshot＋patchの結果が同じ世代のfresh viewと一致 |
| AE-039 | patch欠落 | gap／base mismatch／再接続でresyncして復旧 |
| AE-040 | backpressure | 遅いclientのqueueが有界で、切り捨てを明示 |
| AE-041 | GUIアクセシビリティ | キーボード操作、一覧代替、色以外の状態判別が可能 |
| AE-042 | CLI契約 | help、JSON stdout、stderr、引数、終了codeが仕様と一致 |
| AE-043 | MCP実接続 | 対応版clientでtool取得・query・cancel・shutdownが正常 |
| AE-044 | Agent予算 | MCP上限と根拠を返し、巨大JSONやsource全件を強制しない |
| AE-045 | JSON交換 | schema版を検査し、export／importで保持対象を失わない |
| AE-046 | Mermaid／SVG | label injectionを防ぎ、表示範囲と元IDを追跡できる |
| AE-047 | 単体HTML | ネットワーク禁止・サーバーなしでfileから開ける |
| AE-048 | exportの世代 | export中の編集で入力世代を混ぜず、liveと表示しない |
| AE-049 | 外部Annotation | mock結果を関連付け、Providerの状態・命題・前提を保つ |
| AE-050 | 外部結果の鮮度 | 入力や依存が変わればstale／unknownとなり、保証を移植しない |
| AE-051 | 外部部分graph | 名前空間を隔離し、元構造のFactsを上書きしない |
| AE-052 | trust未承認 | manifest／build script／proc macro／背景buildが実行されない |
| AE-053 | loopback安全性 | 異なるOrigin、Host、未認証HTTP／WSを拒否 |
| AE-054 | path安全性 | traversal／symlink／外部artifactで許可rootを越えない |
| AE-055 | 出力安全性 | source名・comment・Annotationのscriptを実行しない |
| AE-056 | offline | インストール済みで通常操作にCDN／telemetry／自動取得がない |
| AE-057 | リソース制限 | 大ファイル、timeout、悪性入力、cancelで有界に終了 |
| AE-058 | 性能実測 | §21の条件とp50／p95／memoryを記録し、未達を隠さない |
| AE-059 | 所有process cleanup | Ctrl-C／異常終了で所有processを回収し、他sessionを壊さない |
| AE-060 | 責務回帰 | 実装・help・依存・テストに検証総合判定やformal自動起動が混入しない |

## 25. 実装成果物と完成条件

実装担当は最低限、以下を納品する。root Packageは`ArchitectureIR`、`ArchitectureGraph`、`ArchitectureClient`、`ArchitectureService`等の必要なライブラリ製品と、実行製品`architecture`を公開する。Web Packageは実行製品`architecture-web`とWeb用ライブラリを公開し、上位統合パッケージがCLI内部をコピーせずに合成できるようにする。公開製品一覧とABI／schemaの変更方針をREADMEに記録する。

```text
ArchitectureExplorer/
├── Package.swift / Package.resolved
├── Sources/                         # Core、IR、解析、Store、Service、CLI等
├── Apps/ArchitectureExplorerWeb/
│   ├── Package.swift / Package.resolved
│   ├── Sources/
│   └── WebAssets/                   # 固定したJS・style・license
├── Schemas/                         # IR、view、delta、annotation、config
├── Fixtures/                        # Swift、Rust、multi-language、異常系
├── Tests/                           # unit、integration、CLI、browser、負荷
├── Tools/                           # build、配布、timeout付きtest
├── Documentation/
│   ├── SPEC.md                      # 本書
│   ├── ARCHITECTURE.md
│   ├── CLI.md
│   ├── FRONTENDS.md
│   ├── PROTOCOL.md
│   ├── SECURITY.md
│   ├── PERFORMANCE.md
│   ├── VERIFICATION.md              # 製品試験記録。コードの形式保証ではない
│   └── ADR/
├── README.md
├── AGENTS.md
├── PROGRESS.md
└── toolchain.lock.json / dependency-lock.json
```

製品の完成条件は、実際のSwift／Rustプロジェクトを変更しながら、CLI／MCP／GUIが同じ情報を参照し、v1範囲の関係とCFGを根拠付きで探索できること。mock graphだけの画面、未接続のMCP定義、stubのwatchで完成扱いにしない。

`architecture explore --workspace . --watch`の起動で、インストール済みのWeb helperと必要なアセットを使う。開発用の`sweb dev`やNode／npmのインストールを一般利用者の毎回の起動条件にしない。

配布はCLI、必要なresource、Web helper、Webアセット、licenseをまとめる。コード署名／公証／公開は別の明示された作業とし、実施したものだけ記録する。GUI build失敗をheadlessの解析失敗と混同しない。

## 26. 最終的な設計判断

- **ArchitectureExplorerは独立した構造探索基盤。swift-formalを依存に加えない。**
- **swift-webはWeb層で採用し、headless本体とはmanifest／processの境界も分ける。**
- **swift-skeletonは構造情報のProviderとして再利用し、意味解析やCFGの完全な代替にしない。**
- **ArchitectureIRは実行意味のFormalIRと別物。JSON／storeがデータ基盤、Mermaid等は表示・交換物。**
- **更新は常駐・差分・段階的。各事実に入力世代と根拠を保持する。**
- **すべてをまとめて検証する機能は、これらを利用する上位パッケージへ置く。**

---

## 付録A：確認した外部資料

以下は2026-11-16に確認した資料。設計のMUSTは本書が定め、資料は外部ライブラリの現状や採用根拠を示す。ArchitectureExplorerとの統合build／性能試験は本仕様作成時点では行っていない。

### [R1] swift-skeleton：README、Trust boundary、公開Library使用例

参照commit：`fb10ef666a30e892b9f3a4ca0740702c6c621d80`。宣言抽出、複数言語、本文非保持、意味解決・正しさの保証対象外を確認した。

`https://github.com/1amageek/swift-skeleton/blob/fb10ef666a30e892b9f3a4ca0740702c6c621d80/README.md`

### [R2] SwiftWeb：README

参照commit：`6edadb6cfa92e3a4b26a1e669329be38f45212f4`。server-rendered HTML、optional browser runtime、SwiftHTML／SwiftWeb／SwiftWebUIの分担を確認した。

`https://github.com/1amageek/swift-web/blob/6edadb6cfa92e3a4b26a1e669329be38f45212f4/README.md`

### [R3] SwiftWeb：Package.swift

同commit。tools 6.4、macOS 26.2、公開host製品、manifestの依存解決境界を確認した。

`https://github.com/1amageek/swift-web/blob/6edadb6cfa92e3a4b26a1e669329be38f45212f4/Package.swift`

### [R4] SwiftWeb：Toolchain契約

同commit。既定snapshotと明示的な公式Swift 6.4.0のhost／WASM SDKの組を区別している。READMEの既定snapshot説明だけから、他の組も自由に混在可能と判断しない。

`https://github.com/1amageek/swift-web/blob/6edadb6cfa92e3a4b26a1e669329be38f45212f4/docs/Toolchain.md`

### [R5] SourceKit-LSP：Background Indexing

公式資料はSwift 6.1以降の既定有効化と、無効時の索引制約を説明する。Explorerは実際の版・設定と入力整合を観測する。

`https://github.com/swiftlang/sourcekit-lsp/blob/main/Documentation/Enable%20Experimental%20Background%20Indexing.md`

### [R6] Cytoscape.js

グラフのJSON表現、compound node、操作・layout・rendererの公開API。

`https://js.cytoscape.org/`

### [R7] ELK.js

階層型の配置とWorker利用の公開実装・説明。実装時にversionとlicenseを固定する。

`https://github.com/kieler/elkjs`

### [R8] MCP 2025-11-25 Transport仕様

この版のstdioのJSON-RPC framing、stdout／stderr分離とtransport契約。本書はこれを初期互換profileとして選択し、最新の全protocol版への自動互換を主張しない。

`https://modelcontextprotocol.io/specification/2025-11-25/basic/transports`

### [R9] rust-analyzer：機能／architecture

言語の意味解析・IDE問い合わせの参考。実際に利用できるcall hierarchy等は、導入版のcapabilityとfixtureで確認する。

`https://rust-analyzer.github.io/book/features.html`

`https://rust-analyzer.github.io/book/contributing/architecture.html`

## 付録B：履歴

| 版 | 日付 | 内容 |
|---|---|---|
| 1.0 | 2026-11-16 | ArchitectureExplorer独立仕様を新規作成。formal非依存、Webビルド分離、IR／差分更新／GUI／CLI／MCP／汎用外部結果を規定 |
