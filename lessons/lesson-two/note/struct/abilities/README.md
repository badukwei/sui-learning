# Sui Move Abilities 系統完整指南

## Abilities 簡介

Move 擁有獨特的類型系統，允許自定義類型能力。Abilities（能力）是結構體聲明的一部分，定義了結構體實例允許的行為。Move 支援 4 種能力：`copy`、`drop`、`key`、和 `store`。

### Abilities 語法

能力在結構體定義中使用 `has` 關鍵字設置，後跟能力列表，能力之間用逗號分隔：

```move
/// 這個結構體具有 `copy` 和 `drop` 能力
public struct VeryAble has copy, drop {
    // field: Type1,
    // field2: Type2,
    // ...
}
```

### 四種基本能力概覽

-   **`copy`** - 允許結構體被複製
-   **`drop`** - 允許結構體被丟棄或銷毀
-   **`key`** - 允許結構體作為儲存中的鍵使用
-   **`store`** - 允許結構體存儲在具有 `key` 能力的結構體中

> **注意**: 所有內建類型（除了引用）都具有 `copy`、`drop` 和 `store` 能力。引用具有 `copy` 和 `drop` 能力。

## 所有能力組合及使用場景

| 能力組合              | 使用場景           | 典型應用                     | 特性說明                             |
| --------------------- | ------------------ | ---------------------------- | ------------------------------------ |
| **無能力**            | HotPotato 模式     | 強制性回調、閃電貸、借用保證 | 必須被手動處理，不能存儲、複製或丟棄 |
| **`key`**             | 獨立頂層物件       | 系統配置、全域狀態、獨特 NFT | 只能獨立存在，無法被包含             |
| **`store`**           | 純內部資料         | 複雜內部狀態、組件資料       | 只能作為其他物件的內部資料           |
| **`copy`**            | 純值類型（少用）   | 簡單計算結果                 | 可複製，隱含`drop`，但無法存儲       |
| **`drop`**            | 臨時資料           | 計算中間結果、臨時狀態       | 可自動銷毀，無法存儲或複製           |
| **`key+store`**       | 標準 NFT           | 遊戲道具、藝術品、收藏品     | 既可獨立存在，也可被收藏             |
| **`key+copy`**        | 可複製配置（困難） | 理論組合，UID 不可複製       | 實際應用困難                         |
| **`key+drop`**        | 可銷毀頂層物件     | 臨時系統狀態                 | UID 需特殊處理，少用                 |
| **`store+copy`**      | 可複製資料         | 元資料、配置參數、統計資料   | 最常見的資料結構組合                 |
| **`store+drop`**      | 可銷毀資料         | 會話資料、臨時記錄           | 需顯式轉移，可自動銷毀               |
| **`copy+drop`**       | 純值類型           | 計算結果、簡單狀態           | 類似基本型別，可複製和銷毀           |
| **`key+store+copy`**  | 理論完整（困難）   | 很少實現                     | UID 與 copy 衝突                     |
| **`key+store+drop`**  | 完整標準物件       | 功能完整的物件               | 可獨立、可包含、可銷毀               |
| **`store+copy+drop`** | 最靈活資料         | 通用資料結構                 | 所有資料操作都支援                   |
| **所有能力**          | 理論完整（困難）   | 很難實現                     | UID 與 copy 的根本衝突               |

### 使用場景詳細說明

#### 🎯 **常用組合推薦**

-   **NFT/遊戲道具**: `key + store`
-   **元資料/配置**: `store + copy`
-   **純值計算**: `copy + drop`
-   **系統狀態**: `key` only
-   **Hot Potato 模式**: 無能力

#### 🔄 **特殊組合說明**

-   **包含 `copy` 的組合**: 由於 UID 不可複製，`key + copy` 組合在實踐中很難實現
-   **只有 `drop`**: 適合臨時計算結果，但無法持久化
-   **只有 `store`**: 無法獨立存在，必須作為其他物件的一部分

---

## Ability: Key 詳解

### Key 能力的核心概念

`key` 能力代表這個結構體可以被記錄在區塊鏈的全域存儲中，也就是說它可以成為鏈上的一個獨立物件，直接被帳戶或地址所擁有。隨著物件模型的出現，`key` 能力就成為物件類型最核心、最具代表性的能力。

### 物件定義

**具有 `key` 能力的結構體被視為物件**，可以在存儲函數中使用。Sui 驗證器將要求結構體的第一個欄位命名為 `id` 並具有 `UID` 類型。

```move
use sui::object::{Self, UID};
use sui::tx_context::TxContext;

public struct Object has key {
    id: UID,    // 必需的第一個欄位
    name: String,
}

/// 創建一個具有唯一 ID 的新物件
public fun new(name: String, ctx: &mut TxContext): Object {
    Object {
        id: object::new(ctx), // 創建新的 UID
        name,
    }
}
```

### Key 能力的特性

#### 1. 仍然是結構體

具有 `key` 能力的結構體仍然是結構體，可以有任意數量的欄位和相關函數。對於打包、存取或解包結構體，沒有特殊的處理或語法。

```move
public struct GameCharacter has key {
    id: UID,
    name: String,
    level: u8,
    health: u64,
    experience: u64,
}

// 正常的結構體操作
public fun level_up(character: &mut GameCharacter) {
    character.level = character.level + 1;
    character.health = character.health + 10;
}

public fun get_name(character: &GameCharacter): String {
    character.name
}
```

#### 2. UID 的要求和影響

因為物件結構體的第一個欄位必須是 `UID` 類型 - 一個不可複製和不可丟棄的類型，所以結構體傳遞性地不能具有 `drop` 和 `copy` 能力。因此，**物件在設計上是不可丟棄的**。

```move
// UID 沒有 copy 和 drop 能力
// 所以包含 UID 的結構體也不能有這些能力

public struct ValidObject has key {
    id: UID,
    data: String,
}

// 這些組合是無效的：
// public struct InvalidObject1 has key, copy { ... }  // 編譯錯誤
// public struct InvalidObject2 has key, drop { ... }  // 編譯錯誤
```

### 具有 Key 能力的類型限制

由於類型需要 `UID` 才能具有 `key` 能力，Move 中的原生類型都不能具有 `key` 能力，標準庫類型也不能。`key` 能力只存在於 Sui Framework 和自定義類型中。

#### 原生類型

```move
// 這些都不能有 key 能力：
// u64, bool, vector<T>, address 等
```

#### 標準庫類型

```move
// 這些也不能有 key 能力：
// Option<T>, String, TypeName 等
```

#### 只有自定義類型可以

```move
// 只有自定義結構體可以有 key 能力
public struct MyObject has key {
    id: UID,
    // 其他欄位...
}
```

### 實際應用範例

#### 基礎 NFT

