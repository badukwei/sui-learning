# Sui 交易完整生命週期

一筆交易從用戶發送到最終上鏈、同步至所有節點的完整流程。

---

## 概覽

Sui 根據交易涉及的物件類型，區分為兩條路徑：

- **Owned Object 交易**（例如轉 NFT）：不需要經過共識，延遲低
- **Shared Object 交易**（例如與 DEX 互動）：需要 Mysticeti 共識排序

---

## 階段一：用戶端提交交易

### 1. 用戶簽名並發送交易

用戶（錢包 / SDK）構建 `TransactionData`，簽名後透過 JSON-RPC 或 gRPC 送到一個 fullnode 或 validator。

### 2. TransactionOrchestrator 接收交易

Fullnode 的 `TransactionOrchestrator`（`crates/sui-core/src/transaction_orchestrator.rs`）判斷交易類型：

- `TxType::SingleWriter` — 只涉及 owned objects（快速路徑）
- `TxType::SharedObject` — 涉及 shared objects（需要共識）

### 3. TransactionDriver 廣播給 Validators

`TransactionDriver`（`crates/sui-core/src/transaction_driver/mod.rs`）透過 `TransactionSubmitter` 將交易平行送給多個 validator。

---

## 階段二：Validator 處理交易

### 4. ValidatorService 接收交易

每個 validator 的 `ValidatorService`（`crates/sui-core/src/authority_server.rs`）執行初始檢查：

- 簽名驗證
- 交易格式合法性
- Gas 是否足夠

### 5A. Owned Object 路徑（快速路徑）

交易只涉及 **owned objects** 時：

1. Validator 鎖住相關物件（防止雙花）
2. 對交易簽名，回傳簽名給提交者
3. 用戶端收集 2/3+ stake 的 validator 簽名
4. 形成 **Transaction Certificate**
5. **不需要等待共識**即可開始執行

### 5B. Shared Object 路徑（需要共識）

交易涉及 **shared objects** 時：

1. Validator 透過 `ConsensusAdapter`（`crates/sui-core/src/consensus_adapter.rs`）提交交易到 Mysticeti 共識
2. `LazyMysticetiClient`（`crates/sui-core/src/mysticeti_adapter.rs`）序列化並送入共識引擎
3. 等待交易被排序

---

## 階段三：共識排序（僅 Shared Object 交易）

### 6. Mysticeti 共識

在 `consensus/core/` 中：

1. 交易被打包進一個 **DAG block**
2. Validators 互相交換 block，形成 DAG 結構
3. 經過 3 輪通訊後，leader 的 block 被 commit
4. `Linearizer` 將 DAG 線性化為確定的交易全序

### 7. ConsensusHandler 處理共識輸出

`ConsensusHandler`（`crates/sui-core/src/consensus_handler.rs`）接收 `CommittedSubDag` 並：

- 過濾、去重交易
- 為 shared objects 分配版本號（決定執行順序）
- 分類交易（用戶交易、系統交易、checkpoint 簽名等）

---

## 階段四：執行交易

### 8. ExecutionScheduler 排程

`ExecutionScheduler`（`crates/sui-core/src/execution_scheduler/`）分析物件依賴關係並排程——不衝突的交易可以**平行執行**。

### 9. AuthorityState 執行交易

`AuthorityState`（`crates/sui-core/src/authority.rs`）呼叫 `process_certificate` → `execute_certificate`：

1. 從儲存層讀取輸入物件
2. 透過 **Move VM** 執行交易邏輯
3. 產生 `TransactionEffects`（描述狀態變更：物件的建立/修改/刪除）
4. 將結果寫入資料庫（RocksDB）

### 10. Effects 簽名與用戶確認

Validator 簽署 `TransactionEffects`。用戶端（透過 `EffectsCertifier`）收集 2/3+ stake 的 effects 簽名。此時**用戶收到確認——交易不可逆**。

---

## 階段五：Checkpoint 與跨節點同步

### 11. CheckpointBuilder 建立 Checkpoint

每個 validator 的 `CheckpointBuilder`（`crates/sui-core/src/checkpoints/mod.rs`）定期把已執行的交易打包成 **Checkpoint**：

- 一個 checkpoint 包含一批交易的摘要及其 effects
- Validator 簽署 checkpoint 並透過共識廣播簽名

### 12. CheckpointAggregator 聚合簽名

收集到 2/3+ stake 的 checkpoint 簽名後，形成 **Certified Checkpoint**——不可逆的全網共識。

### 13. State Sync 同步到 Fullnodes

Fullnode 透過 **State Sync** 協議從 validator 拉取 certified checkpoints：

- 下載 checkpoint summary 和 contents
- `CheckpointExecutor`（`crates/sui-core/src/checkpoints/checkpoint_executor/mod.rs`）按序執行 checkpoint 中的交易
- 同步完成後，fullnode 的狀態與 validator 一致

---

## 流程圖

```
用戶（錢包 / SDK）
  │
  ▼
Fullnode（TransactionOrchestrator）
  │
  ├─── TransactionDriver ──► 廣播給多個 Validators
  │
  ▼
Validator（ValidatorService）
  │
  ├─ Owned Object? ──► 直接簽名
  │                       │
  │                       ▼
  │                 收集 2/3 簽名 = Certificate ──► 執行
  │
  └─ Shared Object? ──► ConsensusAdapter ──► Mysticeti 共識
                                                  │
                                                  ▼
                                          ConsensusHandler
                                          （排序 + 分配版本）
                                                  │
                                                  ▼
                                          ExecutionScheduler
                                          （平行執行）
                                                  │
                                                  ▼
                                          AuthorityState.execute_certificate()
                                          （Move VM 執行 + 寫入 DB）
                                                  │
                                                  ▼
                                          簽署 Effects ──► 回傳用戶（交易確認）
                                                  │
                                                  ▼
                                          CheckpointBuilder（打包交易）
                                                  │
                                                  ▼
                                          Certified Checkpoint（2/3 簽名）
                                                  │
                                                  ▼
                                          State Sync ──► 所有 Fullnodes 同步
```


## 關鍵原始碼對照

| 檔案 | 職責 |
|---|---|
| `crates/sui-core/src/transaction_orchestrator.rs` | Fullnode 的交易入口 |
| `crates/sui-core/src/transaction_driver/mod.rs` | 廣播交易給 validators |
| `crates/sui-core/src/authority_server.rs` | Validator gRPC 服務 |
| `crates/sui-core/src/consensus_adapter.rs` | 提交交易到共識 |
| `crates/sui-core/src/mysticeti_adapter.rs` | Mysticeti 用戶端轉接器 |
| `consensus/core/src/core.rs` | 共識核心邏輯 |
| `consensus/core/src/linearizer.rs` | DAG 線性化 |
| `crates/sui-core/src/consensus_handler.rs` | 處理共識輸出 |
| `crates/sui-core/src/execution_scheduler/` | 交易執行排程 |
| `crates/sui-core/src/authority.rs` | 交易執行與狀態管理 |
| `crates/sui-core/src/authority/backpressure.rs` | Backpressure 機制 |
| `crates/sui-core/src/authority/shared_object_version_manager.rs` | Shared object 版本分配 |
| `crates/sui-core/src/checkpoints/mod.rs` | Checkpoint 建構 |
| `crates/sui-core/src/checkpoints/checkpoint_executor/mod.rs` | Fullnode 上的 Checkpoint 執行 |
| `crates/sui-core/src/checkpoints/causal_order.rs` | 因果排序 |
