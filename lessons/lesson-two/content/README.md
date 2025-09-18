# Lesson 2: Sui Move 程式語言基礎

歡迎來到 Sui Move 程式語言的學習！本課程將深入介紹 Move 語言的核心概念，為您的 Sui 開發之旅奠定堅實基礎。

## 🎯 學習目標

完成本課程後，您將能夠：

-   理解 Sui Move 中資源和物件的概念與差異
-   掌握所有權（Ownership）系統的運作機制
-   熟悉 Move 語言的基本語法結構
-   了解能力系統（Abilities）的作用
-   能夠編寫基本的 Move 模組和函數

## 📚 課程大綱

### 1. Resources and Objects 的概念

#### Move 語言中的資源概念

**傳統 Move vs Sui Move**：

```move
// 傳統 Move 的資源概念
struct Coin has store {
    value: u64
}

// Sui Move 更注重物件模型
struct Coin has key, store {
    id: UID,
    value: u64
}
```

**重要差異**：

-   **傳統 Move**：強調資源的線性類型，不可複製和丟棄
-   **Sui Move**：淡化 Resources 概念，更注重 Objects 和所有權
-   **Sui 特色**：每個物件都有全域唯一的 UID

#### Objects 在 Sui 中的核心地位

**物件的基本特性**：

-   **全域唯一 ID（UID）**：每個物件都有唯一識別碼
-   **明確的所有權**：物件的擁有者是確定的
-   **可轉移性**：物件可以在地址間轉移
-   **版本控制**：每次修改都會增加版本號

### 2. Ownership 所有權概念

#### 四種所有權類型

**2.1 單一所有權（Owned）**

```move
// 被特定地址擁有的物件
struct PersonalNFT has key {
    id: UID,
    name: String,
    description: String,
}
```

-   **特點**：一個地址完全擁有
-   **處理**：可並行執行，無需共識
-   **適用**：個人資產、NFT、遊戲道具

**2.2 共享所有權（Shared）**

```move
// 多人可存取的共享物件
struct LiquidityPool has key {
    id: UID,
    token_a_balance: u64,
    token_b_balance: u64,
}
```

-   **特點**：多個地址可同時存取
-   **處理**：需要共識機制
-   **適用**：DEX 流動性池、多人遊戲狀態

**2.3 不可變物件（Immutable）**

```move
// 創建後不可修改的物件
struct Config has key {
    id: UID,
    network_fee: u64,
    max_supply: u64,
}
```

-   **特點**：創建後永不修改
-   **處理**：最高效率，無限制存取
-   **適用**：配置參數、常數、程式碼

**2.4 子物件（Child Objects）**

```move
// 被其他物件擁有的子物件
struct GameCharacter has key {
    id: UID,
    level: u8,
    equipment: vector<Equipment>,
}

struct Equipment has key, store {
    id: UID,
    name: String,
    power: u64,
}
```

### 3. Models and Functions

#### 3.1 模組結構（Module Structure）

```move
module my_package::my_module {
    // 引入依賴
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    // 結構體定義
    struct MyObject has key {
        id: UID,
        value: u64,
    }

    // 函數定義
    public fun create_object(value: u64, ctx: &mut TxContext): MyObject {
        MyObject {
            id: object::new(ctx),
            value,
        }
    }
}
```

#### 3.2 函數類型

**Public Functions（公開函數）**：

```move
// 可被外部調用
public fun transfer_object(obj: MyObject, recipient: address) {
    transfer::public_transfer(obj, recipient);
}
```

**Entry Functions（入口函數）**：

```move
// 可直接從交易調用
public entry fun mint_nft(name: String, ctx: &mut TxContext) {
    let nft = NFT {
        id: object::new(ctx),
        name,
    };
    transfer::public_transfer(nft, tx_context::sender(ctx));
}
```

**Private Functions（私有函數）**：

```move
// 只能在模組內部使用
fun internal_calculation(a: u64, b: u64): u64 {
    a + b
}
```

### 4. Basic Structure of Move Project

#### 4.1 專案目錄結構

```
my_sui_project/
├── Move.toml             # 專案配置文件
├── sources/              # 原始碼目錄
│   ├── main.move         # 主要模組
│   └── utils.move        # 工具模組
└── tests/                # 測試文件
    └── main_test.move    # 測試代碼
```

#### 4.2 Move.toml 配置

```toml
[package]
name = "my_sui_project"
version = "0.1.0"
edition = "2024.beta"

[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "testnet" }

[addresses]
my_package = "0x0"
```

### 5. Variables, Data Types, and Mutability

#### 5.1 基本資料型別

**數值型別**：

```move
fun data_types_example() {
    // 整數型別
    let small_number: u8 = 255;
    let medium_number: u64 = 1000000;
    let large_number: u128 = 340282366920938463463374607431768211455;

    // 布林型別
    let is_valid: bool = true;

    // 地址型別
    let addr: address = @0x1;
}
```

**複合型別**：