```move
public struct SimpleNFT has key {
    id: UID,
    name: String,
    description: String,
    image_url: String,
}

public fun mint_nft(
    name: String,
    description: String,
    image_url: String,
    ctx: &mut TxContext
): SimpleNFT {
    SimpleNFT {
        id: object::new(ctx),
        name,
        description,
        image_url,
    }
}
```

#### 遊戲道具

```move
public struct Weapon has key, store {
    id: UID,
    name: String,
    attack_power: u64,
    durability: u64,
    rarity: u8,
}

public fun create_weapon(
    name: String,
    attack_power: u64,
    rarity: u8,
    ctx: &mut TxContext
): Weapon {
    Weapon {
        id: object::new(ctx),
        name,
        attack_power,
        durability: 100, // 初始耐久度
        rarity,
    }
}

public fun repair_weapon(weapon: &mut Weapon) {
    weapon.durability = 100;
}
```

#### 系統配置物件

```move
public struct GlobalConfig has key {
    id: UID,
    admin: address,
    fees_enabled: bool,
    fee_rate: u64,
    max_supply: u64,
}

public fun create_config(
    admin: address,
    fee_rate: u64,
    max_supply: u64,
    ctx: &mut TxContext
): GlobalConfig {
    GlobalConfig {
        id: object::new(ctx),
        admin,
        fees_enabled: false,
        fee_rate,
        max_supply,
    }
}

public fun update_fee_rate(config: &mut GlobalConfig, new_rate: u64) {
    config.fee_rate = new_rate;
}
```

### Key 與其他能力的組合

#### Key + Store（最常見）

```move
// 標準 NFT 模式：可以獨立存在，也可以被包含
public struct StandardNFT has key, store {
    id: UID,
    metadata: NFTMetadata,
}
```

#### 只有 Key（獨立物件）

```move
// 只能獨立存在的物件，不能被其他物件包含
public struct AdminCapability has key {
    id: UID,
    permissions: vector<String>,
}
```

#### Key + Store + Drop（理論上，但實際困難）

```move
// 由於 UID 沒有 drop 能力，這種組合在實際中很難實現
// 即使聲明了 drop，也需要特殊處理 UID
```

### 物件的生命週期

#### 創建

```move
public fun create_object(ctx: &mut TxContext): MyObject {
    MyObject {
        id: object::new(ctx), // 分配新的唯一 ID
        // 其他欄位初始化
    }
}
```

#### 轉移

```move
use sui::transfer;

public fun transfer_object(obj: MyObject, recipient: address) {
    transfer::transfer(obj, recipient);
}
```

#### 共享

```move
public fun share_object(obj: MyObject) {
    transfer::share_object(obj);
}
```

#### 刪除（需要特殊處理 UID）

```move
use sui::object;

public fun delete_object(obj: MyObject) {
    let MyObject { id, /* 其他欄位 */ } = obj;
    object::delete(id); // 必須明確刪除 UID
}
```

### 設計模式

#### 1. 能力控制模式

```move
public struct AdminCap has key {
    id: UID,
}

public struct TreasuryCap has key {
    id: UID,
    total_supply: u64,
}

// 只有擁有相應能力的人才能執行特定操作
public fun admin_only_function(_: &AdminCap) {
    // 只有管理員可以呼叫
}
```

#### 2. 資源容器模式

```move
public struct Vault has key {
    id: UID,
    balance: u64,
    owner: address,
}

public fun deposit(vault: &mut Vault, amount: u64) {
    vault.balance = vault.balance + amount;
}

public fun withdraw(vault: &mut Vault, amount: u64): u64 {
    assert!(vault.balance >= amount, 0);
    vault.balance = vault.balance - amount;
    amount
}
```

#### 3. 註冊表模式

```move
public struct Registry has key {
    id: UID,
    entries: Table<String, address>,
}

public fun register(
    registry: &mut Registry,
    name: String,
    owner: address
) {
    registry.entries.add(name, owner);
}
```

### Key 能力的限制

#### 1. UID 要求

```move
// 錯誤：沒有 UID 欄位
// public struct BadObject has key {
//     name: String,
// }

// 錯誤：UID 不是第一個欄位
// public struct BadObject2 has key {
//     name: String,
//     id: UID,
// }
```

#### 2. 不能複製

```move
// 由於 UID 不可複製，具有 key 的物件也不能複製
public fun cannot_copy_object(obj: MyObject) {
    // let copy = obj; // 這會移動，不是複製
    // let another = obj; // 編譯錯誤：obj 已被移動
}
```

#### 3. 必須明確處理

```move
// 物件不能被丟棄，必須明確處理
public fun must_handle_object(obj: MyObject) {
    // 必須轉移、共享或刪除物件
    transfer::transfer(obj, @some_address);
    // 或者：transfer::share_object(obj);
    // 或者：object::delete(obj.id);
}
```

### 最佳實踐

#### 1. 明確的物件用途

```move
// 好的設計：清晰的物件目的
public struct UserProfile has key, store {
    id: UID,
    username: String,
    email: String,
    created_at: u64,
}
```

#### 2. 適當的能力組合

```move
// 大多數情況下，key + store 是好的組合
public struct GameItem has key, store {
    id: UID,
    item_type: u8,
    value: u64,
}

// 特殊權限物件通常只有 key
public struct AdminCap has key {
    id: UID,
}
```

#### 3. 安全的物件操作

```move
public fun safe_transfer(obj: MyObject, recipient: address) {
    // 在轉移前可以進行驗證
    assert!(recipient != @0x0, 1);
    transfer::transfer(obj, recipient);
}
```

### 下一步：存儲函數

`key` 能力定義了 Move 中的物件，而物件是用來被存儲的。Sui 提供了 `sui::transfer` 模組，為物件提供原生的存儲函數，包括：

-   `transfer::transfer()` - 轉移物件給特定地址
-   `transfer::share_object()` - 將物件設為共享
-   `transfer::freeze_object()` - 將物件設為不可變

Key 能力是 Sui 物件模型的基礎，理解它對於構建有效的去中心化應用至關重要。

---

## Ability: Store 詳解

### Store 能力的核心概念

在前面我們介紹了 `key` 能力及概念，接下來讓我們深入了解另一個重要能力：`store`。

### 定義

`store` 是一種特殊能力，允許類型被存儲在物件中。**這個能力是類型被用作具有 `key` 能力的 struct 中的欄位所必需的**。換句話說，`store` 能力允許值被包裝在物件中。

`store` 能力還放寬了轉移操作的限制。我們在「限制和公開轉移」部分會詳細討論。

### 基本範例

