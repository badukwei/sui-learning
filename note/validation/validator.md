# Sui Validator 深度解析

本文件詳細說明 Validator 節點的內部架構、元件組成、交易處理流程，以及對應的程式碼位置。

---

## 目錄

1. [Validator 是什麼](#validator-是什麼)
2. [交易完整時間軸](#交易完整時間軸)
   - [T0 — 用戶端構建交易](#t0--用戶端構建交易)
   - [T1 — Fullnode 轉發交易](#t1--fullnode-轉發交易)
   - [T2 — Validator 接收與本地驗證](#t2--validator-接收與本地驗證)
   - [T3 — 提交到共識引擎](#t3--提交到共識引擎)
   - [T4 — Mysticeti 共識投票](#t4--mysticeti-共識投票)
   - [T5 — 共識排序與 Commit](#t5--共識排序與-commit)
   - [T6 — 共識輸出處理](#t6--共識輸出處理)
   - [T7 — 排程與執行交易](#t7--排程與執行交易)
   - [T8 — 寫入結果與通知用戶端](#t8--寫入結果與通知用戶端)
   - [T9 — 打包成 Checkpoint](#t9--打包成-checkpoint)
   - [T10 — Checkpoint 認證與全網同步](#t10--checkpoint-認證與全網同步)
3. [啟動流程](#啟動流程)
4. [核心元件架構圖](#核心元件架構圖)
5. [元件詳解](#元件詳解)
   - [ValidatorService — gRPC 服務層](#1-validatorservice--grpc-服務層)
   - [ConsensusAdapter — 共識提交器](#2-consensusadapter--共識提交器)
   - [ConsensusManager — 共識管理器](#3-consensusmanager--共識管理器)
   - [SuiTxValidator — 共識交易驗證器](#4-suitxvalidator--共識交易驗證器)
   - [ConsensusHandler — 共識輸出處理器](#5-consensushandler--共識輸出處理器)
   - [AuthorityState — 狀態與執行引擎](#6-authoritystate--狀態與執行引擎)
   - [CheckpointBuilder — Checkpoint 建構器](#7-checkpointbuilder--checkpoint-建構器)
6. [Epoch 生命週期](#epoch-生命週期)
7. [關鍵原始碼索引](#關鍵原始碼索引)

---

## 交易完整時間軸

以下按照嚴格的時間順序，描述一筆交易從用戶發起到全網同步的完整流程。

> **注意**：用戶端對 Validator 發起的是**兩個獨立的 gRPC 呼叫**：
> 1. `submit_transaction` — 提交交易（T2 觸發）
> 2. `wait_for_effects` — 等待結果（T2 之後立即發起，在 T8 被喚醒回傳）

```
時間軸總覽

T0   用戶端構建交易並簽名
T1   Fullnode 轉發交易給多個 Validator
T2   Validator 接收交易，本地驗證，回傳 ConsensusPosition（座位號碼）
     ↓ 同時用戶端發起 wait_for_effects（持續等待中...）
T3   ConsensusAdapter 將交易提交到 Mysticeti 共識引擎
T4   所有 Validator 的 SuiTxValidator 對交易投票（接受/拒絕）
     → 2/3 接受 → FastpathCertified（暫時性確認，通知用戶端但非最終）
T5   Mysticeti DAG 排序 → Linearizer 線性化 → CommittedSubDag 產出
T6   ConsensusHandler 處理共識輸出（過濾、去重、分配 shared object 版本號）
     → 設定狀態為 Finalized
T7   ExecutionScheduler 排程 → ExecutionDriver 平行執行交易
T8   AuthorityState 透過 Move VM 執行 → 寫入 Effects 到 DB → 通知用戶端
     ↑ wait_for_effects 在此被喚醒，回傳結果給用戶
T9   CheckpointBuilder 打包已執行的交易成 Checkpoint
T10  CheckpointAggregator 收集 2/3 簽名 → Certified Checkpoint → 全網同步
```

---

### T0 — 用戶端構建交易

**誰**：用戶（錢包 / SDK）
**做什麼**：構建 `TransactionData`，用私鑰簽名

```
用戶端
  │
  ├─ 構建 TransactionData（指定要操作的物件、呼叫的函式、gas 等）
  ├─ 用私鑰簽名
  └─ 透過 JSON-RPC 或 gRPC 送出
```

此時交易還沒進入任何節點。

---

### T1 — Fullnode 轉發交易

**誰**：Fullnode 的 `TransactionOrchestrator` + `TransactionDriver`
**做什麼**：收到用戶的交易後，平行轉發給多個 Validator
**程式碼**：`crates/sui-core/src/transaction_orchestrator.rs`、`crates/sui-core/src/transaction_driver/mod.rs`

```
Fullnode (TransactionOrchestrator)
  │
  ├─ 判斷交易類型：
  │   ├─ SingleWriter（only owned objects）
  │   └─ SharedObject（涉及 shared objects）
  │
  └─ TransactionDriver 平行送給多個 Validator
      ├─→ Validator A
      ├─→ Validator B
      └─→ Validator C
```

Fullnode 不執行交易，只做路由。

---

### T2 — Validator 接收與本地驗證

**誰**：Validator 的 `ValidatorService`
**做什麼**：接收交易、本地預先驗證、回傳 `ConsensusPosition`
**程式碼**：`crates/sui-core/src/authority_server.rs` — `handle_submit_transaction_inner()`

```
ValidatorService::submit_transaction()
  │
  ├─ 1. bcs::from_bytes::<Transaction>()        反序列化
  ├─ 2. transaction.validity_check()             格式合法性
  ├─ 3. state.check_system_overload()            系統過載檢查
  │     → 過載時回傳 Rejected，交易到此結束
  ├─ 4. epoch_store.verify_transaction()         簽名驗證
  ├─ 5. state.handle_vote_transaction()          【本地預先驗證】
  │     ├─ 檢查 epoch 是否仍在接受交易
  │     ├─ 檢查交易是否已執行過
  │     └─ 驗證 owned object 版本號
  │     （只有收到交易的這個 Validator 做，目的是擋掉明顯無效的交易）
  ├─ 6. 包裝成 ConsensusTransaction
  └─ 7. 提交到 ConsensusAdapter（進入 T3）
        → 立即回傳 ConsensusPosition 給用戶端
```

**同時**：用戶端收到 `ConsensusPosition` 後，立刻發起第二個 RPC `wait_for_effects`。
這個呼叫會**一直等著**，直到 T8 交易執行完畢才被喚醒。

`wait_for_effects` 內部用 `tokio::select!` 同時監聽兩條路徑：
- 路徑 1：DB 中 Effects 被寫入（T8 觸發）
- 路徑 2：`ConsensusTxStatusCache` 的狀態變化（T4/T6 觸發）

哪條先完成就回傳哪個。

---

### T3 — 提交到共識引擎

**誰**：`ConsensusAdapter` → `LazyMysticetiClient`
**做什麼**：將交易序列化後送入 Mysticeti 共識引擎
**程式碼**：`crates/sui-core/src/consensus_adapter.rs`、`crates/sui-core/src/mysticeti_adapter.rs`

```
ConsensusAdapter::submit_batch()
  │
  ├─ 取得 semaphore permit（限制同時提交數量，防止過載）
  ├─ 如果失敗 → 指數退避重試（常見於 epoch 切換時）
  │
  └─ LazyMysticetiClient::submit()
      └─ bcs 序列化交易 → client.submit(transactions_bytes)
         → 交易進入 Mysticeti 的待處理佇列
```

此時交易已離開 Sui 層，進入共識層。

---

### T4 — Mysticeti 共識投票

**誰**：所有 Validator 的 `SuiTxValidator`（在 Mysticeti 引擎內部被呼叫）
**做什麼**：每個 Validator 各自對交易投票接受或拒絕
**程式碼**：`crates/sui-core/src/consensus_validator.rs`

Mysticeti 的 DAG 結構就是一個「邊廣播邊投票邊排序」的設計，不需要先收集齊所有人再統一排序。每個 Validator 持續發出自己的 block（裡面包含新交易 + 對其他人 block 的引用），這些引用關係形成 DAG，最終由 Linearizer 確定順序。

```
Validator A 提出的 block 廣播給所有 Validator
  │
  ▼
每個 Validator 的 SuiTxValidator::vote_transactions()
  │
  ├─ validity_check()                 交易格式合法性
  ├─ check_system_overload()          系統是否過載
  ├─ verify_transaction()             簽名驗證
  └─ 地址別名一致性檢查
  │
  ├─ 驗證通過 → 投票接受
  └─ 驗證失敗 → 投票拒絕，回傳拒絕的交易索引

投票結果聚合：
  ├─ 2/3+ stake 接受 → FastpathCertified（暫時性確認）
  │     → ConsensusTxStatusCache 設定狀態
  │     → wait_for_effects 的路徑 2 可以提前通知用戶端（但這不是最終結果）
  └─ 2/3+ stake 拒絕 → Rejected
        → wait_for_effects 直接回傳 Rejected，交易流程結束
```

**重要**：`FastpathCertified` 是暫時性的。交易被多數投票接受了，但還沒經過共識排序。
後續可能變成 `Finalized`（最終確認）或 `Dropped`（被丟棄）。

---

### T5 — 共識排序與 Commit

**誰**：Mysticeti 共識引擎（`consensus/core/`）
**做什麼**：將 DAG 中的 blocks 線性化，產出確定的交易全序

```
Mysticeti 共識引擎
  │
  ├─ DAG Builder：各 Validator 交換 block，形成 DAG 結構
  ├─ 經過 3 輪通訊，Leader 的 block 被 commit
  ├─ Linearizer：將 DAG 線性化為確定的交易順序
  └─ 輸出 CommittedSubDag（包含已排序的交易列表）
```

到這一步，交易的順序在全網已經確定，不可逆。

---

### T6 — 共識輸出處理

**誰**：`ConsensusHandler`
**做什麼**：接收 `CommittedSubDag`，過濾/去重交易，為 shared objects 分配版本號
**程式碼**：`crates/sui-core/src/consensus_handler.rs`

```
ConsensusHandler::handle_consensus_commit()
  │
  ├─ 1. await_no_backpressure()          等待執行層趕上（背壓控制）
  ├─ 2. filter_consensus_txns()          過濾無效交易
  ├─ 3. deduplicate_consensus_txns()     去重（同一筆交易可能被多個 Validator 提交）
  ├─ 4. build_commit_handler_input()     分類交易：
  │     ├─ user_transactions             用戶交易
  │     ├─ checkpoint_signature_messages  checkpoint 簽名
  │     ├─ randomness_dkg_messages        隨機數 DKG
  │     └─ end_of_publish_transactions    epoch 結束信號
  ├─ 5. process_transactions()           為 shared objects 分配確切版本號
  │     → SharedObjectVersionManager 統一分配
  └─ 6. 設定 ConsensusTxStatus::Finalized
        → ConsensusTxStatusCache 更新狀態
        → wait_for_effects 的路徑 2 被通知
```

此時 `wait_for_effects` 可以知道交易狀態是 `Finalized`、`Rejected` 或 `Dropped`。

---

### T7 — 排程與執行交易

**誰**：`ExecutionScheduler` → `ExecutionDriver`
**做什麼**：根據物件依賴關係排程，平行執行不衝突的交易
**程式碼**：`crates/sui-core/src/execution_scheduler/`、`crates/sui-core/src/execution_driver.rs`

```
ExecutionScheduler
  │
  ├─ 分析物件依賴關係
  ├─ 不衝突的交易 → 平行執行
  └─ 有衝突的交易 → 按版本號順序執行
      │
      ▼
ExecutionDriver
  └─ authority.try_execute_immediately()
      → 進入 T8
```

---

### T8 — 寫入結果與通知用戶端

**誰**：`AuthorityState`
**做什麼**：透過 Move VM 執行交易、產生 Effects、寫入 DB、觸發通知
**程式碼**：`crates/sui-core/src/authority.rs`

```
AuthorityState::try_execute_immediately()
  │
  ├─ process_certificate()
  │   ├─ read_objects_for_execution()            讀取輸入物件
  │   ├─ executor.execute_transaction_to_effects() 透過 Move VM 執行
  │   │   → 產生 TransactionEffects（哪些物件被建立/修改/刪除）
  │   └─ Fork 檢測：比對 effects digest 是否與預期一致
  │
  ├─ commit_certificate()
  │   └─ 將 Effects 寫入 RocksDB
  │
  └─ 觸發 NotifyRead 通知
      → 所有正在等待這筆交易的 wait_for_effects 被喚醒
      → 路徑 1（notify_read_executed_effects）收到 Effects
      → 回傳給用戶端：WaitForEffectsResponse::Executed

            ┌──────────────────────────────────────┐
            │  此時用戶端收到最終確認                  │
            │  交易結果不可逆                         │
            └──────────────────────────────────────┘
```

---

### T9 — 打包成 Checkpoint

**誰**：`CheckpointBuilder`
**做什麼**：定期將已執行的交易打包成 Checkpoint，簽名後透過共識廣播
**程式碼**：`crates/sui-core/src/checkpoints/mod.rs`

```
CheckpointBuilder::write_checkpoints()
  │
  ├─ 收集一批已執行的交易
  ├─ 因果排序（CausalOrder）
  ├─ 打包成 CheckpointSummary + CheckpointContents
  ├─ 寫入本地 DB
  └─ 將 Checkpoint 簽名透過共識廣播給其他 Validator
```

---

### T10 — Checkpoint 認證與全網同步

**誰**：`CheckpointAggregator` → State Sync → Fullnode
**做什麼**：收集 2/3+ 簽名形成 Certified Checkpoint，供全網同步

```
CheckpointAggregator
  │
  ├─ 收集其他 Validator 的 Checkpoint 簽名
  ├─ 達到 2/3+ stake → 形成 Certified Checkpoint（不可逆）
  │
  ▼
State Sync 協議
  │
  ├─→ Fullnode X 拉取 Certified Checkpoint
  │   ├─ 下載 checkpoint summary + contents
  │   ├─ CheckpointExecutor 按序執行交易
  │   └─ 寫入本地 DB → 狀態與 Validator 一致
  │
  ├─→ Fullnode Y ...
  └─→ Fullnode Z ...

            ┌──────────────────────────────────────┐
            │  全網所有節點狀態一致                    │
            │  交易生命週期完成                        │
            └──────────────────────────────────────┘
```

---

### 時間軸與並行流總覽

```
用戶端              Validator A             其他 Validators          Fullnodes
  │                    │                        │                      │
T0 簽名交易           │                        │                      │
  │                    │                        │                      │
T1 ──送到 Fullnode──→ │                        │                      │
  │    └──轉發給──────→│                        │                      │
  │                    │                        │                      │
T2                    本地驗證                   │                      │
  │←─ConsensusPos─────│                        │                      │
  │                    │                        │                      │
  │──wait_for_effects→│（開始等待...）           │                      │
  │                    │                        │                      │
T3                    ConsensusAdapter          │                      │
  │                    │──submit──→ Mysticeti   │                      │
  │                    │                        │                      │
T4                    │    ←── 廣播 block ────→ SuiTxValidator 投票    │
  │                    │                        │                      │
  │   （FastpathCertified 可提前通知）            │                      │
  │                    │                        │                      │
T5                    │    ←── DAG commit ────→ │                      │
  │                    │                        │                      │
T6                    ConsensusHandler          ConsensusHandler       │
  │                    │（set Finalized）        │（set Finalized）      │
  │                    │                        │                      │
T7                    ExecutionScheduler        ExecutionScheduler     │
  │                    │                        │                      │
T8                    AuthorityState 執行       AuthorityState 執行    │
  │                    │──Effects 寫入 DB        │                      │
  │←─Effects──────────│                        │                      │
  │   （wait_for_effects 被喚醒回傳）             │                      │
  │                    │                        │                      │
T9                    CheckpointBuilder         CheckpointBuilder      │
  │                    │                        │                      │
T10                   CheckpointAggregator      │                      │
  │                    │──Certified Checkpoint──────────────State Sync─→│
  │                    │                        │                     同步完成
```

---

## Validator 是什麼

Validator 是 Sui 網路的核心參與者，負責：

- **接收交易**：透過 gRPC 接收來自 fullnode 或用戶端的交易
- **參與共識**：運行 Mysticeti 協議，與其他 validator 協商交易排序
- **執行交易**：透過 Move VM 執行智能合約邏輯
- **簽署結果**：對執行結果（Effects）簽名，提供最終性保證
- **建構 Checkpoint**：定期打包已執行的交易，供全網同步

判斷一個節點是否為 validator 的方式非常簡單：

```rust
// crates/sui-node/src/lib.rs
let is_validator = config.consensus_config().is_some();
let is_full_node = !is_validator;
```

有 `consensus_config` 就是 validator。同一份 `sui-node` 程式碼，兩種角色。

---

## 啟動流程

Validator 啟動時，`SuiNode::start_async()` 會依序初始化所有元件：

```
sui-node 程式啟動
  │
  ├─ 1. 載入 NodeConfig
  ├─ 2. 初始化儲存（RocksDB、CheckpointStore）
  ├─ 3. 建立 AuthorityState（交易執行引擎）
  ├─ 4. 判斷角色 → is_validator = true
  │
  └─ 5. construct_validator_components()
        │
        ├─ 建立 ConsensusAdapter（提交交易到共識）
        ├─ 建立 ConsensusManager（管理 Mysticeti 生命週期）
        ├─ 啟動 ValidatorService（gRPC 服務）
        ├─ 啟動 Overload Monitor（過載監控）
        │
        └─ start_epoch_specific_validator_components()
              │
              ├─ 啟動 Mysticeti 共識引擎
              ├─ 建立 ConsensusHandler（處理共識輸出）
              ├─ 建立 SuiTxValidator（驗證共識交易）
              ├─ 啟動 CheckpointBuilder（建構 checkpoint）
              └─ 啟動 CheckpointAggregator（聚合簽名）
```

對應程式碼：

```rust
// crates/sui-node/src/lib.rs
let validator_components = if state.is_validator(&epoch_store) {
    let mut components = Self::construct_validator_components(
        config.clone(),
        state.clone(),
        committee,
        epoch_store.clone(),
        checkpoint_store.clone(),
        // ...
    ).await?;

    components.consensus_adapter.submit_recovered(&epoch_store);
    components.validator_server_handle = components.validator_server_handle.start().await;

    Some(components)
} else {
    None
};
```

---

## 核心元件架構圖

```
┌──────────────────────────────────────────────────────────────────┐
│                      一台 Validator 機器                          │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                   ValidatorService (gRPC)                   │ │
│  │            接收交易 / 等待 Effects / Checkpoint 查詢          │ │
│  └─────────────────────────┬───────────────────────────────────┘ │
│                            │                                     │
│                            ▼                                     │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                    ConsensusAdapter                         │ │
│  │              提交交易到共識、等待排序完成                      │ │
│  └─────────────────────────┬───────────────────────────────────┘ │
│                            │                                     │
│                            ▼                                     │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                    ConsensusManager                         │ │
│  │  ┌────────────────────────────────────────────────────────┐ │ │
│  │  │              Mysticeti 共識引擎                         │ │ │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐  │ │ │
│  │  │  │ DAG Builder  │  │  Linearizer  │  │ Committer   │  │ │ │
│  │  │  └──────────────┘  └──────────────┘  └─────────────┘  │ │ │
│  │  └────────────────────────────────────────────────────────┘ │ │
│  │  ┌────────────────────┐                                    │ │
│  │  │  SuiTxValidator    │ ← 驗證交易 + 投票接受/拒絕           │ │
│  │  └────────────────────┘                                    │ │
│  └─────────────────────────┬───────────────────────────────────┘ │
│                            │ 共識輸出 (CommittedSubDag)           │
│                            ▼                                     │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                   ConsensusHandler                         │ │
│  │        過濾/去重交易、分配 shared object 版本號               │ │
│  └─────────────────────────┬───────────────────────────────────┘ │
│                            │                                     │
│                            ▼                                     │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                  ExecutionScheduler                         │ │
│  │              依物件依賴關係排程、平行執行交易                   │ │
│  └─────────────────────────┬───────────────────────────────────┘ │
│                            │                                     │
│                            ▼                                     │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                    AuthorityState                           │ │
│  │     Move VM 執行 → TransactionEffects → 寫入 RocksDB        │ │
│  └─────────────────────────┬───────────────────────────────────┘ │
│                            │                                     │
│                            ▼                                     │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │         CheckpointBuilder → CheckpointAggregator           │ │
│  │            打包交易 → 簽名 → 收集 2/3 簽名 = Certified       │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ◄──── P2P 網路 ────► 與其他 Validator / Fullnode 通訊            │
└──────────────────────────────────────────────────────────────────┘
```

---

## 元件詳解

### 1. ValidatorService — gRPC 服務層

**檔案**: `crates/sui-core/src/authority_server.rs`

Validator 對外暴露的 gRPC 介面，定義了 `Validator` trait 的所有 RPC 方法：

```rust
// crates/sui-core/src/authority_server.rs
impl Validator for ValidatorService {
    async fn submit_transaction(...) -> Result<...> { ... }
    async fn wait_for_effects(...) -> Result<...> { ... }
    async fn object_info(...) -> Result<...> { ... }
    async fn transaction_info(...) -> Result<...> { ... }
    async fn checkpoint(...) -> Result<...> { ... }
}
```

#### submit_transaction — 交易提交入口

當 fullnode 或用戶端提交交易時，ValidatorService 的處理流程：

```
submit_transaction()
  │
  ├─ 1. 反序列化交易 (bcs::from_bytes<Transaction>)
  ├─ 2. 合法性檢查 (validity_check)
  ├─ 3. 過載檢查 (check_system_overload)
  │     → 過載時直接拒絕，回傳 SubmitTxResult::Rejected
  ├─ 4. 簽名驗證 (verify_transaction_with_current_aliases)
  ├─ 5. 投票驗證 (handle_vote_transaction)
  │     → 鎖住 owned objects，驗證版本號
  ├─ 6. 包裝成 ConsensusTransaction
  └─ 7. 提交到共識 (handle_submit_to_consensus_for_position)
        → 回傳 ConsensusPosition（交易在共識中的位置）
```

程式碼細節：

```rust
// crates/sui-core/src/authority_server.rs — handle_submit_transaction_inner()

// 反序列化每筆交易
for (idx, tx_bytes) in request.transactions.iter().enumerate() {
    let transaction = bcs::from_bytes::<Transaction>(tx_bytes)?;

    // 合法性檢查
    let tx_size = transaction.validity_check(&epoch_store.tx_validity_check_context())?;

    // 過載檢查
    let overload_check_res = state.check_system_overload(
        consensus_adapter,
        transaction.data(),
        state.check_system_overload_at_signing(),
    );

    // 簽名驗證
    let verified_transaction = epoch_store
        .verify_transaction_with_current_aliases(transaction)?;

    // 投票（鎖住 owned objects）
    state.handle_vote_transaction(&epoch_store, verified_transaction.clone())?;

    // 包裝成共識交易
    consensus_transactions.push(
        ConsensusTransaction::new_user_transaction_v2_message(&state.name, tx_with_claims)
    );
}

// 提交到共識
self.handle_submit_to_consensus_for_position(consensus_transactions, &epoch_store, ...).await?;
```

#### wait_for_effects — 等待執行結果

用戶端提交交易後，呼叫 `wait_for_effects` 等待結果。有兩條路徑同時等待：

```rust
// crates/sui-core/src/authority_server.rs — wait_for_effects_response()
tokio::select! {
    // 路徑 1: 等待最終確認的 effects（經過共識排序後執行的）
    effects_result = self.state
        .get_transaction_cache_reader()
        .notify_read_executed_effects_may_fail(...) => {
        // 回傳已確認的結果
    }

    // 路徑 2: Fastpath effects（owned object 交易的快速路徑）
    fastpath_response = fastpath_effects_future => {
        // 回傳快速路徑的結果
    }
}
```

可能的回應狀態：
- **Executed** — 交易已執行（可能是 fast_path 或共識路徑）
- **Rejected** — 交易被拒絕（例如 owned object 鎖衝突）
- **Expired** — 交易在共識中過期
- **Dropped** — 交易在共識後被丟棄

#### Soft Bundle 支援

ValidatorService 支援將多筆交易作為一個 soft bundle 提交，系統會盡量將它們排在同一個共識區塊中：

```rust
// crates/sui-core/src/authority_server.rs
let is_soft_bundle_request = submit_type == SubmitTxType::SoftBundle;

let max_num_transactions = if is_soft_bundle_request {
    epoch_store.protocol_config().max_soft_bundle_size()
} else {
    epoch_store.protocol_config().max_num_transactions_in_block()
};
```

---

### 2. ConsensusAdapter — 共識提交器

**檔案**: `crates/sui-core/src/consensus_adapter.rs`

負責將交易從 Sui 層提交到 Mysticeti 共識層。

```rust
// crates/sui-core/src/consensus_adapter.rs
impl ConsensusAdapter {
    pub fn submit(...) -> SuiResult<JoinHandle<()>> {
        self.submit_batch(&[transaction], lock, epoch_store, ...)
    }

    pub fn submit_batch(...) -> SuiResult<JoinHandle<()>> {
        // 取得 semaphore permit（限制同時提交的數量）
        // 序列化交易
        // 提交到共識客戶端
        // 等待共識確認
    }
}
```

核心流程：
1. 取得提交 semaphore（防止過載）
2. 透過 `ConsensusClient` 提交到 Mysticeti
3. 等待共識排序完成
4. 回傳 `ConsensusPosition`（交易在哪個 block、哪個位置）

重試機制：

```rust
// crates/sui-core/src/consensus_adapter.rs — submit_inner()
let (consensus_positions, status_waiter) = loop {
    match self.consensus_client.submit(transactions, epoch_store).await {
        Err(err) => {
            // 共識提交失敗，自動重試（常見於 epoch 切換時）
            warn!("Failed to submit to consensus: {err}. Retry #{retries}");
            retries += 1;
            time::sleep(backoff.next().unwrap()).await;
        }
        Ok((positions, waiter)) => break (positions, waiter),
    }
};
```

---

### 3. ConsensusManager — 共識管理器

**檔案**: `crates/sui-core/src/consensus_manager/mod.rs`

管理 Mysticeti 共識引擎的完整生命週期——每個 epoch 啟動一次、關閉一次。

```rust
// crates/sui-core/src/consensus_manager/mod.rs
pub struct ConsensusManager {
    consensus_config: ConsensusConfig,
    protocol_keypair: ProtocolKeyPair,
    network_keypair: NetworkKeyPair,
    authority: ArcSwapOption<(ConsensusAuthority, RegistryID)>,
    client: Arc<LazyMysticetiClient>,
    consensus_handler: Mutex<Option<MysticetiConsensusHandler>>,
    running: Mutex<Running>,
    boot_counter: Mutex<u64>,
    // ...
}
```

#### 啟動共識

```rust
// crates/sui-core/src/consensus_manager/mod.rs — start()
pub async fn start(&self, node_config, epoch_store, consensus_handler_initializer, tx_validator) {
    // 確保不會重複啟動
    let mut running = self.running.lock().await;
    *running = Running::True(epoch, protocol_config.version);

    // 建立 Mysticeti 共識實例
    let authority = ConsensusAuthority::start(
        NetworkType::Tonic,
        epoch_store.epoch_start_config().epoch_start_timestamp_ms(),
        own_index,
        committee.clone(),
        parameters.clone(),
        protocol_config.clone(),
        self.protocol_keypair.clone(),
        self.network_keypair.clone(),
        Arc::new(Clock::default()),
        Arc::new(tx_validator.clone()),
        commit_consumer,
        registry.clone(),
        *boot_counter,
    ).await;

    // 初始化客戶端，讓 ConsensusAdapter 可以提交交易
    let client = authority.transaction_client();
    self.client.set(client);
}
```

#### 關閉共識

```rust
// crates/sui-core/src/consensus_manager/mod.rs — shutdown()
pub async fn shutdown(&self) {
    // 停止接受新交易
    self.client.clear();

    // 關閉 Mysticeti 引擎
    let (authority, registry_id) = Arc::try_unwrap(r).unwrap();
    authority.stop().await;

    // 停止 ConsensusHandler
    if let Some(mut handler) = consensus_handler.take() {
        handler.abort().await;
    }

    self.consensus_client.clear();
}
```

---

### 4. SuiTxValidator — 共識交易驗證器

**檔案**: `crates/sui-core/src/consensus_validator.rs`

Mysticeti 共識引擎在將交易打包進 block 之前，會呼叫 `SuiTxValidator` 來驗證交易。每個 validator 可以投票決定是否接受或拒絕某筆交易。

```rust
// crates/sui-core/src/consensus_validator.rs
pub struct SuiTxValidator {
    authority_state: Arc<AuthorityState>,
    epoch_store: Arc<AuthorityPerEpochStore>,
    consensus_overload_checker: Arc<dyn ConsensusOverloadChecker>,
    checkpoint_service: Arc<dyn CheckpointServiceNotify + Send + Sync>,
    metrics: Arc<SuiTxValidatorMetrics>,
}
```

#### 投票機制

```rust
// crates/sui-core/src/consensus_validator.rs
fn vote_transactions(&self, block_ref: &BlockRef, txs: Vec<ConsensusTransactionKind>) -> Vec<TransactionIndex> {
    let mut reject_txn_votes = Vec::new();

    for (i, tx) in txs.into_iter().enumerate() {
        if let Err(error) = self.vote_transaction(epoch_store, tx) {
            // 投票拒絕
            debug!(?tx_digest, "Voting to reject transaction: {error}");
            reject_txn_votes.push(i as TransactionIndex);
        } else {
            // 投票接受
            debug!(?tx_digest, "Voting to accept transaction");
        }
    }

    reject_txn_votes  // 回傳要拒絕的交易索引
}
```

投票驗證的檢查項目：
1. `validity_check()` — 交易格式合法性
2. `check_system_overload()` — 系統是否過載
3. `verify_transaction_with_current_aliases()` — 簽名驗證
4. 地址別名（address aliases）一致性檢查

---

### 5. ConsensusHandler — 共識輸出處理器

**檔案**: `crates/sui-core/src/consensus_handler.rs`

接收 Mysticeti 產出的 `CommittedSubDag`，將其轉換為可執行的交易。

```rust
// crates/sui-core/src/consensus_handler.rs
pub async fn handle_consensus_commit(&mut self, consensus_commit: impl ConsensusCommitAPI) {
    // 1. 等待 backpressure 解除
    self.backpressure_subscriber.await_no_backpressure().await;

    // 2. 過濾交易（移除無效的）
    let FilteredConsensusOutput { transactions, owned_object_locks } =
        self.filter_consensus_txns(..., &consensus_commit);

    // 3. 去重（移除重複提交的）
    let transactions = self.deduplicate_consensus_txns(&mut state, ...);

    // 4. 分類交易
    let CommitHandlerInput {
        user_transactions,
        checkpoint_signature_messages,
        randomness_dkg_messages,
        end_of_publish_transactions,
        // ...
    } = self.build_commit_handler_input(transactions);

    // 5. 處理各類交易
    self.process_checkpoint_signature_messages(checkpoint_signature_messages);

    // 6. 為 shared objects 分配版本號並排程執行
    self.process_transactions(&mut state, ...);
}
```

關鍵步驟 — 交易去重：

```rust
// crates/sui-core/src/consensus_handler.rs — deduplicate_consensus_txns()
// 同一筆交易可能被多個 validator 提交到共識
// ConsensusHandler 會根據交易 key 去重，只處理第一次出現的
let count = occurrence_counts.entry(key.clone()).or_insert(0);
*count += 1;
let in_commit = *count > 1;

let in_cache = self.processed_cache.put(key.clone(), ()).is_some();
if in_commit || in_cache {
    // 跳過重複的交易
    continue;
}
```

---

### 6. AuthorityState — 狀態與執行引擎

**檔案**: `crates/sui-core/src/authority.rs`

Validator 的核心狀態管理，負責交易執行和資料持久化。

```rust
// crates/sui-core/src/authority.rs
pub struct AuthorityState {
    pub name: AuthorityName,
    pub secret: StableSyncAuthoritySigner,
    epoch_store: ArcSwap<AuthorityPerEpochStore>,
    execution_lock: RwLock<EpochId>,
    pub checkpoint_store: Arc<CheckpointStore>,
    execution_scheduler: Arc<ExecutionScheduler>,
    pub metrics: Arc<AuthorityMetrics>,
    pub config: NodeConfig,
    // ...
}
```

#### handle_vote_transaction — 投票簽署

在交易提交到共識之前，validator 先驗證並「投票」：

```rust
// crates/sui-core/src/authority.rs
pub fn handle_vote_transaction(
    &self,
    epoch_store: &Arc<AuthorityPerEpochStore>,
    transaction: VerifiedTransaction,
) -> SuiResult<()> {
    // 檢查 epoch 是否仍在接受交易
    if !epoch_store.get_reconfig_state_read_lock_guard().should_accept_user_certs() {
        return Err(SuiErrorKind::ValidatorHaltedAtEpochEnd.into());
    }

    // 如果交易已執行過，直接接受
    if epoch_store.is_recently_finalized(&tx_digest)
        || epoch_store.transactions_executed_in_cur_epoch(&[tx_digest])?[0]
    {
        return Ok(());
    }

    // 驗證輸入物件、檢查版本號
    let checked_input_objects = self.handle_transaction_deny_checks(&transaction, epoch_store)?;

    // 驗證 owned object 版本（不取得鎖，鎖在共識後才取得）
    self.get_cache_writer().validate_owned_object_versions(&owned_objects)
}
```

#### process_certificate — 執行交易

共識排序完成後，交易進入執行階段：

```rust
// crates/sui-core/src/authority.rs
fn process_certificate(&self, tx_guard, execution_guard, certificate, execution_env, epoch_store) {
    // 1. 讀取輸入物件
    let input_objects = self.read_objects_for_execution(
        tx_guard.as_lock_guard(),
        certificate,
        &execution_env.assigned_versions,
        epoch_store,
    )?;

    // 2. 執行交易（呼叫 Move VM）
    let (inner_temp_store, _, effects, timings, execution_error_opt) =
        epoch_store.executor().execute_transaction_to_effects(
            &tracking_store,
            protocol_config,
            // ... 執行參數
            kind,
            signer,
            tx_digest,
        );

    // 3. Fork 檢測：比對 effects digest
    if effects.digest() != expected_effects_digest {
        error!("fork detected!");
    }
}
```

#### commit_certificate — 提交結果

執行成功後，將結果寫入資料庫：

```rust
// crates/sui-core/src/authority.rs
let effects = transaction_outputs.effects.clone();
let commit_result = self.commit_certificate(certificate, transaction_outputs, epoch_store);
```

---

### 7. CheckpointBuilder — Checkpoint 建構器

**檔案**: `crates/sui-core/src/checkpoints/mod.rs`

Validator 負責將已執行的交易定期打包成 checkpoint。

```rust
// crates/sui-core/src/checkpoints/mod.rs
async fn write_checkpoints(
    &mut self,
    height: CheckpointHeight,
    new_checkpoints: NonEmpty<(CheckpointSummary, CheckpointContents)>,
) -> SuiResult {
    for (summary, contents) in &new_checkpoints {
        // 寫入 checkpoint 內容到 DB
        batch.insert_batch(&self.store.tables.checkpoint_content, [(contents.digest(), contents)])?;
        batch.insert_batch(&self.store.tables.locally_computed_checkpoints, [(sequence_number, summary)])?;
    }
    batch.write()?;

    // 將 checkpoint 簽名透過共識廣播
    for (summary, contents) in &new_checkpoints {
        self.output.checkpoint_created(summary, contents, &self.epoch_store, &self.store).await?;
    }

    // 通知 CheckpointAggregator 去收集簽名
    self.notify_aggregator.notify_one();
}
```

Checkpoint 從建構到認證的完整流程：

```
ConsensusHandler 輸出已排序的交易
        │
        ▼
ExecutionScheduler 執行交易
        │
        ▼
CheckpointBuilder 打包交易
  ├─ 寫入本地 DB
  └─ 透過共識廣播 checkpoint 簽名
        │
        ▼
CheckpointAggregator 收集簽名
  └─ 收集到 2/3+ stake 簽名
        │
        ▼
Certified Checkpoint（不可逆）
  └─ 透過 State Sync 供 fullnode 拉取
```

---

## Epoch 生命週期

Validator 的元件以 epoch 為單位運作。每次 epoch 切換：

```
舊 Epoch 結束
  │
  ├─ 1. 停止接受新交易 (should_accept_user_certs() = false)
  ├─ 2. 等待所有待執行交易完成
  ├─ 3. 建構最後一個 checkpoint (is_last_checkpoint_of_epoch)
  ├─ 4. ConsensusManager::shutdown()  ← 關閉舊的 Mysticeti
  │
  ▼
新 Epoch 開始
  │
  ├─ 1. 載入新的 committee（validator 集合可能變動）
  ├─ 2. 判斷自己是否仍是 validator
  │     ├─ 是 → start_epoch_specific_validator_components()
  │     └─ 否 → 降級為 fullnode
  ├─ 3. ConsensusManager::start()  ← 啟動新的 Mysticeti 實例
  └─ 4. 恢復接受交易
```

對應程式碼：

```rust
// crates/sui-node/src/lib.rs — reconfigure()
if self.state.is_validator(&new_epoch_store) {
    // 仍然是 validator → 重啟共識
    Some(Self::start_epoch_specific_validator_components(...).await?)
} else {
    info!("Promoting the node from fullnode to validator, starting grpc server");
    // 或者相反：從 validator 降級為 fullnode
}
```

---

## 關鍵原始碼索引

| 元件 | 檔案 | 職責 |
|---|---|---|
| **ValidatorService** | `crates/sui-core/src/authority_server.rs` | gRPC 服務，接收交易和查詢 |
| **ConsensusAdapter** | `crates/sui-core/src/consensus_adapter.rs` | 提交交易到共識，等待排序 |
| **ConsensusManager** | `crates/sui-core/src/consensus_manager/mod.rs` | 管理 Mysticeti 生命週期 |
| **LazyMysticetiClient** | `crates/sui-core/src/mysticeti_adapter.rs` | Mysticeti 客戶端轉接器 |
| **SuiTxValidator** | `crates/sui-core/src/consensus_validator.rs` | 共識層的交易驗證與投票 |
| **ConsensusHandler** | `crates/sui-core/src/consensus_handler.rs` | 處理共識輸出，分配版本號 |
| **AuthorityState** | `crates/sui-core/src/authority.rs` | 核心狀態管理與交易執行 |
| **AuthorityPerEpochStore** | `crates/sui-core/src/authority/authority_per_epoch_store.rs` | 每 epoch 的狀態與鎖 |
| **SharedObjectVersionManager** | `crates/sui-core/src/authority/shared_object_version_manager.rs` | Shared object 版本分配 |
| **ExecutionScheduler** | `crates/sui-core/src/execution_scheduler/` | 交易執行排程 |
| **ExecutionDriver** | `crates/sui-core/src/execution_driver.rs` | 驅動交易執行 |
| **BackpressureManager** | `crates/sui-core/src/authority/backpressure.rs` | 執行背壓控制 |
| **CheckpointBuilder** | `crates/sui-core/src/checkpoints/mod.rs` | 建構 checkpoint |
| **CheckpointAggregator** | `crates/sui-core/src/checkpoints/mod.rs` | 收集 checkpoint 簽名 |
| **CausalOrder** | `crates/sui-core/src/checkpoints/causal_order.rs` | Checkpoint 內交易的因果排序 |
| **OverloadMonitor** | `crates/sui-core/src/overload_monitor.rs` | 系統過載監控 |
| **SuiNode** | `crates/sui-node/src/lib.rs` | 節點啟動與元件組裝 |
| **Mysticeti 核心** | `consensus/core/src/core.rs` | 共識核心邏輯 |
| **DAG Linearizer** | `consensus/core/src/linearizer.rs` | DAG 線性化 |
| **ConsensusAuthority** | `consensus/core/src/authority_node.rs` | 共識節點入口 |
