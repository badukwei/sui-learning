# Move 可見性系統（Visibility System）

## 概述

在 Move 中，每個模組成員都有可見性。預設情況下，所有模組成員（函數、結構體、常數等）都是私有的 - 意味著它們只能在定義它們的模組內存取。但是，您可以添加可見性修飾符來使模組成員具有不同的存取權限。

## 適用於所有模組成員

可見性系統適用於：

-   **函數（Functions）**
-   **結構體（Structs）**
-   **常數（Constants）**
-   **使用宣告（Use Declarations）**

## 四種可見性類型

| 可見性類型   | 關鍵字            | 存取範圍        | 適用成員           |
| ------------ | ----------------- | --------------- | ------------------ |
| **Internal** | 無修飾符          | 僅限模組內部    | 函數、結構體、常數 |
| **Public**   | `public`          | 所有模組        | 函數、結構體、常數 |
| **Package**  | `public(package)` | 同一 package 內 | 函數、結構體、常數 |
| **Entry**    | `entry`           | 交易入口        | 僅限函數           |

---

## 1. Internal Visibility（內部可見性）

### 定義

在模組中定義的函數、結構體或常數，如果沒有可見性修飾符，則對模組來說是私有的。它們無法從其他模組存取。

### 範例

```move
module book::internal_visibility;

// 內部常數
const MAX_LEVEL: u8 = 100;

// 內部結構體
struct InternalData {
    value: u64,
    is_valid: bool,
}

// 內部函數
fun internal_function() {
    // 內部邏輯
}

// 內部輔助函數
fun validate_data(data: &InternalData): bool {
    data.is_valid && data.value > 0
}

// 同一模組 -> 可以使用所有內部成員
fun call_internal() {
    let data = InternalData { value: 50, is_valid: true };

    if (validate_data(&data)) {
        internal_function();
    }
}
```

### 錯誤範例

以下程式碼無法編譯：

```move
module book::try_calling_internal;

use book::internal_visibility;

// 不同模組 -> 無法存取內部成員
fun try_calling_internal() {
    // ❌ 編譯錯誤：無法存取內部函數
    internal_visibility::internal_function();

    // ❌ 編譯錯誤：無法存取內部結構體
    let data = internal_visibility::InternalData { value: 1, is_valid: true };

    // ❌ 編譯錯誤：無法存取內部常數
    let max = internal_visibility::MAX_LEVEL;
}
```

### 使用場景

```move
module game::character;

// 內部常數
const MAX_LEVEL: u8 = 100;
const BASE_HEALTH: u64 = 100;

// 內部結構體
struct CharacterStats {
    strength: u8,
    defense: u8,
    agility: u8,
}

// 內部輔助函數
fun calculate_damage(base: u64, multiplier: u64): u64 {
    base * multiplier
}

// 內部驗證函數
fun validate_level(level: u8): bool {
    level > 0 && level <= MAX_LEVEL
}

// 內部統計計算
fun calculate_health(stats: &CharacterStats, level: u8): u64 {
    BASE_HEALTH + (stats.strength as u64) * (level as u64)
}

// 公開函數使用內部成員
public fun attack(attacker_power: u64, defender_defense: u64): u64 {
    if (validate_level(attacker_power as u8)) {
        calculate_damage(attacker_power, 2)
    } else {
        0
    }
}
```

---

## 2. Public Visibility（公開可見性）

### 定義

結構體、函數或常數可以通過在相應關鍵字前添加 `public` 關鍵字來設為公開。公開成員可以從任何模組存取。

### 範例

```move
module book::public_visibility;

// 公開常數
public const MAX_SUPPLY: u64 = 1000000;

// 公開結構體
public struct PublicData has drop {
    value: u64,
    timestamp: u64,
}

// 公開函數
public fun public_function(): u64 {
    MAX_SUPPLY
}

// 公開創建函數
public fun create_data(value: u64): PublicData {
    PublicData {
        value,
        timestamp: 12345, // 簡化的時間戳
    }
}
```

### 成功範例

公開成員可以從其他模組匯入和使用：

```move
module book::try_calling_public;

use book::public_visibility;

// 不同模組 -> 可以使用所有公開成員
fun try_calling_public() {
    // ✅ 編譯成功：存取公開常數
    let max = public_visibility::MAX_SUPPLY;

    // ✅ 編譯成功：呼叫公開函數
    let value = public_visibility::public_function();

    // ✅ 編譯成功：創建公開結構體
    let data = public_visibility::create_data(100);
}
```

### 實際應用

```move
module defi::token;

// 公開常數
public const DECIMALS: u8 = 9;
public const TOTAL_SUPPLY: u64 = 1000000000;

// 公開結構體
public struct Token has key, store {
    id: UID,
    value: u64,
}

// 公開結構體（元資料）
public struct TokenMetadata has drop, store {
    name: vector<u8>,
    symbol: vector<u8>,
    decimals: u8,
}

// 公開創建函數
public fun mint(value: u64, ctx: &mut TxContext): Token {
    Token {
        id: object::new(ctx),
        value,
    }
}

// 公開轉移函數
public fun transfer(token: Token, recipient: address) {
    transfer::public_transfer(token, recipient);
}

// 公開查詢函數
public fun value(token: &Token): u64 {
    token.value
}

// 公開獲取元資料函數
public fun get_metadata(): TokenMetadata {
    TokenMetadata {
        name: b"MyToken",
        symbol: b"MTK",
        decimals: DECIMALS,
    }
}
```