```move
/// 這個類型具有 `store` 能力
public struct Storable has store {}

/// Config 包含一個 `Storable` 欄位，該欄位必須具有 `store` 能力
public struct Config has key, store {
    id: UID,
    stores: Storable,
}

/// MegaConfig 包含一個具有 `store` 能力的 `Config` 欄位
public struct MegaConfig has key {
    id: UID,
    config: Config, // 這裡就是！
}
```

### Store 能力的作用機制

#### 1. 包含關係的要求

```move
// 正確：包含具有 store 能力的類型
public struct Container has key {
    id: UID,
    data: StorableData,      // ✅ 有 store 能力
    count: u64,              // ✅ 原生類型有 store 能力
    items: vector<Item>,     // ✅ 如果 Item 有 store 能力
}

public struct StorableData has store {
    value: String,
}

public struct Item has store {
    name: String,
}
```

#### 2. 編譯時檢查

```move
// 錯誤：嘗試包含沒有 store 能力的類型
public struct NonStorable {} // 沒有 store 能力

public struct BadContainer has key {
    id: UID,
    // data: NonStorable,    // ❌ 編譯錯誤！
}
```

### 實際應用範例

#### NFT 與元資料

```move
// NFT 元資料，可以被存儲在 NFT 中
public struct NFTMetadata has store, copy {
    name: String,
    description: String,
    image_url: String,
    attributes: vector<Attribute>,
}

// 屬性資料，可以被存儲在元資料中
public struct Attribute has store, copy {
    trait_type: String,
    value: String,
}

// NFT 主體，包含元資料
public struct MyNFT has key, store {
    id: UID,
    metadata: NFTMetadata,     // 需要 store 能力
    creator: address,
}
```

#### 遊戲系統

```move
// 遊戲角色屬性
public struct Stats has store, copy {
    health: u64,
    attack: u64,
    defense: u64,
    speed: u64,
}

// 遊戲裝備
public struct Equipment has key, store {
    id: UID,
    name: String,
    equipment_type: u8,
    stats_bonus: Stats,        // 需要 store 能力
}

// 遊戲角色
public struct Character has key, store {
    id: UID,
    name: String,
    base_stats: Stats,         // 需要 store 能力
    equipment: vector<Equipment>, // Equipment 需要 store 能力
    level: u8,
}
```

#### 複雜的資料結構

```move
// 公司資訊
public struct Company has store {
    name: String,
    founded: u64,
    employees: u64,
}

// 個人資訊
public struct Person has store {
    name: String,
    age: u8,
    company: Option<Company>,  // Company 需要 store 能力
}

// 用戶檔案（頂層物件）
public struct UserProfile has key {
    id: UID,
    personal_info: Person,     // Person 需要 store 能力
    created_at: u64,
}
```

### Store 與其他能力的組合

#### Store Only（純內部資料）

```move
// 只能作為其他物件的內部資料
public struct InternalData has store {
    private_key: vector<u8>,
    timestamp: u64,
}
```

#### Store + Copy（可複製資料）

```move
// 最常見的資料結構組合
public struct Metadata has store, copy {
    title: String,
    tags: vector<String>,
}
```

#### Store + Drop（可銷毀資料）

```move
// 可存儲但不可複製的資料
public struct SessionData has store, drop {
    session_id: String,
    expires_at: u64,
}
```

#### Key + Store（標準物件）

```move
// 既可獨立存在，也可被包含
public struct Token has key, store {
    id: UID,
    value: u64,
}
```

### 層次化存儲

#### 多層嵌套

```move
// 第三層：基礎資料
public struct BaseData has store, copy {
    value: u64,
    name: String,
}

// 第二層：中間容器
public struct MiddleContainer has store {
    data: BaseData,            // 需要 store
    metadata: String,
}

// 第一層：頂層物件
public struct TopLevel has key {
    id: UID,
    container: MiddleContainer, // 需要 store
}
```

#### 動態集合

```move
use sui::table::Table;
use sui::bag::Bag;

public struct DataRegistry has key {
    id: UID,
    // 所有存儲在 Table 或 Bag 中的類型都需要 store 能力
    string_data: Table<String, StorableItem>,
    mixed_data: Bag,
}

public struct StorableItem has store {
    content: String,
    priority: u8,
}
```

### 具有 Store 能力的類型

#### 所有原生類型（除了引用）

Move 中的所有原生類型都具有 `store` 能力：

-   `bool`
-   無符號整數（`u8`, `u16`, `u32`, `u64`, `u128`, `u256`）
-   `vector<T>`（如果 T 有 store 能力）
-   `address`

#### 標準庫類型

標準庫中定義的所有類型也都具有 `store` 能力：

-   `Option<T>`（如果 T 有 store 能力）
-   `String`
-   `TypeName`

#### 條件性 Store 能力

```move
// vector 只有在元素類型有 store 時才有 store
vector<StorableType>    // ✅ 有 store（如果 StorableType 有 store）
vector<NonStorableType> // ❌ 沒有 store

// Option 同樣如此
Option<StorableType>    // ✅ 有 store（如果 StorableType 有 store）
Option<NonStorableType> // ❌ 沒有 store
```

### Store 能力的限制

#### 1. 傳遞性要求

```move
// 如果結構體要有 store 能力，所有欄位都必須有 store 能力
public struct ValidStorable has store {
    data1: String,        // ✅ String 有 store
    data2: u64,          // ✅ u64 有 store
    data3: StorableItem, // ✅ StorableItem 有 store
}

public struct StorableItem has store {
    value: u64,
}

// 這會編譯錯誤：
// public struct InvalidStorable has store {
//     data: NonStorableItem,  // ❌ NonStorableItem 沒有 store
// }
```

#### 2. Hot Potato 的限制

```move
// Hot Potato（無能力）不能被存儲
public struct HotPotato {
    data: String,
}

// 這是無效的：
// public struct Container has key {
//     id: UID,
//     potato: HotPotato,  // ❌ 編譯錯誤！
// }
```

### 設計模式

#### 1. 數據層次模式

```move
// 基礎資料層
public struct RawData has store, copy {
    bytes: vector<u8>,
}

// 處理資料層
public struct ProcessedData has store {
    raw: RawData,
    processed_at: u64,
}

// 業務物件層
public struct BusinessObject has key, store {
    id: UID,
    data: ProcessedData,
}
```

#### 2. 組合物件模式

```move
// 可組合的組件
public struct Component has key, store {
    id: UID,
    component_type: u8,
    properties: ComponentProperties,
}

public struct ComponentProperties has store, copy {
    color: String,
    size: u64,
    weight: u64,
}

// 複合物件
public struct CompositeObject has key {
    id: UID,
    components: vector<Component>, // 每個 Component 需要 store
    assembly_date: u64,
}
```

#### 3. 配置樹模式

