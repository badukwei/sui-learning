# Fullnode 與 Validator 的差異

同一份 `sui-node` 程式碼，根據是否配置 `consensus_config` 決定角色。

## 核心差異

| | Validator | Fullnode |
|---|---|---|
| 運行 Mysticeti 共識 | 是 | 否 |
| 對交易簽名投票 | 是 | 否 |
| 產生區塊 | 是 | 否 |
| 執行交易時機 | 收到交易後直接執行 | 收到 certified checkpoint 後重放 |
| Checkpoint 角色 | 建構者（打包 + 簽名） | 消費者（拉取 + 重放驗證） |
| 對外 API | 通常不開放 | 提供 JSON-RPC / GraphQL |
| Index Store | 通常不需要 | 建立索引支援豐富查詢 |
| TransactionOrchestrator | 不需要 | 需要（轉發交易給 validator） |

## Fullnode 不是「寫入鏈上」

- **Validator** 才是寫入鏈上資料的角色：執行交易 → 簽署 Effects → 建構 Checkpoint → 收集 2/3 簽名 = 上鏈
- **Fullnode** 只是同步已 certify 的資料到本地，重放驗證後存入本地資料庫供查詢