**重要注意**：

-   結構體欄位無法設為公開（與某些語言不同）
-   常數可以設為公開，方便其他模組使用
-   結構體可以設為公開，但欄位存取仍需要通過函數

---

## 3. Package Visibility（包可見性）

### 定義

具有 package 可見性的函數、結構體或常數可以從同一 package 內的任何模組存取，但不能從其他 package 中的模組存取。換句話說，它們是 package 內部的。

### 範例

```move
module book::package_visibility;

// Package 內部常數
public(package) const INTERNAL_CONFIG: u64 = 12345;

// Package 內部結構體
public(package) struct PackageData has drop {
    sensitive_info: vector<u8>,
    internal_id: u64,
}

// Package 內部函數
public(package) fun package_only_function() {
    // Package 內部邏輯
}

// Package 內部創建函數
public(package) fun create_package_data(info: vector<u8>): PackageData {
    PackageData {
        sensitive_info: info,
        internal_id: INTERNAL_CONFIG,
    }
}
```

### 成功範例

Package 成員可以從同一 package 內的任何模組存取：

```move
module book::try_calling_package;

use book::package_visibility;

// 同一 package `book` -> 可以存取所有 package 成員
fun try_calling_package() {
    // ✅ 編譯成功：存取 package 常數
    let config = package_visibility::INTERNAL_CONFIG;

    // ✅ 編譯成功：呼叫 package 函數
    package_visibility::package_only_function();

    // ✅ 編譯成功：創建 package 結構體
    let data = package_visibility::create_package_data(b"secret");
}
```

### 實際應用

```move
// Package: game
module game::character;

// Package 內部常數
public(package) const MAX_LEVEL: u8 = 100;
public(package) const EXP_PER_LEVEL: u64 = 1000;

// 公開結構體
public struct Character has key {
    id: UID,
    level: u8,
    experience: u64,
}

// Package 內部結構體 - 敏感的統計資料
public(package) struct CharacterStats has drop {
    base_stats: vector<u8>,
    hidden_bonuses: u64,
    internal_flags: u8,
}

// Package 內部函數 - 只有遊戲模組可以直接修改角色等級
public(package) fun level_up(character: &mut Character) {
    if (character.level < MAX_LEVEL) {
        character.level = character.level + 1;
    }
}

// Package 內部函數 - 只有遊戲模組可以增加經驗值
public(package) fun add_experience(character: &mut Character, exp: u64) {
    character.experience = character.experience + exp;
}

// Package 內部函數 - 獲取內部統計資料
public(package) fun get_internal_stats(character: &Character): CharacterStats {
    CharacterStats {
        base_stats: vector[character.level, 50, 30],
        hidden_bonuses: character.experience / EXP_PER_LEVEL,
        internal_flags: 0,
    }
}
```

```move
module game::quest;

use game::character;

// 同一 package -> 可以存取所有 package 成員
public fun complete_quest(character: &mut character::Character) {
    // 存取 package 常數
    let max_exp = character::EXP_PER_LEVEL;

    // 呼叫 package 函數
    character::add_experience(character, max_exp / 2);
    character::level_up(character);

    // 獲取 package 內部統計資料
    let stats = character::get_internal_stats(character);
}
```

---

## 4. Entry Functions（入口函數）

### 定義

`entry` 函數是可以直接從交易呼叫的函數，但不能從其他模組呼叫。它們是區塊鏈交易的入口點。

### 範例

```move
module game::actions;

use game::character::Character;

// 入口函數 - 可以從交易呼叫
entry fun create_character(name: vector<u8>, ctx: &mut TxContext) {
    let character = Character {
        id: object::new(ctx),
        name: string::utf8(name),
        level: 1,
        experience: 0,
    };

    transfer::transfer(character, tx_context::sender(ctx));
}

// 入口函數 - 戰鬥動作
entry fun battle(
    attacker: &mut Character,
    defender: &mut Character,
    ctx: &TxContext
) {
    // 戰鬥邏輯
    let damage = calculate_battle_damage(attacker, defender);
    apply_damage(defender, damage);
}
```

### Entry vs Public 對比

```move
module example::comparison;

// Entry 函數：可從交易呼叫，不可從其他模組呼叫
entry fun entry_function(value: u64) {
    // 只能通過交易呼叫
}

// Public 函數：可從其他模組呼叫，也可從交易呼叫
public fun public_function(value: u64) {
    // 可以從任何地方呼叫
}

// Public Entry 函數：兩者兼具
public entry fun public_entry_function(value: u64) {
    // 既可從交易呼叫，也可從其他模組呼叫
}
```

---

## 5. Native Functions（原生函數）

### 定義

框架和標準庫中的某些函數標記有 `native` 修飾符。這些函數由 Move VM 原生提供，在 Move 原始碼中沒有函數體。