```move
// 葉子節點配置
public struct LeafConfig has store, copy {
    value: u64,
    enabled: bool,
}

// 分支節點配置
public struct BranchConfig has store {
    name: String,
    children: vector<LeafConfig>,
}

// 根配置物件
public struct RootConfig has key {
    id: UID,
    branches: vector<BranchConfig>,
    version: u64,
}
```

### 轉移限制的放寬

`store` 能力還放寬了轉移操作的限制：

#### 受限轉移 vs 公開轉移

```move
// 沒有 store 能力的物件有轉移限制
public struct RestrictedObject has key {
    id: UID,
    data: String,
}

// 有 store 能力的物件支援更靈活的轉移
public struct FlexibleObject has key, store {
    id: UID,
    data: String,
}
```

### 最佳實踐

#### 1. 明確的資料層次

```move
// 好的設計：清晰的資料層次
public struct UserMetadata has store, copy {
    display_name: String,
    avatar_url: String,
}

public struct UserAccount has key, store {
    id: UID,
    metadata: UserMetadata,
    balance: u64,
}
```

#### 2. 適當的能力組合

```move
// 純資料：store + copy
public struct Settings has store, copy {
    theme: String,
    language: String,
}

// 業務邏輯：store（不要 copy）
public struct BusinessData has store {
    sensitive_info: String,
    last_updated: u64,
}

// 頂層物件：key + store
public struct Application has key, store {
    id: UID,
    settings: Settings,
    business_data: BusinessData,
}
```

#### 3. 性能考量

```move
// 對於大型資料結構，考慮使用引用
public fun process_large_data(data: &LargeStorableData) {
    // 避免不必要的複製
}

// 對於小型配置，直接傳值是可以的
public fun update_config(config: SmallConfig) {
    // 小型資料結構的複製開銷較小
}
```

### 總結

Store 能力是 Move 類型系統中的關鍵組件，它：

1. **啟用包含關係**：允許類型被存儲在具有 key 能力的結構體中
2. **建立資料層次**：支援複雜的嵌套資料結構
3. **放寬轉移限制**：提供更靈活的物件轉移選項
4. **確保類型安全**：通過編譯時檢查確保資料完整性

理解 Store 能力對於設計可組合、可擴展的 Move 應用程式至關重要。

---

## Ability: Copy 詳解

### Copy 能力的核心概念

在 Move 中，`copy` 能力表示該類型的實例或值可以被複製或複製。雖然這種行為在處理數字或其他基本類型時是預設提供的，但對於自定義類型來說並非預設行為。

Move 被設計用來表達數位資產和資源，**控制複製資源的能力是資源模型的核心原則**。然而，Move 類型系統允許您為自定義類型添加 `copy` 能力：

```move
public struct Copyable has copy {}
```

### 複製行為的運作方式

當結構體具有 `copy` 能力時，可以進行隱式和顯式複製：

```move
public struct Copyable has copy {}

public fun demonstrate_copy() {
    let a = Copyable {}; // 允許，因為 Copyable 結構體有 `copy` 能力
    let b = a;           // `a` 被複製到 `b`（隱式複製）
    let c = *&b;         // 通過解引用運算符顯式複製

    // Copyable 沒有 `drop` 能力，所以每個實例 (a, b, c) 都必須
    // 被使用或明確解構。`drop` 能力將在下面解釋。
    let Copyable {} = a;
    let Copyable {} = b;
    let Copyable {} = c;
}
```

### 隱式複製與顯式複製

#### 隱式複製

```move
let original = Copyable {};
let copied = original; // 自動複製，original 仍然可用
```

#### 顯式複製

```move
let original = Copyable {};
let reference = &original;
let copied = *reference; // 通過解引用顯式複製
```

### Copy 與 Drop 的關係

`copy` 能力與 `drop` 能力密切相關。如果一個類型具有 `copy` 能力，它很可能也應該具有 `drop` 能力。這是因為需要 `drop` 能力來在實例不再需要時清理資源。

#### 只有 Copy 的問題

```move
// 問題：只有 copy，沒有 drop
public struct OnlyCopy has copy {}

public fun problematic_usage() {
    let a = OnlyCopy {};
    let b = a; // 複製成功

    // 問題：a 和 b 都必須被明確處理，否則編譯錯誤
    let OnlyCopy {} = a; // 必須明確解構
    let OnlyCopy {} = b; // 必須明確解構
}
```

#### 推薦的組合

```move
// 推薦：copy + drop 組合
public struct Value has copy, drop {}

public fun better_usage() {
    let a = Value {};
    let b = a; // 複製成功

    // a 和 b 會自動清理，無需明確處理
}
```

### 解構語法的重要性

在 Move 中，使用空大括號進行解構經常用於消費未使用的變數，特別是對於沒有 `drop` 能力的類型。這防止了值超出作用域而沒有被明確使用時的編譯器錯誤。

```move
// 必須包含類型名稱的解構
let Copyable {} = some_copyable_value;

// 錯誤的寫法：
// let {} = some_copyable_value; // 編譯錯誤
```

**為什麼需要類型名稱？**
Move 要求在解構中使用類型名稱（例如 `let Copyable {} = a;` 中的 `Copyable`），因為它強制執行嚴格的類型檢查和所有權規則。

### 具有 Copy 能力的類型

#### 所有原生類型

Move 中的所有原生類型都具有 `copy` 能力：

-   `bool`
-   無符號整數（`u8`, `u16`, `u32`, `u64`, `u128`, `u256`）
-   `vector<T>`（如果 T 有 copy 能力）
-   `address`

#### 標準庫類型

標準庫中定義的所有類型也都具有 `copy` 能力：

-   `Option<T>`（如果 T 有 copy 能力）
-   `String`
-   `TypeName`

### 實際應用範例

#### 配置資料

```move
public struct Config has copy, drop {
    max_supply: u64,
    price_per_unit: u64,
    is_active: bool,
}

public fun use_config() {
    let config = Config {
        max_supply: 1000,
        price_per_unit: 100,
        is_active: true,
    };

    // 可以隨意複製配置
    let backup_config = config;
    let another_copy = config;

    // 所有副本都可以獨立使用
}
```

#### 數學計算結果

```move
public struct Point has copy, drop {
    x: u64,
    y: u64,
}

public fun calculate_distance(p1: Point, p2: Point): u64 {
    // 可以直接使用參數，因為它們會被自動複製
    let dx = if (p1.x > p2.x) { p1.x - p2.x } else { p2.x - p1.x };
    let dy = if (p1.y > p2.y) { p1.y - p2.y } else { p2.y - p1.y };

    // 簡化的距離計算
    dx + dy
}
```

#### 元資料結構

```move
public struct NFTMetadata has copy, drop, store {
    name: String,
    description: String,
    image_url: String,
    attributes: vector<Attribute>,
}

public struct Attribute has copy, drop, store {
    trait_type: String,
    value: String,
}

// 可以輕鬆複製和分享元資料
public fun share_metadata(metadata: NFTMetadata): (NFTMetadata, NFTMetadata) {
    (metadata, metadata) // 自動複製
}
```

