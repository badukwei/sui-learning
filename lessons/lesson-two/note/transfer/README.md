# Restricted and Public Transfer 轉移權限控制

在 Sui Move 中，物件的轉移操作有著明確的權限控制機制。本文將深入探討限制性轉移和公開轉移的差異，以及 `store` 能力的重要性。

## 🔒 默認限制性操作

### 基本概念

在前面章節描述的存儲操作（Storage Operations）默認是受限制的：

-   **限制範圍**：只能在定義物件的模組內調用
-   **內部類型要求**：類型必須是模組內部的才能用於存儲操作
-   **執行層級**：此限制在 Sui 驗證器中實現，在字節碼層級強制執行

```move
module my_package::restricted_example {
    use sui::object::UID;
    use sui::transfer;

    struct MyObject has key {
        id: UID,
        data: String,
    }

    // ✅ 可以調用 - MyObject 是此模組內部類型
    public fun internal_transfer(obj: MyObject, to: address) {
        transfer::transfer(obj, to);
    }
}
```

## 🌐 公開轉移機制

### 解除限制的方法

為了允許物件在其他模組中被轉移和存儲，Sui 提供了放寬限制的機制。`sui::transfer` 模組提供了一組 `public_*` 函數，允許從其他模組調用存儲操作。

### 公開存儲操作函數

```move
module sui::transfer;

/// transfer 函數的公開版本
public fun public_transfer<T: key + store>(object: T, to: address) {}

/// share_object 函數的公開版本
public fun public_share_object<T: key + store>(object: T) {}

/// freeze_object 函數的公開版本
public fun public_freeze_object<T: key + store>(object: T) {}
```

**關鍵特點**：

-   函數名前綴為 `public_`
-   對所有模組和交易開放
-   **要求類型具有 `key + store` 能力**

## 📚 實際範例分析

### 模組 A：定義物件類型

```move
/// 定義具有不同能力組合的物件類型
module book::transfer_a;

use sui::object::UID;

// 只有 key 能力的物件
public struct ObjectK has key {
    id: UID
}

// 具有 key + store 能力的物件
public struct ObjectKS has key, store {
    id: UID
}
```

### 模組 B：嘗試實現轉移函數

```move
/// 嘗試為外部物件實現轉移功能
module book::transfer_b;

use book::transfer_a::{ObjectK, ObjectKS};
use sui::transfer;

// ❌ 失敗！ObjectK 沒有 store 能力，且不是此模組的內部類型
public fun transfer_k(k: ObjectK, to: address) {
    transfer::transfer(k, to);  // 編譯錯誤
}

// ❌ 失敗！ObjectKS 有 store 但使用的不是公開函數
public fun transfer_ks(ks: ObjectKS, to: address) {
    transfer::transfer(ks, to);  // 編譯錯誤
}

// ❌ 失敗！ObjectK 沒有 store 能力，public_transfer 要求 store
public fun public_transfer_k(k: ObjectK, to: address) {
    transfer::public_transfer(k, to);  // 編譯錯誤
}

// ✅ 成功！ObjectKS 有 store 能力且使用公開函數
public fun public_transfer_ks(ks: ObjectKS, to: address) {
    transfer::public_transfer(ks, to);  // 正確
}
```

### 結果分析

| 函數                 | 物件類型   | 函數類型 | store 能力 | 結果    | 原因                      |
| -------------------- | ---------- | -------- | ---------- | ------- | ------------------------- |
| `transfer_k`         | `ObjectK`  | 限制性   | ❌         | ❌ 失敗 | ObjectK 不是模組內部類型  |
| `transfer_ks`        | `ObjectKS` | 限制性   | ✅         | ❌ 失敗 | ObjectKS 不是模組內部類型 |
| `public_transfer_k`  | `ObjectK`  | 公開     | ❌         | ❌ 失敗 | ObjectK 沒有 store 能力   |
| `public_transfer_ks` | `ObjectKS` | 公開     | ✅         | ✅ 成功 | 滿足所有要求              |

## 🎯 Store 能力的重要性

### Store 能力的作用

`store` 能力是實現跨模組轉移的關鍵：

```move
// 沒有 store 能力 - 只能在定義模組內操作
struct PrivateNFT has key {
    id: UID,
    secret_data: String,
}

// 有 store 能力 - 可以被其他模組操作
struct PublicNFT has key, store {
    id: UID,
    public_data: String,
}
```

### 設計決策的考量

添加 `store` 能力需要謹慎考慮：

#### ✅ 優點

-   **互操作性**：讓類型可被其他應用程式使用
-   **組合性**：支援複雜的應用程式組合
-   **生態友好**：促進開放的生態系統發展