### 範例

```move
module std::type_name;

public native fun get<T>(): TypeName;
```

### 常見原生函數

```move
// 雜湊函數
module std::hash;
public native fun sha2_256(data: vector<u8>): vector<u8>;
public native fun sha3_256(data: vector<u8>): vector<u8>;

// 簽名驗證
module std::ed25519;
public native fun verify(
    signature: vector<u8>,
    public_key: vector<u8>,
    message: vector<u8>
): bool;

// BCS 序列化
module std::bcs;
public native fun to_bytes<T>(v: &T): vector<u8>;
```

---

## 6. 已棄用：Friends（朋友宣告）

> **注意**：此功能已被 `public(package)` 取代。

### 歷史背景

Friend 語法用於宣告受當前模組信任的模組。受信任的模組可以呼叫當前模組中定義的任何具有 `public(friend)` 可見性的函數。

### 朋友宣告（已棄用）

```move
module 0x42::a {
    friend 0x42::b;  // 宣告 0x42::b 為朋友模組
}

// 或使用別名
module 0x42::a {
    use 0x42::b;
    friend b;
}
```

### 朋友宣告規則

1. **模組不能宣告自己為朋友**

```move
module 0x42::m {
    friend Self; // ❌ 錯誤！
}
```

2. **朋友模組必須為編譯器所知**

```move
module 0x42::m {
    friend 0x42::nonexistent; // ❌ 錯誤！未綁定的模組
}
```

3. **朋友模組必須在同一帳戶地址內**

```move
module 0x42::m {}
module 0x43::n {
    friend 0x42::m; // ❌ 錯誤！不能宣告不同地址的模組為朋友
}
```

4. **朋友關係不能創建循環模組依賴**

5. **朋友列表不能包含重複項**

---

## 7. 最佳實踐與設計指南

### 可見性選擇策略

```move
module game::inventory;

// 1. 內部輔助函數
fun validate_item_id(id: u64): bool {
    id > 0 && id < 10000
}

// 2. Package 內部函數 - 只允許遊戲邏輯模組使用
public(package) fun add_item_direct(inventory: &mut Inventory, item: Item) {
    // 繞過某些檢查的內部添加
    vector::push_back(&mut inventory.items, item);
}

// 3. 公開函數 - 外部 dApp 可以使用
public fun add_item_safe(inventory: &mut Inventory, item: Item) {
    assert!(validate_item_id(item.id), 1);
    add_item_direct(inventory, item);
}

// 4. 入口函數 - 玩家可以直接從交易呼叫
entry fun equip_item(
    inventory: &mut Inventory,
    item_id: u64,
    ctx: &TxContext
) {
    // 裝備邏輯
}
```

### 安全性考量

```move
module defi::vault;

public struct Vault has key {
    id: UID,
    balance: u64,
    owner: address,
}

// ❌ 錯誤：過於開放的公開函數
// public fun set_balance(vault: &mut Vault, amount: u64) {
//     vault.balance = amount;
// }

// ✅ 正確：安全的公開函數
public fun deposit(vault: &mut Vault, amount: u64, ctx: &TxContext) {
    assert!(tx_context::sender(ctx) == vault.owner, 1);
    vault.balance = vault.balance + amount;
}

// ✅ 正確：Package 內部函數用於特殊邏輯
public(package) fun admin_set_balance(vault: &mut Vault, amount: u64) {
    vault.balance = amount;
}
```

### 模組組織建議

```move
// Package: marketplace
module marketplace::core;      // 核心邏輯，使用 public(package)
module marketplace::api;       // 外部 API，使用 public
module marketplace::admin;     // 管理功能，使用 public(package)
module marketplace::events;    // 事件，使用 public

// Package: game
module game::character;        // 角色系統
module game::items;           // 道具系統
module game::battle;          // 戰鬥系統
module game::economy;         // 經濟系統
```

---

## 8. 總結

### 可見性選擇指南

| 使用場景        | 推薦可見性                | 原因                  |
| --------------- | ------------------------- | --------------------- |
| **輔助函數**    | Internal                  | 避免外部依賴內部實現  |
| **Package API** | `public(package)`         | 控制 Package 邊界     |
| **外部 API**    | `public`                  | 允許其他 Package 使用 |
| **交易入口**    | `entry` 或 `public entry` | 直接從交易呼叫        |
| **管理功能**    | `public(package)`         | 限制敏感操作          |

### 核心原則

1. **最小權限原則**：使用最限制性的可見性
2. **明確邊界**：清楚定義 Package 內外的 API
3. **安全第一**：敏感操作使用 Package 可見性
4. **用戶友好**：提供清晰的 Entry 函數
5. **模組化設計**：合理組織模組和可見性

### 常見錯誤

```move
// ❌ 過度公開
public fun internal_helper() { }

// ✅ 適當隱藏
fun internal_helper() { }

// ❌ 過度限制
fun user_facing_api() { }

// ✅ 適當公開
public entry fun user_facing_api() { }
```

正確的可見性設計是構建安全、可維護 Move 代碼的關鍵！