### Copy 能力的限制

#### 資源安全考量

```move
// 不應該有 copy 能力的資源
public struct Coin has key, store {
    id: UID,
    value: u64,
}

// 如果 Coin 有 copy 能力，就可以無限複製金錢！
// 這違反了資源稀缺性的原則
```

#### UID 的特殊性

```move
// UID 永遠不能有 copy 能力
public struct UniqueObject has key, store {
    id: UID, // UID 沒有 copy 能力
    data: String,
}

// 這意味著包含 UID 的結構體也不能有 copy 能力
```

### 設計原則

#### 何時使用 Copy

-   ✅ 純資料結構（配置、元資料）
-   ✅ 數學計算結果
-   ✅ 狀態標記和枚舉
-   ✅ 輕量級的值類型

#### 何時避免 Copy

-   ❌ 代表稀缺資源的類型
-   ❌ 包含 UID 的結構體
-   ❌ 需要唯一性的資產
-   ❌ 需要追蹤所有權轉移的物件

### 性能考量

#### Copy 的開銷

```move
public struct LargeData has copy, drop {
    data: vector<vector<u8>>, // 大量資料
}

// 複製大型資料結構可能有性能開銷
public fun expensive_copy(large: LargeData) {
    let copy1 = large; // 複製整個資料結構
    let copy2 = large; // 再次複製

    // 考慮使用引用代替
}

// 更高效的方法
public fun efficient_access(large: &LargeData) {
    // 使用引用避免不必要的複製
}
```

### 最佳實踐總結

1. **明智使用 Copy**：只為真正需要複製的類型添加 `copy` 能力
2. **Copy + Drop 組合**：大多數可複製的類型也應該可丟棄
3. **避免大型結構**：對於大型資料結構，考慮使用引用而不是複製
4. **資源安全**：永遠不要為代表稀缺資源的類型添加 `copy` 能力
5. **一致性設計**：相似用途的類型應該有一致的能力組合

Copy 能力是 Move 類型系統中的強大工具，但必須謹慎使用以維護資源安全和系統性能。

---

## Ability: Drop 詳解

### Drop 能力的核心概念

`drop` 能力是四種能力中最簡單的一個，它允許結構體的實例被忽略或丟棄。在許多程式語言中，這種行為被認為是預設的。然而，在 Move 中，**沒有 `drop` 能力的結構體不允許被忽略**。這是 Move 語言的安全特性，確保所有資產都得到適當處理。嘗試忽略沒有 `drop` 能力的結構體會導致編譯錯誤。

### 基本範例

```move
module book::drop_ability {
    /// 這個結構體具有 `drop` 能力
    public struct IgnoreMe has drop {
        a: u8,
        b: u8,
    }

    /// 這個結構體沒有 `drop` 能力
    public struct NoDrop {}

    #[test]
    // 創建 `IgnoreMe` 結構體的實例並忽略它
    // 即使我們構造了實例，也不需要解包它
    fun test_ignore() {
        let no_drop = NoDrop {};
        let _ = IgnoreMe { a: 1, b: 2 }; // 不需要解包

        // 沒有 drop 能力的值必須被解包才能編譯
        let NoDrop {} = no_drop; // OK
    }
}
```

### Drop 能力的作用機制

#### 1. 自動清理 vs 手動處理

```move
public struct AutoCleanup has drop {
    data: String,
    value: u64,
}

public struct ManualHandling {
    important_data: String,
    critical_value: u64,
}

public fun demonstrate_drop_behavior() {
    // 有 drop 能力：可以自動清理
    let auto = AutoCleanup {
        data: string::utf8(b"auto"),
        value: 42,
    };
    // auto 在函數結束時自動被清理，無需手動處理

    // 沒有 drop 能力：必須手動處理
    let manual = ManualHandling {
        important_data: string::utf8(b"manual"),
        critical_value: 100,
    };

    // 必須明確解構，否則編譯錯誤
    let ManualHandling { important_data: _, critical_value: _ } = manual;
}
```

#### 2. 函數參數和返回值

```move
// 有 drop 能力的參數可以被忽略
public fun process_droppable(data: AutoCleanup) {
    // 可以選擇不使用 data，它會自動被清理
    // do_something_else();
}

// 沒有 drop 能力的參數必須被處理
public fun process_non_droppable(data: ManualHandling) {
    // 必須明確處理 data
    let ManualHandling { important_data, critical_value } = data;
    // 使用 important_data 和 critical_value
}
```

### 實際應用範例

#### 配置和元資料