#### ⚠️ 缺點

-   **包裝風險**：允許被包裝並改變預期的存儲模型
-   **存儲模型變更**：可能改變原始設計意圖

### 實際影響範例

```move
module game::character {
    use sui::object::UID;
    use sui::transfer;

    // 設計意圖：角色應該由帳戶擁有
    struct GameCharacter has key, store {  // 添加了 store
        id: UID,
        name: String,
        level: u8,
    }
}

module marketplace::wrapper {
    use game::character::GameCharacter;
    use sui::object::UID;
    use sui::transfer;

    // 由於 GameCharacter 有 store 能力，可以被包裝
    struct CharacterListing has key {
        id: UID,
        character: GameCharacter,  // 包裝原始角色
        price: u64,
    }

    // 甚至可以被凍結（與原始設計意圖不符）
    public fun freeze_character(char: GameCharacter) {
        transfer::public_freeze_object(char);  // 角色變成不可變
    }
}
```

## 🛡️ 最佳實踐建議

### 1. 謹慎添加 Store 能力

```move
// 適合添加 store 的類型
struct Token has key, store {      // 代幣天然需要流通
    id: UID,
    value: u64,
}

struct GameItem has key, store {   // 遊戲道具需要交易
    id: UID,
    name: String,
    rarity: u8,
}

// 不適合添加 store 的類型
struct UserProfile has key {       // 用戶檔案不應被轉移
    id: UID,
    username: String,
    private_data: vector<u8>,
}

struct SystemConfig has key {      // 系統配置不應被任意操作
    id: UID,
    admin_only_settings: u64,
}
```

### 2. 設計時考慮存儲模型

```move
module nft::collection {
    // 清楚定義存儲模型的 NFT
    struct CollectionNFT has key, store {
        id: UID,
        collection_id: u64,
        token_id: u64,
        metadata: String,
        // 明確設計為可轉移和交易
    }

    // 提供控制轉移的機制
    struct TransferPolicy has key {
        id: UID,
        royalty_rate: u64,
        allowed_marketplaces: vector<address>,
    }
}
```

### 3. 文檔化設計意圖

```move
/// A game character that is designed to be:
/// - Owned by player accounts
/// - Transferable between players
/// - Tradeable on marketplaces
/// - Composable with equipment system
///
/// Note: This struct has `store` ability to enable ecosystem composability.
/// Developers should be aware that characters can be wrapped or frozen.
struct GameCharacter has key, store {
    id: UID,
    name: String,
    stats: CharacterStats,
}
```

## 🔄 轉移模式比較

### 限制性轉移 vs 公開轉移

| 特性         | 限制性轉移         | 公開轉移             |
| ------------ | ------------------ | -------------------- |
| **調用範圍** | 僅定義模組內       | 任何模組             |
| **能力要求** | 僅需 `key`         | 需要 `key + store`   |
| **安全性**   | 更高（模組控制）   | 較低（開放使用）     |
| **靈活性**   | 較低               | 更高                 |
| **適用場景** | 內部邏輯、敏感操作 | 生態互操作、用戶轉移 |

### 選擇指南

```move
// 場景 1：內部管理的敏感資源
struct AdminCapability has key {  // 不添加 store
    id: UID,
    permissions: u64,
}

// 場景 2：用戶資產，需要生態互操作
struct UserToken has key, store {  // 添加 store
    id: UID,
    amount: u64,
}

// 場景 3：混合模式 - 提供受控的公開接口
struct ControlledAsset has key {   // 核心結構不添加 store
    id: UID,
    sensitive_data: u64,
}

// 提供包裝器以實現受控轉移
struct AssetWrapper has key, store {  // 包裝器添加 store
    id: UID,
    asset_id: ID,  // 引用而非包含
}
```

## 📋 總結

### 關鍵要點

1. **默認限制**：存儲操作默認限制在定義模組內
2. **Store 能力**：是實現跨模組操作的關鍵
3. **公開函數**：`public_*` 函數提供跨模組存儲操作
4. **設計權衡**：添加 `store` 能力需要在互操作性和安全性間平衡

### 開發建議

-   **謹慎設計**：仔細考慮是否添加 `store` 能力
-   **明確意圖**：清楚記錄設計意圖和預期用法
-   **安全優先**：優先考慮安全性，再考慮互操作性
-   **漸進開放**：可以從限制性開始，後續通過包裝器提供受控的公開接口

通過理解這些概念，開發者可以更好地設計 Sui Move 應用程式的物件轉移策略，在安全性和互操作性之間找到適當的平衡點。