```move
fun composite_types() {
    // 向量（Vector）
    let numbers: vector<u64> = vector[1, 2, 3, 4, 5];

    // 選項型別（Option）
    let maybe_value: Option<u64> = option::some(42);

    // 字串（String）
    let text: String = string::utf8(b"Hello, Sui!");
}
```

#### 5.2 可變性（Mutability）

```move
fun mutability_example() {
    // 不可變變數
    let immutable_value = 100;

    // 可變變數
    let mut mutable_value = 100;
    mutable_value = 200; // 可以修改

    // 可變引用
    let mut vec = vector[1, 2, 3];
    vector::push_back(&mut vec, 4);
}
```

### 6. Common Design Patterns

#### 6.1 物件創建模式

```move
// 基本物件創建
public fun create_and_transfer(
    name: String,
    recipient: address,
    ctx: &mut TxContext
) {
    let obj = MyObject {
        id: object::new(ctx),
        name,
    };
    transfer::public_transfer(obj, recipient);
}
```

#### 6.2 物件修改模式

```move
// 物件狀態修改
public fun update_object(obj: &mut MyObject, new_value: u64) {
    obj.value = new_value;
}
```

#### 6.3 物件銷毀模式

```move
// 銷毀物件並提取值
public fun destroy_and_extract(obj: MyObject): u64 {
    let MyObject { id, value } = obj;
    object::delete(id);
    value
}
```

### 7. 基礎語法：Abilities 能力系統

#### 7.1 四種核心能力

**Key 能力**：

```move
// 具有 key 能力的結構體可以作為頂層物件
struct TopLevelObject has key {
    id: UID,
    data: String,
}
```

**Store 能力**：

```move
// 具有 store 能力的結構體可以存儲在其他結構體中
struct StorableData has store {
    value: u64,
    metadata: String,
}

struct Container has key {
    id: UID,
    data: StorableData, // 可以包含具有 store 能力的結構體
}
```

**Copy 能力**：

```move
// 具有 copy 能力的結構體可以被複製
struct CopyableData has copy, store {
    number: u64,
}

fun use_copy() {
    let data = CopyableData { number: 42 };
    let data_copy = data; // 自動複製
    // 原始 data 仍然可用
}
```

**Drop 能力**：

```move
// 具有 drop 能力的結構體可以被自動銷毀
struct DroppableData has drop {
    temp_value: u64,
}

fun use_drop() {
    let temp = DroppableData { temp_value: 123 };
    // 函數結束時自動銷毀，無需手動處理
}
```

#### 7.2 能力組合規則

```move
// 常見的能力組合
struct NFT has key, store {          // 可以是頂層物件，也可以被存儲
    id: UID,
    name: String,
}

struct Currency has key, store {     // 貨幣類型物件
    id: UID,
    value: u64,
}

struct Configuration has copy, drop, store {  // 配置資料
    fee_rate: u64,
    max_limit: u64,
}
```

## 🔧 實際程式範例

### 簡單的 NFT 實作

```move
module nft_example::simple_nft {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::string::String;

    // NFT 結構體：具有 key 和 store 能力
    struct SimpleNFT has key, store {
        id: UID,
        name: String,
        description: String,
        creator: address,
    }

    // 創建 NFT 的入口函數
    public entry fun mint_nft(
        name: String,
        description: String,
        ctx: &mut TxContext
    ) {
        let nft = SimpleNFT {
            id: object::new(ctx),
            name,
            description,
            creator: tx_context::sender(ctx),
        };

        // 轉移給創建者
        transfer::public_transfer(nft, tx_context::sender(ctx));
    }

    // 轉移 NFT
    public entry fun transfer_nft(
        nft: SimpleNFT,
        recipient: address,
    ) {
        transfer::public_transfer(nft, recipient);
    }

    // 查看 NFT 資訊
    public fun get_nft_info(nft: &SimpleNFT): (&String, &String, address) {
        (&nft.name, &nft.description, nft.creator)
    }
}
```

## 🎯 重點總結

### Sui Move 的特殊之處

1. **物件優先**：相比傳統 Move，Sui Move 更注重物件模型
2. **所有權清晰**：四種明確的所有權類型
3. **並行友好**：物件的獨立性支持並行處理
4. **能力系統**：fine-grained 控制結構體的行為

### 開發最佳實踐

1. **合理使用能力**：根據需求選擇適當的 abilities 組合
2. **明確所有權**：設計時考慮物件的所有權類型
3. **模組化設計**：將相關功能組織在同一模組中
4. **錯誤處理**：使用 Option 和 Result 處理可能的錯誤

## 🚀 下一步學習

掌握這些基礎概念後，您可以：

1. **實作練習**：編寫自己的 Move 模組
2. **進階主題**：學習事件發射、動態字段等
3. **專案開發**：開始開發完整的 dApp
4. **最佳實踐**：學習安全性和效能優化

---

**提示**：Move 語言的學習需要大量實踐。建議您邊學習邊動手編寫程式碼，這樣能更好地理解這些概念！