```move
// 配置資料：通常有 drop 能力，方便使用
public struct Config has copy, drop {
    max_users: u64,
    timeout: u64,
    enabled: bool,
}

// 系統狀態（模擬）
public struct SystemState has key {
    id: UID,
    current_max_users: u64,
    current_timeout: u64,
    is_enabled: bool,
}

public fun update_system(system: &mut SystemState) {
    let config = Config {
        max_users: 1000,
        timeout: 30,
        enabled: true,
    };

    // 可以創建臨時配置而不用擔心清理
    apply_config(system, config);
    // config 自動被清理
}

public fun apply_config(system: &mut SystemState, config: Config) {
    // 使用配置更新系統狀態
    system.current_max_users = config.max_users;
    system.current_timeout = config.timeout;
    system.is_enabled = config.enabled;

    // config 在函數結束時自動清理
}

// 也可以輕鬆地複製和傳遞配置
public fun get_default_config(): Config {
    Config {
        max_users: 500,
        timeout: 60,
        enabled: true,
    }
}

public fun validate_config(config: Config): bool {
    config.max_users > 0 && config.timeout > 0
    // config 使用後自動清理
}

// ============ Copy + Drop vs 只有 Copy 的差異 ============

// 只有 copy 能力的配置（沒有 drop）
public struct ConfigOnlyCopy has copy {
    max_users: u64,
    timeout: u64,
    enabled: bool,
}

// 對比：有 copy + drop 能力的配置
public struct ConfigWithDrop has copy, drop {
    max_users: u64,
    timeout: u64,
    enabled: bool,
}

public fun demonstrate_difference() {
    // === 只有 Copy 的情況 ===
    let config_no_drop = ConfigOnlyCopy {
        max_users: 1000,
        timeout: 30,
        enabled: true,
    };

    let copy1 = config_no_drop; // 複製成功
    let copy2 = config_no_drop; // 再次複製成功

    // ❌ 問題：所有副本都必須被明確處理，否則編譯錯誤
    let ConfigOnlyCopy { max_users: _, timeout: _, enabled: _ } = copy1; // 必須解構
    let ConfigOnlyCopy { max_users: _, timeout: _, enabled: _ } = copy2; // 必須解構
    let ConfigOnlyCopy { max_users: _, timeout: _, enabled: _ } = config_no_drop; // 也必須解構

    // === 有 Copy + Drop 的情況 ===
    let config_with_drop = ConfigWithDrop {
        max_users: 1000,
        timeout: 30,
        enabled: true,
    };

    let copy_a = config_with_drop; // 複製成功
    let copy_b = config_with_drop; // 再次複製成功

    // ✅ 方便：所有副本都會自動清理，無需手動處理
    use_config_somehow(copy_a);
    // copy_b 和 config_with_drop 自動清理
}

public fun use_config_somehow(config: ConfigWithDrop) {
    // 使用配置做某些事情
    if (config.enabled) {
        // 處理邏輯...
    }
    // config 在函數結束時自動清理
}

// === 實際應用中的差異 ===

public fun only_copy_workflow() {
    let config = ConfigOnlyCopy {
        max_users: 500,
        timeout: 60,
        enabled: true,
    };

    // 可以傳遞給多個函數
    let result1 = validate_only_copy(config);
    let result2 = process_only_copy(config);

    // ❌ 問題：必須在最後明確處理原始配置
    let ConfigOnlyCopy { max_users: _, timeout: _, enabled: _ } = config;

    // 並且每個函數內部也必須處理參數
}

public fun copy_drop_workflow() {
    let config = ConfigWithDrop {
        max_users: 500,
        timeout: 60,
        enabled: true,
    };

    // 可以傳遞給多個函數
    let result1 = validate_with_drop(config);
    let result2 = process_with_drop(config);

    // ✅ 方便：config 自動清理，無需手動處理
}

// 只有 copy 的函數必須手動處理參數
public fun validate_only_copy(config: ConfigOnlyCopy): bool {
    let is_valid = config.max_users > 0 && config.timeout > 0;

    // ❌ 必須明確處理 config，否則編譯錯誤
    let ConfigOnlyCopy { max_users: _, timeout: _, enabled: _ } = config;

    is_valid
}

public fun process_only_copy(config: ConfigOnlyCopy): u64 {
    let result = config.max_users * config.timeout;

    // ❌ 必須明確處理 config
    let ConfigOnlyCopy { max_users: _, timeout: _, enabled: _ } = config;

    result
}

// copy + drop 的函數可以自動清理參數
public fun validate_with_drop(config: ConfigWithDrop): bool {
    config.max_users > 0 && config.timeout > 0
    // ✅ config 自動清理
}

public fun process_with_drop(config: ConfigWithDrop): u64 {
    config.max_users * config.timeout
    // ✅ config 自動清理
}

// ============ 記憶體行為詳解 ============

public fun memory_behavior_explanation() {
    // === Copy 的記憶體行為 ===

    let original = ConfigWithDrop {     // 記憶體位置 A
        max_users: 1000,
        timeout: 30,
        enabled: true,
    };

    let copy1 = original;               // 記憶體位置 B（完全獨立的副本）
    let copy2 = original;               // 記憶體位置 C（又一個獨立副本）

    // 重要：original, copy1, copy2 是三個完全獨立的記憶體位置
    // 修改其中一個不會影響其他的

    demonstrate_independence(original, copy1, copy2);
}

public fun demonstrate_independence(
    mut config_a: ConfigWithDrop,  // 位置 A 的副本
    mut config_b: ConfigWithDrop,  // 位置 B 的副本
    config_c: ConfigWithDrop       // 位置 C 的副本（不可變）
) {
    // 修改 config_a
    config_a.max_users = 2000;        // 只影響位置 A

    // 修改 config_b
    config_b.timeout = 60;             // 只影響位置 B

    // config_c 保持原始值

    // 驗證它們是獨立的
    assert!(config_a.max_users == 2000, 1);  // A 的修改
    assert!(config_b.max_users == 1000, 2);  // B 保持原值
    assert!(config_c.max_users == 1000, 3);  // C 保持原值

    assert!(config_a.timeout == 30, 4);      // A 保持原值
    assert!(config_b.timeout == 60, 5);      // B 的修改
    assert!(config_c.timeout == 30, 6);      // C 保持原值

    // 所有副本在函數結束時自動清理（各自的記憶體位置）
}

// === 與引用（Reference）的對比 ===

public fun reference_vs_copy_behavior() {
    let mut original = ConfigWithDrop {
        max_users: 1000,
        timeout: 30,
        enabled: true,
    };

    // 方法 1：使用引用（同一記憶體位置）
    modify_via_reference(&mut original);
    assert!(original.max_users == 3000, 1);  // 原始值被修改了

    // 方法 2：使用複製（不同記憶體位置）
    let result = modify_via_copy(original);   // original 被移動並複製
    // original 已經被移動，不能再使用
    assert!(result.max_users == 6000, 2);    // 返回新的獨立副本
}

public fun modify_via_reference(config: &mut ConfigWithDrop) {
    // 直接修改原始記憶體位置
    config.max_users = config.max_users * 3;  // 3000
}

public fun modify_via_copy(config: ConfigWithDrop): ConfigWithDrop {
    // 創建新的副本並修改
    let mut new_config = config;              // 複製到新記憶體位置
    new_config.max_users = new_config.max_users * 2;  // 修改新副本
    new_config                                // 返回新副本
    // 原始的 config 參數在此自動清理
}

// === 複雜情況：嵌套結構的記憶體行為 ===

public struct NestedConfig has copy, drop {
    basic: ConfigWithDrop,
    advanced: AdvancedSettings,
    metadata: vector<String>,
}

public struct AdvancedSettings has copy, drop {
    cache_size: u64,
    thread_count: u8,
}

public fun nested_copy_behavior() {
    let nested = NestedConfig {
        basic: ConfigWithDrop {
            max_users: 1000,
            timeout: 30,
            enabled: true,
        },
        advanced: AdvancedSettings {
            cache_size: 1024,
            thread_count: 4,
        },
        metadata: vector[
            string::utf8(b"production"),
            string::utf8(b"v2.0")
        ],
    };

    // 深層複製：所有嵌套結構都被完全複製到新記憶體位置
    let copy1 = nested;                    // 完整的深層複製
    let copy2 = nested;                    // 又一個完整的深層複製

    // 每個副本都有自己完整的記憶體空間
    demonstrate_nested_independence(nested, copy1, copy2);
}

public fun demonstrate_nested_independence(
    mut original: NestedConfig,
    mut copy1: NestedConfig,
    copy2: NestedConfig
) {
    // 修改原始版本的嵌套欄位
    original.basic.max_users = 5000;
    original.advanced.cache_size = 2048;
    vector::push_back(&mut original.metadata, string::utf8(b"modified"));

    // 修改第一個副本
    copy1.basic.timeout = 120;
    copy1.advanced.thread_count = 8;

    // 驗證所有副本都是獨立的
    assert!(original.basic.max_users == 5000, 1);
    assert!(copy1.basic.max_users == 1000, 2);     // 保持原值
    assert!(copy2.basic.max_users == 1000, 3);     // 保持原值

    assert!(original.basic.timeout == 30, 4);      // 保持原值
    assert!(copy1.basic.timeout == 120, 5);        // 被修改
    assert!(copy2.basic.timeout == 30, 6);         // 保持原值

    assert!(vector::length(&original.metadata) == 3, 7);  // 添加了元素
    assert!(vector::length(&copy1.metadata) == 2, 8);     // 保持原長度
    assert!(vector::length(&copy2.metadata) == 2, 9);     // 保持原長度
}

// === 性能考量 ===

public fun performance_considerations() {
    // 小型結構：複製開銷小
    let small_config = ConfigWithDrop {
        max_users: 100,
        timeout: 60,
        enabled: true,
    };

    // 複製開銷很小，可以頻繁複製
    let copy1 = small_config;
    let copy2 = small_config;
    let copy3 = small_config;
    // 所有副本自動清理

    // 大型結構：複製開銷較大
    let large_config = create_large_config();

    // 對於大型結構，考慮使用引用而不是複製
    process_large_config_by_reference(&large_config);  // 高效
    // process_large_config_by_copy(large_config);     // 可能較慢
}

public fun create_large_config(): NestedConfig {
    let mut metadata = vector::empty<String>();
    let mut i = 0;
    while (i < 1000) {  // 創建大量元資料
        vector::push_back(&mut metadata, string::utf8(b"item"));
        i = i + 1;
    };

    NestedConfig {
        basic: ConfigWithDrop {
            max_users: 10000,
            timeout: 300,
            enabled: true,
        },
        advanced: AdvancedSettings {
            cache_size: 1048576,  // 1MB
            thread_count: 16,
        },
        metadata,
    }
}

public fun process_large_config_by_reference(config: &NestedConfig) {
    // 高效：只傳遞引用，不複製資料
    let user_count = config.basic.max_users;
    let cache_size = config.advanced.cache_size;
    // 使用 user_count 和 cache_size...
}

public fun process_large_config_by_copy(config: NestedConfig) {
    // 較慢：整個結構被複製
    let user_count = config.basic.max_users;
    let cache_size = config.advanced.cache_size;
    // 使用 user_count 和 cache_size...
    // config 在函數結束時自動清理
}

// === 總結：記憶體模型 ===

/*
Move 中的 Copy + Drop 記憶體行為：

1. **Copy 行為**：
   - 創建完全獨立的副本
   - 每個副本有自己的記憶體位置
   - 深層複製：嵌套結構也被完全複製
   - 修改其中一個不影響其他副本

2. **Drop 行為**：
   - 每個副本在超出作用域時自動清理
   - 釋放各自的記憶體空間
   - 無需手動管理記憶體

3. **與引用的區別**：
   - 引用：指向同一記憶體位置，修改會影響原始值
   - 複製：創建新記憶體位置，修改不影響原始值

4. **性能影響**：
   - 小型結構：複製開銷小，可以頻繁使用
   - 大型結構：複製開銷大，考慮使用引用

5. **適用場景**：
   - 配置資料：通常較小，複製成本低
   - 計算結果：臨時資料，複製後使用
   - 元資料：需要在多處使用，但不共享狀態
*/
```

