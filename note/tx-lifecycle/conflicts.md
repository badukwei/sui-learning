# 狀態不同步的處理機制

分散式系統中，節點之間不可能時刻同步。Sui 在多個層面處理時間差問題：

## 1. Owned Object 版本衝突

每個 owned object 有版本號和物件鎖。交易必須指定確切的物件版本：

- 引用的版本比本地 (validator) 舊 → 拒絕（物件已被消費）
- 引用的版本比本地 (validator) 新 → 允許（其他 validator 已更新但尚未同步）
- 物件鎖確保同一版本只能被一筆交易消費，防止雙花

## 2. Shared Object 排序

所有 shared object 交易都必須經過 Mysticeti 共識。共識給出全域一致的排序，`SharedObjectVersionManager` 統一分配版本號。即使 validators 在不同時間收到共識結果，它們按照相同的順序執行，最終狀態一定一致。

## 3. Fullnode 落後 Validator

Fullnode 嚴格按 checkpoint 序號依序等待並執行。如果 checkpoint #100 還沒到，就等著，絕不跳過。只要追上 checkpoint 就能恢復一致。

## 4. 執行跟不上共識速度（Backpressure）

如果共識產出速度超過本地執行速度，`BackpressureManager` 會暫停接收共識輸出，等待執行追上：

- 當 writeback cache 中待處理交易過多時觸發
- 但如果 certified checkpoint 沒有超前 executed checkpoint，不能施加 backpressure（否則會死鎖）

## 5. Validator 執行結果不一致（Fork Detection）

正常情況下所有 validator 對同一筆交易的執行結果（`TransactionEffects`）應完全相同。如果不同，代表出現 fork：

- 系統比對 effects digest，偵測不一致
- Checkpoint 層面也會驗證本地建構的 checkpoint 與網路 certify 的是否一致
- 偵測到 fork 時記錄、警告甚至停止運作

## 6. 用戶端遇到不同步（重試機制）

用戶端收集 effects 簽名時可能遇到暫時性不一致：

- **Aborted**（暫時性）：部分 validator 還沒處理完 → 可以重試
- **ForkedExecution**（嚴重）：不同 validator 產生了不同結果 → 不可重試

## 總結

| 問題 | 解法 |
|---|---|
| Owned object 版本不同步 | 物件版本號 + 鎖：精確比對，過期拒絕 |
| Shared object 誰先誰後 | 共識排序：全域一致的執行順序 |
| Fullnode 落後 Validator | Checkpoint 按序同步：嚴格依序追趕 |
| 執行跟不上共識速度 | Backpressure：暫停接收共識輸出 |
| Validator 執行結果不一致 | Fork detection：比對 effects digest |
| 用戶端收到不一致回應 | 重試機制：Aborted 可重試，Fork 則停止 |
| Epoch 切換時的不同步 | Execution lock：寫鎖阻止跨 epoch 衝突 |

核心設計哲學：**不要求即時同步，保證最終一致性**。物件版本號和 checkpoint 序號是收斂的「錨點」——只要所有節點最終處理了相同的 checkpoint 序列，狀態一定一致。