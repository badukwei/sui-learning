# Abilities 與 Object Ownership 的關聯

## 核心問題

**Abilities 跟 Object Ownership 的關聯是什麼？有什麼類型的 Object 只能有特定的 Ability？**

## 🎯 關鍵關聯

### 1. Key Ability 決定物件地位

```move
// 有 key = 是 Sui Object，可以有所有權
public struct MyObject has key {
    id: UID,
    value: u64,
}

// 無 key = 不是 Sui Object，無法獨立存在
public struct MyData has store {
    value: u64,
}
```

**關鍵規則**：

-   **只有有 `key` 能力的 struct 才能成為 Sui Object**
-   **只有 Sui Object 才能有所有權狀態**
-   **沒有 `key` 的 struct 無法獨立擁有所有權**

### 2. Store Ability 影響包裝能力

```move
// 可以被包裝（有 store）
public struct Item has key, store {
    id: UID,
    name: String,
}

// 無法被包裝（無 store）
public struct Singleton has key {
    id: UID,
    config: String,
}
```

**包裝規則**：

-   **有 `store` 能力 → 可以成為 Wrapped Object**
-   **無 `store` 能力 → 只能是頂層物件**

## 📋 所有權類型 vs Abilities 對應表

| 所有權類型        | 必須的 Abilities | 可選的 Abilities        | 限制           |
| ----------------- | ---------------- | ----------------------- | -------------- |
| **Address-Owned** | `key`            | `store`, `copy`, `drop` | 無特殊限制     |
| **Immutable**     | `key`            | `store`, `copy`, `drop` | 凍結後無法修改 |
| **Party**         | `key`            | `store`, `copy`, `drop` | 共識版本控制   |
| **Shared**        | `key`            | `store`, `copy`, `drop` | 需要共識       |
| **Wrapped**       | `key` + `store`  | `copy`, `drop`          | 必須有 `store` |

## 🔒 特定限制和組合

### 1. Wrapped Objects 的強制要求

```move
// ✅ 正確：可以被包裝
public struct Sword has key, store {
    id: UID,
    power: u8,
}

public struct Hero has key {
    id: UID,
    sword: Sword,  // 可以包裝，因為 Sword 有 store
}

// ❌ 錯誤：無法被包裝
public struct GlobalConfig has key {  // 無 store 能力
    id: UID,
    setting: u64,
}

public struct Game has key {
    id: UID,
    config: GlobalConfig,  // 編譯錯誤！GlobalConfig 沒有 store
}
```

**包裝要求**：

-   **子物件必須有 `store` 能力才能被包裝**
-   **沒有 `store` 的物件只能作為頂層獨立物件**

### 2. UID 的特殊性

```move
// UID 有特殊的能力組合：沒有 copy 和 drop
public struct UID has store {}  // 注意：沒有 copy, drop

// 這意味著有 key 的 struct 自動無法有 copy 和 drop
public struct MyObject has key {
    id: UID,  // UID 沒有 copy/drop
    // 因此整個 struct 無法有 copy/drop
}
```

**UID 限制**：

-   **UID 沒有 `copy` 和 `drop` 能力**
-   **因此所有 Sui Object 都無法有 `copy` 和 `drop`**
-   **這確保了物件 ID 的唯一性**

### 3. 不同所有權的能力影響

#### Address-Owned Objects

```move
// 個人 Coin - 可以自由轉移
public struct MyCoin has key, store {
    id: UID,
    value: u64,
}

// 系統配置 - 只能由特定模組操作
public struct SystemConfig has key {  // 故意無 store
    id: UID,
    setting: u64,
}
```

#### Shared Objects

```move
// 商店 - 需要公開存取
public struct Shop has key {  // 通常無 store，避免被包裝
    id: UID,
    items: Table<ID, Item>,
}
```

#### Immutable Objects

```move
// 常數配置 - 設為不可變
public struct Constants has key {
    id: UID,
    pi: u64,
    max_supply: u64,
}

fun create_constants(ctx: &mut TxContext) {
    let constants = Constants {
        id: object::new(ctx),
        pi: 314159,
        max_supply: 1000000,
    };
    transfer::public_freeze_object(constants);  // 變為 Immutable
}
```

## 🎨 設計模式與能力選擇

### 1. 遊戲道具設計

```move
// 可交易道具 - 有 store
public struct TradableItem has key, store {
    id: UID,
    name: String,
    rarity: u8,
}

// 帳號綁定道具 - 無 store
public struct BoundItem has key {
    id: UID,
    name: String,
    owner: address,
}

// 角色系統
public struct Character has key {
    id: UID,
    tradable_items: vector<TradableItem>,    // 可包裝，因為有 store
    // bound_items: vector<BoundItem>,       // ❌ 無法包裝，沒有 store
}
```

### 2. 金融系統設計

```move
// 可轉移代幣 - 有 store
public struct Token has key, store {
    id: UID,
    amount: u64,
}

// 流動性池 - 無 store（避免被意外包裝）
public struct LiquidityPool has key {
    id: UID,
    token_a: u64,
    token_b: u64,
}
```

## 💡 關鍵洞察

### 1. 安全性考量

-   **無 `store` = 無法被包裝 = 增加安全性**
-   **系統級物件通常無 `store`，避免被意外操作**

### 2. 靈活性考量

-   **有 `store` = 可被包裝 = 增加組合靈活性**
-   **遊戲道具通常有 `store`，支援複雜組合**

### 3. 設計哲學

-   **Ability 設計應該反映物件的預期用途**
-   **所有權類型會自動限制某些操作**
-   **UID 的限制確保了物件身份的唯一性**

## 📚 總結

| 設計目標     | 推薦 Abilities   | 適合的所有權            |
| ------------ | ---------------- | ----------------------- |
| **個人資產** | `key, store`     | Address-Owned           |
| **系統配置** | `key` (無 store) | Address-Owned/Immutable |
| **遊戲道具** | `key, store`     | Address-Owned → Wrapped |
| **市場商店** | `key` (無 store) | Shared                  |
| **常數資料** | `key`            | Immutable               |
| **多人協作** | `key, store`     | Party                   |

**核心原則**：

1. **`key` 決定是否為 Sui Object**
2. **`store` 決定是否可被包裝**
3. **所有權類型決定存取和修改權限**
4. **UID 限制確保物件唯一性**
5. **能力組合應該反映設計意圖**