#### 計算結果和臨時資料

```move
// 計算結果：通常有 drop 能力
public struct CalculationResult has copy, drop {
    sum: u64,
    average: u64,
    count: u64,
}

public fun perform_analysis(data: vector<u64>): CalculationResult {
    let sum = 0;
    let count = vector::length(&data);

    let i = 0;
    while (i < count) {
        sum = sum + *vector::borrow(&data, i);
        i = i + 1;
    };

    CalculationResult {
        sum,
        average: if (count > 0) { sum / count } else { 0 },
        count,
    }
}

public fun use_analysis() {
    let data = vector[1, 2, 3, 4, 5];
    let result = perform_analysis(data);

    // 可以選擇只使用部分結果
    if (result.average > 3) {
        // 做某些處理
    }
    // result 自動被清理
}
```

#### 會話和狀態資料

```move
// 臨時會話資料
public struct SessionData has store, drop {
    user_id: address,
    login_time: u64,
    permissions: vector<String>,
}

public fun handle_session() {
    let session = SessionData {
        user_id: @0x123,
        login_time: 1234567890,
        permissions: vector[string::utf8(b"read"), string::utf8(b"write")],
    };

    // 處理會話
    if (is_valid_session(&session)) {
        execute_user_action(&session);
    }
    // session 自動清理，無需手動登出邏輯
}
```

### Drop 與其他能力的組合

#### Drop + Copy（最常見組合）

```move
// 最靈活的資料類型
public struct FlexibleData has copy, drop {
    name: String,
    value: u64,
    metadata: vector<String>,
}

public fun demonstrate_flexibility() {
    let data = FlexibleData {
        name: string::utf8(b"test"),
        value: 42,
        metadata: vector[string::utf8(b"tag1"), string::utf8(b"tag2")],
    };

    let copy1 = data;  // 複製
    let copy2 = data;  // 再次複製

    // 所有副本都會自動清理
    use_data(copy1);
    // copy2 和原始 data 自動清理
}
```

#### Store + Drop（可存儲的臨時資料）

```move
// 可以存儲在物件中，但也可以被丟棄
public struct TemporaryRecord has store, drop {
    event_type: String,
    timestamp: u64,
    details: String,
}

public struct EventLogger has key {
    id: UID,
    recent_events: vector<TemporaryRecord>,
}

public fun log_event(logger: &mut EventLogger, event: TemporaryRecord) {
    // 可以選擇存儲事件
    if (vector::length(&logger.recent_events) < 100) {
        vector::push_back(&mut logger.recent_events, event);
    } else {
        // 或者直接丟棄（如果日誌已滿）
        // event 自動被清理
    }
}
```

#### Key + Drop（理論組合，實際困難）

```move
// 理論上可能，但由於 UID 沒有 drop，實際很困難
// public struct DroppableObject has key, drop {
//     id: UID,  // UID 沒有 drop 能力
//     data: String,
// }
```

### Drop 能力的限制

#### 1. 傳遞性要求

