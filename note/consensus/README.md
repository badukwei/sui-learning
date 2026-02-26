# Sui 共識設計深度解析 — Mysticeti

本文件從整體邏輯出發，逐步拆解 Sui 所使用的 Mysticeti 共識協議的設計理念、核心步驟、資料結構，以及對應的程式碼實作。

---

## 目錄

1. [為什麼需要共識](#為什麼需要共識)
2. [設計哲學](#設計哲學)
3. [核心概念總覽](#核心概念總覽)
4. [完整範例：一筆交易的共識之旅](#完整範例一筆交易的共識之旅)
   - [場景設定](#場景設定)
   - [Round 1 — 交易進入 DAG](#round-1--交易進入-dag)
   - [Round 2 — 投票輪](#round-2--投票輪)
   - [Round 3 — 決定輪](#round-3--決定輪)
   - [Commit 與 Linearize](#commit-與-linearize)
   - [範例：交易被拒絕的情況](#範例交易被拒絕的情況)
   - [範例：Leader 被 Skip 的情況](#範例leader-被-skip-的情況)
   - [範例：Indirect Decide](#範例indirect-decide)
5. [DAG — 核心資料結構](#dag--核心資料結構)
   - [Block 的定義](#block-的定義)
   - [Block 的建構流程](#block-的建構流程)
   - [Block 的廣播](#block-的廣播)
6. [投票機制](#投票機制)
   - [隱性投票 — 引用即投票](#隱性投票--引用即投票)
   - [顯性投票 — SuiTxValidator](#顯性投票--suitxvalidator)
   - [Fastpath 快速確認](#fastpath-快速確認)
7. [Commit Rule — 確認不可逆](#commit-rule--確認不可逆)
   - [Wave 結構](#wave-結構)
   - [Direct Decide — 直接決定](#direct-decide--直接決定)
   - [Indirect Decide — 間接決定](#indirect-decide--間接決定)
8. [Linearizer — DAG 線性化](#linearizer--dag-線性化)
   - [收集 Sub-DAG](#收集-sub-dag)
   - [排序規則](#排序規則)
9. [共識輸出 — CommittedSubDag](#共識輸出--committedsubdag)
10. [Sui 與共識層的整合](#sui-與共識層的整合)
    - [交易提交入口](#交易提交入口)
    - [共識輸出處理](#共識輸出處理)
11. [Epoch 生命週期](#epoch-生命週期)
12. [關鍵程式碼索引](#關鍵程式碼索引)

---

## 為什麼需要共識

區塊鏈網路中有多個 Validator 同時接收交易，每個 Validator 收到的順序可能不同：

```
Validator A 看到：Tx3, Tx1, Tx7, Tx2 ...
Validator B 看到：Tx1, Tx7, Tx3, Tx5 ...
Validator C 看到：Tx7, Tx2, Tx1, Tx3 ...
```

但交易的執行結果必須完全一致（例如 Tx1 和 Tx3 操作同一個共享物件，先執行誰會影響結果）。

**共識的本質**：讓所有 Validator 對交易的順序達成一致，即使其中最多 1/3 是惡意的（拜占庭容錯）。

---

## 設計哲學

Mysticeti 是一個 **DAG-based BFT Consensus Protocol**（基於有向無環圖的拜占庭容錯共識協議）。

```
┌───────────────────────────────────────────────────────────────┐
│                                                               │
│  1. 去中心化：沒有固定 Leader，不存在單點故障                    │
│     → 每個 Validator 持續獨立出 block                          │
│                                                               │
│  2. 持續推進：不需要等其他人，天然高吞吐                         │
│     → 收到交易就打包，收到別人的 block 就引用                    │
│                                                               │
│  3. 引用即投票：不需要獨立的投票訊息                             │
│     → block 之間的引用關係本身就是共識證據                       │
│                                                               │
│  4. 延遲分離：                                                 │
│     ├─ 交易分發 = 立即（block 廣播）                           │
│     ├─ 投票確認 = 快（FastpathCertified，1-2 輪）              │
│     └─ 最終排序 = 稍慢（commit，2-3 輪）                       │
│                                                               │
│  5. 確定性：commit 後的順序全網一致，不可逆                      │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

與傳統共識的對比：

| | 傳統 BFT（PBFT/Tendermint） | DAG-based（Mysticeti） |
|---|---|---|
| 結構 | 固定 Leader 提案 → 投票 → 確認 | 每個人持續出 block → DAG → commit |
| Leader | 每輪一個固定 Leader | Leader 只用於 commit 判定，不影響出塊 |
| 通訊 | 多輪顯式投票訊息 | 引用即投票，無額外訊息 |
| 吞吐 | 受 Leader 瓶頸限制 | 所有人平行出塊，天然高吞吐 |
| 容錯 | Leader 掛了要切換 | 任何人掛了都不影響出塊 |

---

## 核心概念總覽

```
時間推進方向 →

Round 1        Round 2        Round 3        Round 4
┌────┐         ┌────┐         ┌────┐         ┌────┐
│ A1 │────────→│ A2 │────────→│ A3 │────────→│ A4 │
└────┘    ╲    └────┘    ╲    └────┘    ╲    └────┘
           ╲              ╲              ╲
┌────┐    ╱ ╲  ┌────┐    ╱ ╲  ┌────┐    ╱ ╲  ┌────┐
│ B1 │──────→│ B2 │──────→│ B3 ★│─────→│ B4 │
└────┘    ╱    └────┘    ╱    └────┘    ╱    └────┘
           ╱              ╱              ╱
┌────┐    ╱    ┌────┐    ╱    ┌────┐    ╱    ┌────┐
│ C1 │────────→│ C2 │────────→│ C3 │────────→│ C4 │
└────┘         └────┘         └────┘         └────┘

方塊 = Block（包含交易 + 對前一輪 block 的引用）
箭頭 = 引用（ancestors）
★   = Leader block（用於 commit 判定）
```

**名詞定義**：

| 名詞 | 意義 |
|---|---|
| **Round** | 時間輪次，每個 Validator 每輪最多出一個 block |
| **Block** | 包含交易和引用的資料單元 |
| **Ancestors** | 一個 block 引用的前輪 blocks |
| **DAG** | 所有 blocks 的引用關係形成的有向無環圖 |
| **Leader** | 每個 wave 的第一輪選出的特殊 block，用於 commit 判定 |
| **Wave** | 一組 3 輪（leader round → voting round → decision round） |
| **Commit** | Leader 被判定為已確認，連同其引用的所有 blocks 一起確定 |
| **Sub-DAG** | 一個 leader commit 時，連帶確認的所有 blocks 的集合 |
| **Linearize** | 將 Sub-DAG（二維圖）壓成一維的全序交易列表 |

---

## 完整範例：一筆交易的共識之旅

用一個具體的例子，帶你走過共識的每一步。

### 場景設定

```
網路中有 4 個 Validator，各自持有等量的 stake（各 25%）：

  Validator A （stake 25%）
  Validator B （stake 25%）
  Validator C （stake 25%）
  Validator D （stake 25%）

  Quorum = 2/3+ = 需要至少 3 個 Validator（75% stake）同意

用戶小明要轉 10 SUI 給小華（涉及 shared object，需要共識排序）
```

---

### Round 1 — 交易進入 DAG

小明把交易送到 Validator A。A 做完本地驗證後，把交易打包進自己的 block。

同一時間，其他 Validator 也各自收到別的交易，各自打包出 block。

```
Round 1（Leader Round — 假設 A 是這輪的 Leader）

 ┌──────────────────────┐
 │ A1 ★ Leader          │   包含小明的交易 Tx_Ming
 │ ancestors: [genesis]  │   引用: 創世 block
 │ transactions: [Tx_Ming]│
 └──────────────────────┘

 ┌──────────────────────┐
 │ B1                   │   包含其他交易 Tx_X
 │ ancestors: [genesis]  │
 │ transactions: [Tx_X]  │
 └──────────────────────┘

 ┌──────────────────────┐
 │ C1                   │   包含其他交易 Tx_Y
 │ ancestors: [genesis]  │
 │ transactions: [Tx_Y]  │
 └──────────────────────┘

 ┌──────────────────────┐
 │ D1                   │   沒有新交易，空 block
 │ ancestors: [genesis]  │
 │ transactions: []      │
 └──────────────────────┘
```

每個 Validator 透過 `Broadcaster` 把自己的 block 廣播給其他所有人。

```
A ──A1──→ B, C, D
B ──B1──→ A, C, D
C ──C1──→ A, B, D
D ──D1──→ A, B, C
```

**同時**，每個 Validator 收到別人的 block 時，`SuiTxValidator` 會對裡面的交易投票：

```
B 收到 A1（包含 Tx_Ming）
  → SuiTxValidator::vote_transaction(Tx_Ming)
  → validity_check() ✓
  → check_system_overload() ✓
  → verify_transaction() ✓
  → handle_vote_transaction() ✓
  → 投票：接受 ✓

C 收到 A1（包含 Tx_Ming）
  → 同樣的驗證流程
  → 投票：接受 ✓

D 收到 A1（包含 Tx_Ming）
  → 投票：接受 ✓
```

---

### Round 2 — 投票輪

每個 Validator 出新 block，引用 Round 1 收到的 blocks。**引用 = 隱性投票**。

```
Round 2（Voting Round）

 ┌────────────────────────────────────────┐
 │ A2                                    │
 │ ancestors: [A1, B1, C1, D1]           │ ← A 看到了所有人的 R1 block
 │ transactions: [Tx_Z]                  │
 │ transaction_votes: [                  │
 │   {block: B1, rejects: []},           │ ← 接受 B1 中所有交易
 │   {block: C1, rejects: []},           │ ← 接受 C1 中所有交易
 │   {block: D1, rejects: []},           │ ← D1 沒交易，不用投票
 │ ]                                     │
 └────────────────────────────────────────┘

 ┌────────────────────────────────────────┐
 │ B2                                    │
 │ ancestors: [A1, B1, C1, D1]           │ ← B 也看到了所有人
 │ transactions: []                      │
 │ transaction_votes: [                  │
 │   {block: A1, rejects: []},           │ ← 接受 A1 中的 Tx_Ming ✓
 │   {block: C1, rejects: []},           │
 │ ]                                     │
 └────────────────────────────────────────┘

 ┌────────────────────────────────────────┐
 │ C2                                    │
 │ ancestors: [A1, B1, C1, D1]           │
 │ transaction_votes: [                  │
 │   {block: A1, rejects: []},           │ ← 接受 A1 中的 Tx_Ming ✓
 │ ]                                     │
 └────────────────────────────────────────┘

 ┌────────────────────────────────────────┐
 │ D2                                    │
 │ ancestors: [A1, B1, C1, D1]           │
 │ transaction_votes: [                  │
 │   {block: A1, rejects: []},           │ ← 接受 A1 中的 Tx_Ming ✓
 │ ]                                     │
 └────────────────────────────────────────┘
```

DAG 長這樣（箭頭 = ancestors 引用）：

```
Round 1               Round 2

┌────┐                ┌────┐
│ A1 │★ ←─────────────│ A2 │
└────┘ ╲          ╱   └────┘
        ╲        ╱
┌────┐   ╲  ╱  ╱     ┌────┐
│ B1 │←──────╳────────│ B2 │
└────┘   ╱  ╲  ╲     └────┘
        ╱        ╲
┌────┐ ╱          ╲   ┌────┐
│ C1 │←───────────────│ C2 │
└────┘                └────┘

┌────┐                ┌────┐
│ D1 │←───────────────│ D2 │
└────┘                └────┘
```

**隱性投票判定**：
- A2 的 ancestors 包含 A1 → A2 對 Leader A1 投了票 ✓
- B2 的 ancestors 包含 A1 → B2 對 Leader A1 投了票 ✓
- C2 的 ancestors 包含 A1 → C2 對 Leader A1 投了票 ✓
- D2 的 ancestors 包含 A1 → D2 對 Leader A1 投了票 ✓

→ 4/4 投票（100% > 67%）→ Leader A1 有足夠的 votes

**Fastpath 判定**（交易層面）：
- `TransactionCertifier` 聚合 Tx_Ming 的投票：
  - A（提出者，隱含接受）+ B 接受 + C 接受 + D 接受 = 4/4
  - 達到 quorum → **FastpathCertified** ✓
  - → `ConsensusTxStatusCache` 設為 FastpathCertified
  - → 小明的 `wait_for_effects` 可以提前收到暫時確認

---

### Round 3 — 決定輪

每個 Validator 再出一個 block，引用 Round 2 的 blocks。
直覺上會覺得：「Round 2 大家都引用了 A1，投票已經夠了啊，為什麼還要 Round 3？」
原因是：每個 Validator 在 Round 2 結束時，只知道「自己」投了票，不知道「別人」投了沒有。
用一個對話來解釋：

```
Round 2 結束後，每個 Validator 腦中想的事：

Validator B：「我的 B2 引用了 A1 ✓，但 C 和 D 有引用 A1 嗎？我不知道啊！
              我自己的 B2 才剛廣播出去，我還沒收到 C2 和 D2。」

Validator C：「我的 C2 引用了 A1 ✓，但 B 和 D 的 block 我還沒收到...」

Validator D：「我的 D2 引用了 A1 ✓，但其他人呢？我不確定。」
```

```
Round 3（Decision Round）

 ┌──────────────────────────────┐
 │ A3                          │
 │ ancestors: [A2, B2, C2, D2] │
 └──────────────────────────────┘

 ┌──────────────────────────────┐
 │ B3                          │
 │ ancestors: [A2, B2, C2, D2] │
 └──────────────────────────────┘

 ┌──────────────────────────────┐
 │ C3                          │
 │ ancestors: [A2, B2, C2, D2] │
 └──────────────────────────────┘

 ┌──────────────────────────────┐
 │ D3                          │
 │ ancestors: [A2, B2, C2, D2] │
 └──────────────────────────────┘
```

**Commit Rule 判定**（`try_direct_decide(A1)`）：

```
問題：A3 是不是 A1 的 certificate？
  → A3 引用了 A2, B2, C2, D2
  → A2 引用了 A1 → A2 是 A1 的 vote ✓
  → B2 引用了 A1 → B2 是 A1 的 vote ✓
  → C2 引用了 A1 → C2 是 A1 的 vote ✓
  → D2 引用了 A1 → D2 是 A1 的 vote ✓
  → A3 引用了 4 個 votes for A1 → A3 是 A1 的 certificate ✓

同理 B3, C3, D3 都是 A1 的 certificate

Certificate stake = A(25%) + B(25%) + C(25%) + D(25%) = 100%
100% > 67% → enough_leader_support = true

→ LeaderStatus::Commit(A1) → A1 被 commit！ 🎉
```

---

### Commit 與 Linearize

A1 被 commit 後，Linearizer 收集 Sub-DAG：

```
Linearizer::linearize_sub_dag(leader = A1)

步驟 1：從 A1 開始
  buffer = [A1]
  to_commit = []

步驟 2：處理 A1
  to_commit = [A1]
  A1 的 ancestors = [genesis]  ← genesis 不收集
  buffer = []  ← 空了，結束

結果：to_commit = [A1]
```

因為 A1 是 Round 1 的第一個 commit，它之前沒有未 committed 的 blocks（genesis 不算），所以 Sub-DAG 只包含 A1 自己。

```
CommittedSubDag {
    leader: A1,
    blocks: [A1],           // 包含 Tx_Ming
    timestamp_ms: ...,
    commit_ref: Commit#1,
}
```

**接下來如果 Round 4 的 leader（假設是 B4）也被 commit：**

```
Linearizer::linearize_sub_dag(leader = B4)

步驟 1：buffer = [B4]

步驟 2：處理 B4
  B4 的 ancestors = [A3, B3, C3, D3]
  A3, B3, C3, D3 都還未 committed → 加入 buffer

步驟 3：處理 A3
  A3 的 ancestors = [A2, B2, C2, D2]
  A2, B2, C2, D2 都還未 committed → 加入 buffer

步驟 4：處理 B3, C3, D3
  它們的 ancestors 和 A3 重疊 → 已經 marked as committed，跳過

步驟 5：處理 A2, B2, C2, D2
  它們的 ancestors = [A1, B1, C1, D1]
  A1 已 committed → 跳過
  B1, C1, D1 還未 committed → 加入 buffer

步驟 6：處理 B1, C1, D1
  ancestors = [genesis] → 不收集

最終 to_commit（排序後）：
  B1 → C1 → D1 → A2 → B2 → C2 → D2 → A3 → B3 → C3 → D3 → B4
  ↑ Round 1      ↑ Round 2                ↑ Round 3            ↑ R4
  (author B<C<D)  (author A<B<C<D)         (author A<B<C<D)    (leader)
```

這就是第二個 commit 的 Sub-DAG。注意 B1, C1, D1 雖然不是 Leader，但因為它們是 B4 的因果歷史的一部分且之前沒被 commit 過，所以被一起收集進來。

**最終的全網交易順序**：

```
Commit #1: [Tx_Ming]           ← 從 A1
Commit #2: [Tx_X, Tx_Y, ...]  ← 從 B1, C1, D1, ..., B4

所有 Validator 看到的順序完全一致！
```

---

### 範例：交易被拒絕的情況

假設小明的交易簽名無效：

```
Round 1：A 把 Tx_Ming 打包進 A1 並廣播

Round 2：
  B 收到 A1 → SuiTxValidator::vote_transaction(Tx_Ming)
    → verify_transaction() ✗ 簽名無效！
    → 投票：拒絕 ✗

  C 收到 A1 → vote_transaction(Tx_Ming) → 拒絕 ✗
  D 收到 A1 → vote_transaction(Tx_Ming) → 拒絕 ✗

  B2 的 transaction_votes: [{block: A1, rejects: [0]}]  ← 拒絕 A1 的第 0 筆交易
  C2 的 transaction_votes: [{block: A1, rejects: [0]}]
  D2 的 transaction_votes: [{block: A1, rejects: [0]}]

TransactionCertifier 聚合：
  接受：A（提出者，隱含接受）= 25%
  拒絕：B + C + D = 75%
  75% > 67% → Rejected

  → ConsensusTxStatusCache 設為 Rejected
  → wait_for_effects 回傳 Rejected
  → 小明的交易失敗

注意：A1 這個 block 本身仍然可以被 commit（block 有效，只是裡面的某筆交易被拒絕）
     被拒絕的交易在 ConsensusHandler 的 filter 階段會被標記，不會進入執行
```

---

### 範例：Leader 被 Skip 的情況

假設 Validator A 離線了，沒有出 block：

```
Round 1（A 是 Leader，但 A 離線）

  A1 不存在（A 沒出 block）

  ┌────┐  ┌────┐  ┌────┐
  │ B1 │  │ C1 │  │ D1 │    ← 只有 B, C, D 出了 block
  └────┘  └────┘  └────┘

Round 2：
  B2 ancestors: [B1, C1, D1]     ← 沒有 A1（A 離線）
  C2 ancestors: [B1, C1, D1]     ← 沒有 A1
  D2 ancestors: [B1, C1, D1]     ← 沒有 A1

  沒有任何 block 引用 A1 → A1 沒有任何 vote

Round 3：
  try_direct_decide(A1) →
    → 檢查 blame: voting round 的 blocks 有沒有「不引用 A」的？
    → B2 沒引用 A1（A 離線，B 沒看到 A1）
    → C2 沒引用 A1
    → D2 沒引用 A1
    → 3 個 non-votes = 75% > 67%
    → enough_leader_blame = true
    → LeaderStatus::Skip(A1)

  A1 被跳過，不影響共識推進！
  → 下一個 wave 的 leader（假設是 B4）會正常 commit
  → B1, C1, D1 的交易會跟著 B4 的 Sub-DAG 一起被 commit
```

---

### 範例：Indirect Decide

有時候 leader 在 decision round 還無法判定（既不夠 support 也不夠 blame），
這時可以透過後來的 committed leader 間接決定。

```
Round 1：A1 是 Leader
Round 2：只有 B2 和 C2 引用了 A1（2/4 = 50%，不夠 commit）
         D2 沒看到 A1（網路延遲）
Round 3：Decision round
         只有 2 個 certificates → 50% < 67% → Undecided

         但 D2 也沒 blame A1（D 只是延遲，不是故意不引用）
         所以也不夠 skip（只有 1 個 non-vote = 25% < 67%）
         → LeaderStatus::Undecided(A1)

Round 4：B4 是新的 Leader
Round 5：所有人都引用 B4
Round 6：B4 被 Direct Commit ✓

現在用 B4 作為 anchor 來間接決定 A1：
  try_indirect_decide(A1, anchor = B4)

  → B4 的因果歷史包含了 A1 嗎？
  → B4 → B3 → B2 → A1 ✓ （B2 引用了 A1）
  → 是！B4 support A1
  → LeaderStatus::Commit(A1) → 間接 commit ✓

  如果 B4 的因果歷史不包含 A1（例如所有 R2 blocks 都沒引用 A1）：
  → LeaderStatus::Skip(A1) → 間接 skip
```

```
視覺化：

R1      R2      R3      R4      R5      R6
A1★     A2      A3      A4      A5      A6
 ╲     ╱ ╲             ╱ ╲             ╱
B1───→B2───→B3───→B4★───→B5───→B6
 ╱     ╲ ╱             ╲ ╱             ╲
C1───→C2───→C3───→C4───→C5───→C6
              ╲                 ╲
D1      D2───→D3───→D4───→D5───→D6

A1 在 R3 時 Undecided（support 不夠，blame 也不夠）
B4 在 R6 被 Direct Commit
→ A1 被 Indirect Commit（因為 B4 的因果歷史包含 A1）
```

---

## DAG — 核心資料結構

### Block 的定義

Block 是 DAG 的基本單元。每個 Validator 每輪產出一個 block。

```rust
// consensus/core/src/block.rs

pub trait BlockAPI {
    fn epoch(&self) -> Epoch;              // 所屬 epoch
    fn round(&self) -> Round;              // 所在輪次
    fn author(&self) -> AuthorityIndex;    // 出塊的 Validator
    fn timestamp_ms(&self) -> BlockTimestampMs;  // 時間戳
    fn ancestors(&self) -> &[BlockRef];    // 引用的前輪 blocks（核心！）
    fn transactions(&self) -> &[Transaction];    // 包含的交易
    fn commit_votes(&self) -> &[CommitVote];     // 對 commit 的投票
    fn transaction_votes(&self) -> &[BlockTransactionVotes];  // 對交易的投票（fastpath）
}
```

Block 有兩個版本：

```rust
// consensus/core/src/block.rs

// V1：基本版本
struct BlockV1 {
    epoch: Epoch,
    round: Round,
    author: AuthorityIndex,
    timestamp_ms: BlockTimestampMs,
    ancestors: Vec<BlockRef>,          // 引用列表
    transactions: Vec<Transaction>,    // 交易列表
    commit_votes: Vec<CommitVote>,     // commit 投票
    misbehavior_reports: Vec<MisbehaviorReport>,
}

// V2：支援 fastpath 的版本，多了交易投票
struct BlockV2 {
    // ... 同 V1 的所有欄位 ...
    transaction_votes: Vec<BlockTransactionVotes>,  // 對其他 block 中交易的投票
}
```

`BlockRef` 是 block 的唯一標識：

```rust
// consensus/types/src/block.rs

pub struct BlockRef {
    pub round: Round,              // 輪次
    pub author: AuthorityIndex,    // 作者
    pub digest: BlockDigest,       // 內容雜湊
}
```

交易投票結構（用於 fastpath）：

```rust
// consensus/core/src/block.rs

struct BlockTransactionVotes {
    block_ref: BlockRef,                   // 被投票的 block
    rejects: Vec<TransactionIndex>,        // 拒絕的交易索引（其餘隱含為接受）
}
```

---

### Block 的建構流程

`Core::try_propose_block()` 是出塊的核心函式：

```rust
// consensus/core/src/core.rs — try_propose_block()

fn try_propose_block(&mut self, force: bool) -> Option<ExtendedBlock> {
    // 1. 確認可以出塊的輪次
    let clock_round = self.threshold_clock.get_round();

    // 2. 確認 leader 已存在（避免太早出塊）
    if !self.leaders_exist(quorum_round) {
        return None;
    }

    // 3. 智慧選擇要引用的 ancestors
    let (ancestors, excluded) = self.smart_ancestors_to_propose(clock_round, !force);

    // 4. 從交易佇列中拉取待打包的交易
    let (transactions, ack_transactions, _) = self.transaction_consumer.next();

    // 5. 收集對其他 block 中交易的投票（fastpath）
    let transaction_votes = if self.context.protocol_config.mysticeti_fastpath() {
        self.transaction_certifier.get_own_votes(new_causal_history)
    } else {
        vec![]
    };

    // 6. 建構 Block
    let block = Block::V2(BlockV2::new(
        self.context.committee.epoch(),
        clock_round,                                         // 輪次
        self.context.own_index,                              // 自己的 ID
        now,                                                 // 時間戳
        ancestors.iter().map(|b| b.reference()).collect(),   // 引用列表
        transactions,                                        // 交易
        commit_votes,                                        // commit 投票
        transaction_votes,                                   // 交易投票
        vec![],                                              // 行為報告
    ));

    // 7. 簽名
    let signed_block = SignedBlock::new(block, &self.block_signer)
        .expect("Block signing failed.");

    // 8. 驗證並加入本地 DAG
    let verified_block = VerifiedBlock::new_verified(signed_block, serialized);

    // 9. 加入 TransactionCertifier（追蹤 fastpath 投票狀態）
    self.transaction_certifier
        .add_voted_blocks(vec![(verified_block.clone(), vec![])]);

    // 10. 持久化到 DagState
    self.dag_state.write().flush();

    // 11. 回傳，等待 Broadcaster 廣播
    Some(ExtendedBlock { block: verified_block, excluded_ancestors })
}
```

**智慧選擇 Ancestors**：

```rust
// consensus/core/src/core.rs — smart_ancestors_to_propose()

fn smart_ancestors_to_propose(&mut self, clock_round: Round, smart_select: bool)
    -> (Vec<VerifiedBlock>, BTreeSet<BlockRef>)
{
    // 取得每個 authority 在 clock_round 之前的最新 block
    let all_ancestors = self.dag_state.read()
        .get_last_cached_block_per_authority(clock_round);

    // 根據 propagation score 決定是否引用某個 authority 的 block
    // → 如果某個 Validator 的 block 經常延遲（score 低），可能暫時不引用
    // → 這是一種激勵機制：表現差的 Validator 的 block 會被排除
    let ancestor_state_map = self.ancestor_state_manager.get_ancestor_states();

    // 一定包含自己的上一個 block（保證自己的歷史連續）
    let included_ancestors = iter::once(self.last_proposed_block().clone())
        .chain(/* 過濾後的其他 Validator 的 blocks */);
}
```

---

### Block 的廣播

`Broadcaster` 負責將新建的 block 推送給所有其他 Validator：

```rust
// consensus/core/src/broadcaster.rs

pub(crate) struct Broadcaster {
    senders: JoinSet<()>,  // 每個 peer 一個背景任務
}

impl Broadcaster {
    pub(crate) fn new<C: NetworkClient>(
        context: Arc<Context>,
        network_client: Arc<C>,
        signals_receiver: &CoreSignalsReceivers,
    ) -> Self {
        let mut senders = JoinSet::new();
        // 為每個非自己的 Validator 建立一個發送任務
        for (index, _authority) in context.committee.authorities() {
            if index == context.own_index {
                continue;  // 不送給自己
            }
            senders.spawn(Self::push_blocks(
                context.clone(),
                network_client.clone(),
                signals_receiver.block_broadcast_receiver(),
                index,
            ));
        }
        Self { senders }
    }

    /// 持續監聽新 block 並推送給目標 peer
    async fn push_blocks<C: NetworkClient>(
        context: Arc<Context>,
        network_client: Arc<C>,
        mut rx_block_broadcast: broadcast::Receiver<ExtendedBlock>,
        peer: AuthorityIndex,
    ) {
        let mut last_block: Option<VerifiedBlock> = None;

        // 使用指數退避的 RTT 估計來調整 timeout
        let mut rtt_estimate = Duration::from_millis(200);

        loop {
            tokio::select! {
                // 收到新 block → 立即推送
                Ok(extended_block) = rx_block_broadcast.recv() => {
                    last_block = Some(extended_block.block.clone());
                    // 透過 gRPC 送給 peer
                    network_client.send_block(peer, &extended_block.block, timeout).await;
                }
                // 沒有新 block → 定期重送最後一個 block（確保 peer 收到）
                _ = retry_timer.tick() => {
                    if let Some(block) = &last_block {
                        network_client.send_block(peer, block, timeout).await;
                    }
                }
            }
        }
    }
}
```

收到其他 Validator 的 block 後，`BlockManager` 負責處理：

```rust
// consensus/core/src/block_manager.rs

pub(crate) struct BlockManager {
    dag_state: Arc<RwLock<DagState>>,
    // 暫存缺少因果歷史的 blocks
    suspended_blocks: BTreeMap<BlockRef, SuspendedBlock>,
    // 記錄缺少的 ancestor blocks
    missing_ancestors: BTreeMap<BlockRef, BTreeSet<BlockRef>>,
    missing_blocks: BTreeSet<BlockRef>,
}

impl BlockManager {
    /// 嘗試接受 blocks。如果因果歷史完整就接受；否則暫存等待
    pub(crate) fn try_accept_blocks(&mut self, blocks: Vec<VerifiedBlock>)
        -> (Vec<VerifiedBlock>, BTreeSet<BlockRef>)
    {
        // 對每個 block：
        //   1. 檢查它引用的 ancestors 是否都已經存在
        //   2. 如果都存在 → 接受，加入 DagState
        //   3. 如果有缺少的 → 暫存，等缺少的 block 到了再處理
        //   4. 接受一個 block 後，可能會 unsuspend 之前暫存的 blocks（連鎖反應）
    }
}
```

---

## 投票機制

Mysticeti 有兩層投票，作用不同：

```
┌─────────────────────────────────────────────────────────┐
│ 第一層：DAG 層 — 隱性投票                                 │
│   引用一個 block = 承認它存在且有效                        │
│   作用：決定 block 是否能被 commit                         │
│                                                           │
│ 第二層：交易層 — 顯性投票（SuiTxValidator）                │
│   對 block 中的每筆交易投票接受/拒絕                       │
│   作用：決定交易是否能走 fastpath（搶先執行）               │
└─────────────────────────────────────────────────────────┘
```

### 隱性投票 — 引用即投票

每個 block 都有一個 `ancestors` 欄位，列出它引用的前輪 blocks。引用某個 block 就表示「我看到了這個 block，而且我認為它是有效的」。

```
Round 1        Round 2
┌────┐         ┌────┐
│ A1 │←────────│ A2 │   A2 引用了 A1 和 B1
└────┘    ╱    └────┘   = A 投票說「A1 和 B1 有效」
         ╱
┌────┐  ╱
│ B1 │←╱
└────┘

如果 C2 沒有引用 A1：
= C 沒看到 A1、或者認為 A1 無效
```

判定投票的程式碼在 `BaseCommitter::is_vote()`：

```rust
// consensus/core/src/base_committer.rs

/// 檢查 potential_vote 是否對 leader_block 投了票
fn is_vote(&self, potential_vote: &VerifiedBlock, leader_block: &VerifiedBlock) -> bool {
    let reference = leader_block.reference();
    let leader_slot = Slot::from(reference);
    // 在 potential_vote 的 ancestor 鏈中找到 leader_slot 的 block
    // 如果找到的 block 和 leader_block 是同一個 → 投了票
    self.find_supported_block(leader_slot, potential_vote) == Some(reference)
}
```

判定 certificate（2/3+ 投票）的程式碼：

```rust
// consensus/core/src/base_committer.rs

/// 檢查 potential_certificate 是否是 leader_block 的 certificate
fn is_certificate(
    &self,
    potential_certificate: &VerifiedBlock,
    leader_block: &VerifiedBlock,
    all_votes: &mut HashMap<BlockRef, bool>,
) -> bool {
    let mut votes_stake_aggregator = StakeAggregator::<QuorumThreshold>::new();

    for reference in potential_certificate.ancestors() {
        let potential_vote = self.dag_state.read().get_block(reference);
        let is_vote = if let Some(potential_vote) = potential_vote {
            self.is_vote(&potential_vote, leader_block)
        } else {
            false
        };

        if is_vote {
            // 累積投票的 stake
            if votes_stake_aggregator.add(reference.author, &self.context.committee) {
                return true;  // 達到 2/3+ stake = certificate!
            }
        }
    }
    false
}
```

### 顯性投票 — SuiTxValidator

在 Mysticeti 引擎內部，每個 Validator 收到其他人的 block 時，會呼叫 `SuiTxValidator` 對 block 中的每筆交易做驗證投票：

```rust
// crates/sui-core/src/consensus_validator.rs

impl TransactionVerifier for SuiTxValidator {
    /// 對 block 中的每筆交易投票
    fn vote_transactions(
        &self,
        block_ref: &BlockRef,
        txs: Vec<ConsensusTransactionKind>,
    ) -> Vec<TransactionIndex> {
        let mut reject_txn_votes = Vec::new();

        for (i, tx) in txs.into_iter().enumerate() {
            if let Err(error) = self.vote_transaction(epoch_store, tx) {
                // 投票拒絕 → 記錄索引
                reject_txn_votes.push(i as TransactionIndex);
            }
            // 不在拒絕列表中 = 隱含投票接受
        }

        reject_txn_votes  // 回傳要拒絕的交易索引列表
    }

    /// 對單筆交易做詳細驗證
    fn vote_transaction(&self, epoch_store, tx) -> SuiResult<()> {
        // 1. 交易格式合法性
        inner_tx.validity_check(&epoch_store.tx_validity_check_context())?;

        // 2. 系統是否過載
        self.authority_state.check_system_overload(...)?;

        // 3. 簽名驗證
        let verified_tx = epoch_store.verify_transaction_with_current_aliases(inner_tx)?;

        // 4. 地址別名一致性檢查
        if !aliases_match {
            return Err(SuiErrorKind::AliasesChanged.into());
        }

        // 5. Owned object 版本驗證
        self.authority_state.handle_vote_transaction(epoch_store, inner_tx)?;

        Ok(())  // 全部通過 = 投票接受
    }
}
```

投票結果會被包含在下一個 block 的 `transaction_votes` 欄位中。

### Fastpath 快速確認

`TransactionCertifier` 負責聚合交易投票，實現快速確認：

```rust
// consensus/core/src/transaction_certifier.rs

pub struct TransactionCertifier {
    certifier_state: Arc<RwLock<CertifierState>>,
    dag_state: Arc<RwLock<DagState>>,
    certified_blocks_sender: UnboundedSender<CertifiedBlocksOutput>,
}
```

工作原理：

```
Validator A 出 block（包含 Tx1）
    │
    ▼
Validator B 收到 → vote_transactions() → 接受 Tx1
Validator C 收到 → vote_transactions() → 接受 Tx1
Validator D 收到 → vote_transactions() → 接受 Tx1
    │
    ▼
TransactionCertifier 聚合投票：
    ├─ A 接受（隱含，因為是 A 提出的）
    ├─ B 接受
    ├─ C 接受
    ├─ D 接受
    └─ 達到 2/3+ stake → FastpathCertified！

    → 通知 Sui 層的 ConsensusTxStatusCache
    → wait_for_effects 可以提前回傳給用戶端
    （但這不是最終結果，最終要等 commit + 執行）
```

重要特性：

- **接受投票是隱含的**：如果一個 block 引用了包含某筆交易的 block，且沒有在 `transaction_votes.rejects` 中列出該交易，就視為接受
- **拒絕投票是顯式的**：只有被拒絕的交易會被明確列出
- **Fastpath 是延遲優化**：讓用戶端更快得到確認，但不影響最終的正確性

---

## Commit Rule — 確認不可逆

### Wave 結構

Mysticeti 的 commit rule 以 **wave**（波）為單位運作。每個 wave 包含 3 輪：

```
Wave 0                    Wave 1                    Wave 2
┌────────────────────┐    ┌────────────────────┐    ┌────────────────────┐
│ R0     R1     R2   │    │ R3     R4     R5   │    │ R6     R7     R8   │
│Leader Voting Decide│    │Leader Voting Decide│    │Leader Voting Decide│
└────────────────────┘    └────────────────────┘    └────────────────────┘
```

```rust
// consensus/core/src/commit.rs

/// 最少 3 輪：leader round + voting round + decision round
pub(crate) const MINIMUM_WAVE_LENGTH: Round = 3;
pub(crate) const DEFAULT_WAVE_LENGTH: Round = MINIMUM_WAVE_LENGTH;
```

每個 wave 的角色：

| 輪次 | 名稱 | 作用 |
|---|---|---|
| Leader Round | Leader 被選出 | 由 `LeaderSchedule` 選出這輪的 Leader |
| Voting Round | 投票 | 其他 Validator 出 block 引用（或不引用）Leader |
| Decision Round | 決定 | 檢查投票是否達到 2/3+，決定 commit 或 skip |

```rust
// consensus/core/src/base_committer.rs

/// Leader 輪次 = wave * wave_length + round_offset
pub(crate) fn leader_round(&self, wave: WaveNumber) -> Round {
    (wave * self.options.wave_length) + self.options.round_offset
}

/// Decision 輪次 = leader 輪次 + wave_length - 1
pub(crate) fn decision_round(&self, wave: WaveNumber) -> Round {
    let wave_length = self.options.wave_length;
    (wave * wave_length) + wave_length - 1 + self.options.round_offset
}
```

### Direct Decide — 直接決定

直接決定是最常見的 commit 方式：

```
R0 (Leader)    R1 (Voting)      R2 (Decision)

  ┌──────┐       ┌──────┐         ┌──────┐
  │ A: L │←──────│ A: V │←────────│ A: D │
  └──────┘  ╱    └──────┘    ╱    └──────┘
            ╱                ╱
  ┌──────┐╱      ┌──────┐  ╱      ┌──────┐
  │ B    │←──────│ B: V │←╱───────│ B: D │
  └──────┘  ╲    └──────┘    ╲    └──────┘
            ╲                ╲
  ┌──────┐   ╲   ┌──────┐    ╲    ┌──────┐
  │ C    │←──────│ C: V │←────────│ C: D │
  └──────┘       └──────┘         └──────┘

L = Leader block
V = 引用了 Leader 的 block（vote for leader）
D = 引用了至少一個 V 的 block（certificate）

判定：D 在 decision round，引用了 V（V 引用了 L）
如果有 2/3+ 的 D 都引用了 vote for L 的 V → commit L
```

程式碼：

```rust
// consensus/core/src/base_committer.rs

pub fn try_direct_decide(&self, leader: Slot) -> LeaderStatus {
    // 1. 檢查是否有足夠的 blame（2f+1 non-votes → skip leader）
    let voting_round = leader.round + 1;
    if self.enough_leader_blame(voting_round, leader.authority) {
        return LeaderStatus::Skip(leader);
    }

    // 2. 檢查是否有足夠的 support（2f+1 certificates → commit leader）
    let wave = self.wave_number(leader.round);
    let decision_round = self.decision_round(wave);
    let leader_blocks = self.dag_state.read()
        .get_uncommitted_blocks_at_slot(leader);

    let mut leaders_with_enough_support: Vec<_> = leader_blocks
        .into_iter()
        .filter(|l| self.enough_leader_support(decision_round, l))
        .map(LeaderStatus::Commit)
        .collect();

    // 3. 最多一個 leader 有足夠 support（否則 BFT 假設被破壞）
    if leaders_with_enough_support.len() > 1 {
        panic!("More than one candidate for {leader}");
    }

    leaders_with_enough_support
        .pop()
        .unwrap_or(LeaderStatus::Undecided(leader))
}
```

其中 `enough_leader_support` 的邏輯：

```rust
// consensus/core/src/base_committer.rs

/// 檢查在 decision_round 中是否有 2/3+ 的 blocks 是 leader_block 的 certificate
fn enough_leader_support(&self, decision_round: Round, leader_block: &VerifiedBlock) -> bool {
    let mut all_votes: HashMap<BlockRef, bool> = HashMap::new();
    let mut certificate_stake_aggregator = StakeAggregator::<QuorumThreshold>::new();

    let decision_blocks = self.dag_state.read()
        .get_uncommitted_blocks_at_round(decision_round);

    for decision_block in &decision_blocks {
        // 檢查每個 decision block 是否是 leader 的 certificate
        if self.is_certificate(decision_block, leader_block, &mut all_votes) {
            // 累積 certificate 的 stake
            if certificate_stake_aggregator.add(
                decision_block.author(), &self.context.committee
            ) {
                return true;  // 達到 quorum → 有足夠 support
            }
        }
    }
    false
}
```

### Indirect Decide — 間接決定

如果直接決定無法做出判斷（Undecided），可以透過之後的 committed leader 間接決定：

```rust
// consensus/core/src/base_committer.rs

pub fn try_indirect_decide<'a>(
    &self,
    leader_slot: Slot,
    leaders: impl Iterator<Item = &'a LeaderStatus>,
) -> LeaderStatus {
    // 找到第一個已 committed 且 round 足夠高的 anchor leader
    let anchors = leaders.filter(|x|
        leader_slot.round + self.options.wave_length <= x.round()
    );

    for anchor in anchors {
        match anchor {
            LeaderStatus::Commit(anchor) => {
                // 用 anchor 來間接決定 leader_slot
                return self.decide_leader_from_anchor(anchor, leader_slot);
            }
            LeaderStatus::Skip(..) => (),      // 跳過的 leader 不能當 anchor
            LeaderStatus::Undecided(..) => break,  // 遇到 undecided 就停
        }
    }
    LeaderStatus::Undecided(leader_slot)
}
```

### UniversalCommitter — 統一 Commit 入口

`UniversalCommitter` 把直接和間接決定整合在一起：

```rust
// consensus/core/src/universal_committer.rs

impl UniversalCommitter {
    pub(crate) fn try_decide(&self, last_decided: Slot) -> Vec<DecidedLeader> {
        let highest_accepted_round = self.dag_state.read().highest_accepted_round();
        let mut leaders = VecDeque::new();

        // 從高輪次往低輪次嘗試 commit
        // 只需要檢查到 highest_accepted_round - 2（因為 commit 需要 3 輪）
        for round in (last_round..=highest_accepted_round.saturating_sub(2)).rev() {
            for committer in self.committers.iter().rev() {
                let Some(slot) = committer.elect_leader(round) else {
                    continue;
                };

                if slot == last_decided {
                    break;  // 已經到達上次 commit 的位置
                }

                // 先嘗試直接決定
                let mut status = committer.try_direct_decide(slot);

                if status.is_decided() {
                    leaders.push_front((status, Decision::Direct));
                } else {
                    // 直接決定不了 → 嘗試間接決定
                    status = committer.try_indirect_decide(
                        slot,
                        leaders.iter().map(|(x, _)| x),
                    );
                    leaders.push_front((status, Decision::Indirect));
                }
            }
        }

        // 回傳最長的 decided 前綴序列
        leaders.into_iter()
            .take_while(|(leader, _)| leader.is_decided())
            .filter_map(|(leader, decision)| leader.into_decided_leader(/* ... */))
            .collect()
    }
}
```

---

## Linearizer — DAG 線性化

Commit 產出的是一個 **Sub-DAG**（一組 blocks），但交易執行需要一個**確定的全序**。Linearizer 負責將 Sub-DAG 壓平成一維的交易列表。

### 收集 Sub-DAG

```rust
// consensus/core/src/linearizer.rs

pub(crate) fn linearize_sub_dag(
    leader_block: VerifiedBlock,
    dag_state: &mut impl BlockStoreAPI,
) -> Vec<VerifiedBlock> {
    let gc_round = dag_state.gc_round();
    let leader_block_ref = leader_block.reference();
    let mut buffer = vec![leader_block];
    let mut to_commit = Vec::new();

    // 從 leader block 開始，遞歸收集所有未 committed 的 ancestors
    dag_state.set_committed(&leader_block_ref);

    while let Some(x) = buffer.pop() {
        to_commit.push(x.clone());

        // 找到 x 的所有未 committed 且 round > gc_round 的 ancestors
        let ancestors: Vec<VerifiedBlock> = dag_state
            .get_blocks(
                &x.ancestors().iter().copied()
                    .filter(|ancestor| {
                        ancestor.round > gc_round       // 沒被 GC
                        && !dag_state.is_committed(ancestor)  // 沒被之前 commit
                    })
                    .collect::<Vec<_>>(),
            )
            .into_iter()
            .map(|opt| opt.expect("block should exist"))
            .collect();

        for ancestor in ancestors {
            buffer.push(ancestor.clone());
            dag_state.set_committed(&ancestor.reference());
        }
    }

    // 排序
    sort_sub_dag_blocks(&mut to_commit);
    to_commit
}
```

### 排序規則

```rust
// consensus/core/src/commit.rs

pub fn sort_sub_dag_blocks(blocks: &mut [VerifiedBlock]) {
    blocks.sort_by(|a, b| {
        // 1. 先按 round 排序（低 round 在前）
        a.round().cmp(&b.round())
            // 2. 同 round 按 author 排序
            .then_with(|| a.author().cmp(&b.author()))
    });
}
```

視覺化：

```
Sub-DAG（commit leader B3 時收集到的 blocks）：

        ┌────┐
        │ B3 │ ← Leader（round 3）
        └──┬─┘
       ╱   │   ╲
   ┌────┐ ┌────┐ ┌────┐
   │ A2 │ │ B2 │ │ C2 │  （round 2，之前未被 commit 的）
   └────┘ └────┘ └────┘
       ╲   │   ╱
        ┌────┐
        │ C1 │              （round 1，之前未被 commit 的）
        └────┘

Linearize 後的全序：
  C1 → A2 → B2 → C2 → B3
  ↑      ↑              ↑
  round 1  round 2        round 3
  (author C) (A < B < C)  (leader)
```

---

## 共識輸出 — CommittedSubDag

Linearizer 產出的最終結構：

```rust
// consensus/core/src/commit.rs

pub struct CommittedSubDag {
    /// 這次 commit 的 leader block reference
    pub leader: BlockRef,
    /// 已排序的 blocks 列表（包含交易）
    pub blocks: Vec<VerifiedBlock>,
    /// Commit 的時間戳
    pub timestamp_ms: BlockTimestampMs,
    /// Commit reference
    pub commit_ref: CommitRef,
}
```

這個結構會被送到 Sui 層的 `ConsensusHandler` 處理。

---

## Sui 與共識層的整合

### 交易提交入口

```
Sui 層                              共識層
───────                             ───────
ValidatorService                    
  │ submit_transaction()            
  ▼                                 
ConsensusAdapter                    
  │ submit_batch()                  
  ▼                                 
LazyMysticetiClient                 
  │ submit()                        
  ▼                                 
TransactionClient ──────────────→ TransactionConsumer
                                    │ next() → 拉取交易
                                    ▼
                                  Core::try_propose_block()
                                    │ 打包進 block
                                    ▼
                                  Broadcaster::push_blocks()
                                    │ 廣播給所有 Validator
                                    ▼
                                  ... DAG + Commit ...
                                    │
                                    ▼
                                  CommittedSubDag
CommitConsumer ←──────────────── 共識輸出通道
  │
  ▼
ConsensusHandler
  │ handle_consensus_commit()
  ▼
ExecutionScheduler → AuthorityState
```

提交程式碼：

```rust
// crates/sui-core/src/mysticeti_adapter.rs

impl LazyMysticetiClient {
    pub async fn submit(
        &self,
        transactions: Vec<ConsensusTransaction>,
        epoch_store: &Arc<AuthorityPerEpochStore>,
    ) -> SuiResult<(Vec<ConsensusPosition>, oneshot::Receiver<BlockStatus>)> {
        // 序列化交易
        let transactions_bytes = transactions.iter()
            .map(|t| bcs::to_bytes(t).expect("Serialization should not fail."))
            .collect::<Vec<_>>();

        // 透過 TransactionClient 提交到共識引擎
        let (block_ref, transaction_indices, status_receiver) =
            self.client.submit(transactions_bytes).await?;

        // 構建 ConsensusPosition（交易在共識中的「座位號碼」）
        let positions = transaction_indices.into_iter()
            .map(|index| ConsensusPosition {
                epoch: epoch_store.epoch(),
                block: block_ref,
                index,
            })
            .collect();

        Ok((positions, status_receiver))
    }
}
```

### 共識輸出處理

```rust
// crates/sui-core/src/consensus_handler.rs

pub async fn handle_consensus_commit(&mut self, consensus_commit: impl ConsensusCommitAPI) {
    // 1. 等待背壓解除（如果執行層太慢）
    self.backpressure_subscriber.await_no_backpressure().await;

    // 2. 過濾無效交易
    let filtered = self.filter_consensus_txns(..., &consensus_commit);

    // 3. 去重（同一筆交易可能被多個 Validator 提交）
    let transactions = self.deduplicate_consensus_txns(&mut state, ...);

    // 4. 分類交易
    let input = self.build_commit_handler_input(transactions);
    //   ├─ user_transactions       用戶交易
    //   ├─ checkpoint_signatures   checkpoint 簽名
    //   ├─ randomness_dkg          隨機數相關
    //   └─ end_of_publish          epoch 結束信號

    // 5. 為 shared objects 分配確定的版本號
    self.process_transactions(&mut state, ...);
    //   → SharedObjectVersionManager 統一分配

    // 6. 設定交易最終狀態
    //   → ConsensusTxStatus::Finalized
    //   → 通知 wait_for_effects
}
```

---

## Epoch 生命週期

共識引擎以 epoch 為單位運作。每次 epoch 切換：

```
舊 Epoch 結束
  │
  ├─ 1. 停止接受新交易
  ├─ 2. 等待所有待執行交易完成
  ├─ 3. ConsensusManager::shutdown()
  │     ├─ self.client.clear()          停止接受新交易
  │     ├─ authority.stop().await       關閉 Mysticeti 引擎
  │     └─ handler.abort().await        停止 ConsensusHandler
  │
  ▼
新 Epoch 開始
  │
  ├─ 1. 載入新的 committee（Validator 集合可能變動）
  ├─ 2. ConsensusManager::start()
  │     ├─ ConsensusAuthority::start()  啟動新的 Mysticeti 實例
  │     │   ├─ 初始化 Core、BlockManager、DagState
  │     │   ├─ 啟動 Broadcaster
  │     │   ├─ 啟動 Synchronizer
  │     │   └─ 啟動 CommitSyncer
  │     └─ self.client.set(client)      開始接受新交易
  └─ 3. 恢復接受交易
```

```rust
// consensus/core/src/authority_node.rs

pub enum ConsensusAuthority {
    WithTonic(AuthorityNode<TonicManager>),
}

impl ConsensusAuthority {
    pub async fn start(
        network_type: NetworkType,
        own_index: AuthorityIndex,
        committee: Committee,
        parameters: Parameters,
        protocol_config: ProtocolConfig,
        protocol_keypair: ProtocolKeyPair,
        network_keypair: NetworkKeyPair,
        clock: Arc<Clock>,
        transaction_verifier: Arc<dyn TransactionVerifier>,  // = SuiTxValidator
        commit_consumer: CommitConsumerArgs,
        registry: Registry,
        boot_counter: u64,
    ) -> Self {
        // 啟動完整的共識引擎
        let authority = AuthorityNode::start(/* ... */).await;
        Self::WithTonic(authority)
    }

    pub async fn stop(self) {
        match self {
            Self::WithTonic(authority) => authority.stop().await,
        }
    }
}
```

---

## 關鍵程式碼索引

### 共識引擎核心（consensus/core/src/）

| 檔案 | 元件 | 職責 |
|---|---|---|
| `core.rs` | `Core` | 共識核心邏輯：出塊、處理接收的 blocks、觸發 commit |
| `block.rs` | `Block`, `BlockV1`, `BlockV2` | Block 資料結構定義 |
| `broadcaster.rs` | `Broadcaster` | 廣播新建 block 給所有 peers |
| `block_manager.rs` | `BlockManager` | 管理收到的 blocks，處理因果依賴 |
| `dag_state.rs` | `DagState` | DAG 狀態管理（blocks、commits、GC） |
| `base_committer.rs` | `BaseCommitter` | 基礎 commit rule（直接/間接決定） |
| `universal_committer.rs` | `UniversalCommitter` | 統一 commit 入口，支援 pipeline |
| `linearizer.rs` | `Linearizer` | 將 committed Sub-DAG 線性化為全序 |
| `commit.rs` | `Commit`, `CommittedSubDag` | Commit 和 Sub-DAG 的資料結構 |
| `commit_observer.rs` | `CommitObserver` | 觀察 commit 並發送 Sub-DAG 到輸出通道 |
| `transaction.rs` | `TransactionClient`, `TransactionConsumer` | 交易提交與消費 |
| `transaction_certifier.rs` | `TransactionCertifier` | Fastpath 交易投票聚合與認證 |
| `authority_node.rs` | `ConsensusAuthority`, `AuthorityNode` | 共識節點入口與生命週期管理 |
| `leader_schedule.rs` | `LeaderSchedule` | Leader 選舉與排程 |
| `synchronizer.rs` | `Synchronizer` | 同步缺失的 blocks |
| `commit_syncer.rs` | `CommitSyncer` | 同步缺失的 commits |
| `ancestor.rs` | `AncestorStateManager` | 追蹤 ancestor 品質，決定是否引用 |
| `round_tracker.rs` | `RoundTracker` | 追蹤各 authority 的最高 round |

### Sui 整合層（crates/sui-core/src/）

| 檔案 | 元件 | 職責 |
|---|---|---|
| `consensus_validator.rs` | `SuiTxValidator` | 實作 `TransactionVerifier` trait，投票接受/拒絕交易 |
| `consensus_adapter.rs` | `ConsensusAdapter` | Sui 側提交交易到共識的入口 |
| `mysticeti_adapter.rs` | `LazyMysticetiClient` | 封裝 Mysticeti 的 `TransactionClient` |
| `consensus_handler.rs` | `ConsensusHandler` | 處理共識輸出（過濾、去重、分配版本號） |
| `consensus_manager/mod.rs` | `ConsensusManager` | 管理 Mysticeti 生命週期（啟動/關閉） |

### 共識類型（consensus/types/src/）

| 檔案 | 元件 | 職責 |
|---|---|---|
| `block.rs` | `BlockRef`, `Round`, `TransactionIndex` | 共識層和 Sui 層共享的基本類型 |

---

## 一句話總結

> Mysticeti 是一個 DAG-based BFT 共識協議。每個 Validator 持續廣播 block（包含交易 + 對其他 blocks 的引用），引用累積到 2/3+ stake 時 commit，Linearizer 將 commit 的 Sub-DAG 線性化為全網一致的交易全序，送給 Sui 的 ConsensusHandler 處理。