```move
// 如果結構體要有 drop 能力，所有欄位都必須有 drop 能力
public struct ValidDrop has drop {
    field1: String,        // ✅ String 有 drop
    field2: u64,          // ✅ u64 有 drop
    field3: DroppableItem, // ✅ DroppableItem 有 drop
}

public struct DroppableItem has drop {
    name: String,
}

// 這會編譯錯誤：
// public struct InvalidDrop has drop {
//     field: NonDroppableItem,  // ❌ NonDroppableItem 沒有 drop
// }

public struct NonDroppableItem {
    data: String,
}
```

#### 2. 與資源安全的關係

```move
// 重要資產不應該有 drop 能力
public struct ImportantAsset has key, store {
    id: UID,
    value: u64,
    // 沒有 drop：防止意外丟失
}

// 輔助資料可以有 drop 能力
public struct AuxiliaryData has store, drop {
    cache: vector<u8>,
    computed_hash: vector<u8>,
}
```

### 具有 Drop 能力的類型

#### 所有原生類型

Move 中的所有原生類型都具有 `drop` 能力：

-   `bool`
-   無符號整數（`u8`, `u16`, `u32`, `u64`, `u128`, `u256`）
-   `vector<T>`（如果 T 有 drop 能力）
-   `address`

#### 標準庫類型

標準庫中定義的所有類型也都具有 `drop` 能力：

-   `Option<T>`（如果 T 有 drop 能力）
-   `String`
-   `TypeName`

#### 條件性 Drop 能力

```move
// vector 只有在元素類型有 drop 時才有 drop
vector<DroppableType>    // ✅ 有 drop（如果 DroppableType 有 drop）
vector<NonDroppableType> // ❌ 沒有 drop

// Option 同樣如此
Option<DroppableType>    // ✅ 有 drop（如果 DroppableType 有 drop）
Option<NonDroppableType> // ❌ 沒有 drop
```

### Witness 模式

具有單一 `drop` 能力的結構體被稱為 **Witness**。這是 Move 中一個重要的設計模式：

```move
// Witness：只有 drop 能力的結構體
public struct MyWitness has drop {}

// Witness 用於證明某種權限或條件
public fun create_protected_object(witness: MyWitness, ctx: &mut TxContext): ProtectedObject {
    // witness 的存在證明了呼叫者有權限創建這個物件
    let MyWitness {} = witness; // 消費 witness

    ProtectedObject {
        id: object::new(ctx),
        data: string::utf8(b"protected"),
    }
}

public struct ProtectedObject has key {
    id: UID,
    data: String,
}
```

### 設計模式

#### 1. 臨時計算模式

```move
// 用於函數內部的臨時計算
public struct TempCalculation has drop {
    intermediate_result: u64,
    step_count: u8,
}

public fun complex_computation(input: u64): u64 {
    let temp = TempCalculation {
        intermediate_result: input * 2,
        step_count: 1,
    };

    // 多步計算
    temp.intermediate_result = temp.intermediate_result + 10;
    temp.step_count = temp.step_count + 1;

    // 返回最終結果，temp 自動清理
    temp.intermediate_result
}
```

#### 2. 可選資料模式

```move
// 可選的額外資料
public struct OptionalMetadata has store, drop {
    author: Option<String>,
    tags: vector<String>,
    creation_date: Option<u64>,
}

public fun create_content(title: String, body: String, metadata: Option<OptionalMetadata>) {
    // 可以選擇使用或忽略 metadata
    match (metadata) {
        Some(meta) => {
            // 使用元資料
            process_with_metadata(title, body, meta);
        },
        None => {
            // 忽略元資料
            process_simple(title, body);
        }
    }
}
```

#### 3. 錯誤和結果模式

```move
// 可丟棄的錯誤資訊
public struct ProcessingError has drop {
    error_code: u64,
    message: String,
    recoverable: bool,
}

public fun safe_process(data: vector<u8>): Result<ProcessedData, ProcessingError> {
    if (vector::is_empty(&data)) {
        return Err(ProcessingError {
            error_code: 1,
            message: string::utf8(b"Empty data"),
            recoverable: true,
        });
    }

    // 處理資料...
    Ok(ProcessedData { /* ... */ })
}

public fun handle_processing() {
    match (safe_process(vector::empty())) {
        Ok(result) => use_result(result),
        Err(error) => {
            // 可以選擇記錄錯誤或直接忽略
            if (error.recoverable) {
                log_error(&error);
            }
            // error 自動被清理
        }
    }
}
```

### 性能考量

#### Drop 的開銷

```move
// 簡單資料的 drop 開銷很小
public struct SimpleData has drop {
    value: u64,
    flag: bool,
}

// 複雜資料的 drop 可能有開銷
public struct ComplexData has drop {
    large_vector: vector<vector<String>>,
    nested_data: vector<NestedStructure>,
}

public struct NestedStructure has drop {
    data: String,
    sub_items: vector<String>,
}

// 對於大型資料結構，考慮顯式清理
public fun handle_large_data() {
    let complex = create_complex_data();

    // 如果不再需要，可以顯式清理某些欄位
    vector::destroy_empty(complex.large_vector);

    // 剩餘部分自動清理
}
```

### 最佳實踐

#### 1. 合理使用 Drop

```move
// 好的設計：給適當的類型 drop 能力
public struct Configuration has copy, drop {
    settings: vector<String>,
    enabled: bool,
}

public struct TemporaryResult has drop {
    computation_result: u64,
    execution_time: u64,
}

// 謹慎設計：重要資產不要 drop
public struct DigitalAsset has key, store {
    id: UID,
    value: u64,
    // 沒有 drop：防止意外丟失
}
```

#### 2. 清晰的生命週期管理

```move
public fun process_data_with_cleanup() {
    // 創建臨時資料
    let temp_data = create_temporary_data();

    // 處理資料
    let result = process(temp_data);

    // temp_data 自動清理
    // 返回持久結果
    result
}
```

#### 3. 避免記憶體洩漏

```move
// 確保所有分配的資源都能被適當清理
public fun safe_resource_management() {
    let droppable = create_droppable_resource();
    let non_droppable = create_non_droppable_resource();

    // 使用資源
    use_resources(&droppable, &non_droppable);

    // droppable 自動清理
    // non_droppable 必須手動處理
    destroy_non_droppable(non_droppable);
}
```

### 總結

Drop 能力是 Move 類型系統中的基礎組件，它：

1. **簡化記憶體管理**：自動清理不再需要的值
2. **提供安全保證**：防止重要資產被意外丟棄
3. **支援靈活設計**：配合其他能力創建各種資料模式
4. **啟用 Witness 模式**：單一 drop 能力的特殊用途

**核心原則**：

-   給臨時資料和計算結果 drop 能力
-   不要給重要資產 drop 能力
-   利用編譯時檢查確保資源安全
-   合理組合能力以達到設計目標

Drop 能力體現了 Move「資源安全優先」的設計哲學，同時提供了足夠的靈活性來處理各種資料類型和使用模式。

---
