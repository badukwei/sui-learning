# Sui 物件所有權系統詳解

## 概述

Sui 引入了五種不同的物件所有權類型：**地址擁有物件（Address-Owned Objects）**、**不可變物件（Immutable Objects）**、**Party Objects（Party Objects）**、**共享物件（Shared Objects）**和**包裝物件（Wrapped Objects）**。每種模型都提供獨特的特性，適合不同的使用場景，增強了物件管理的靈活性和控制力。

> **重要提醒**：所有權不控制物件的機密性 - 從 Move 外部始終可以讀取鏈上物件的內容。您永遠不應該在物件內存儲未加密的秘密。

## 五種所有權類型概覽

| 所有權類型        | 特性             | 存取權限             | 典型用途             |
| ----------------- | ---------------- | -------------------- | -------------------- |
| **Address-Owned** | 單一帳戶專屬控制 | 只有擁有者可修改     | Coin、個人物件       |
| **Immutable**     | 永久只讀狀態     | 所有人可讀，無人可寫 | ColorObject、配置    |
| **Party**         | 黨派控制存取     | 黨派成員可存取       | 多人協作、組織管理   |
| **Shared**        | 網路共享存取     | 任何帳戶可讀寫       | AMM、市場     |
| **Wrapped**       | 物件擁有物件     | 通過父物件存取       | 遊戲系統 |

---

## 1. Address-Owned Objects（地址擁有物件）

### 核心概念

地址擁有物件由特定的 32 位元組地址擁有，該地址可以是帳戶地址（從特定簽名方案衍生）或物件 ID。地址擁有物件只能由其擁有者存取，其他人無法存取。

作為擁有地址擁有物件的擁有者，您可以將其轉移到不同的地址。因為只有單一擁有者可以存取這些物件，您可以並行執行僅使用擁有物件且沒有任何共同物件的交易，而無需通過共識。

### 創建地址擁有物件

使用這些 transfer 模組函數來創建地址擁有物件：

```move
public fun transfer<T: key>(obj: T, recipient: address)
public fun public_transfer<T: key + store>(obj: T, recipient: address)
```

如果您為物件定義自定義轉移政策，應使用 `sui::transfer::transfer` 函數。如果物件具有 `store` 能力，使用 `sui::transfer::public_transfer` 函數來創建地址擁有物件。

### 官方範例 - Coin 轉移

地址擁有物件的典型範例是 Coin 物件。如果地址 0xA11CE 有一個價值 100 SUI 的硬幣 C，想要支付地址 0xB0B 100 SUI，0xA11CE 可以通過將 C 轉移到 0xB0B 來實現：

```move
transfer::public_transfer(C, @0xB0B);
```

這會導致 C 擁有新的地址擁有者 0xB0B，0xB0B 稍後可以使用那 100 SUI 硬幣。

### 何時使用地址擁有物件

在您需要以下情況時使用地址擁有物件：

-   **任何時候的單一所有權**
-   **比共享物件更好的性能**
-   **避免共識排序**

### 存取地址擁有物件

您可以用兩種不同的方式存取地址擁有物件，取決於物件的地址擁有者是否對應於物件 ID：

-   如果物件的地址擁有者對應於物件 ID，則必須在交易執行期間使用 Transfer to Object 中定義的機制來存取和動態驗證它
-   如果物件的地址擁有者是簽名衍生地址（帳戶地址），則可以在該地址簽名的交易執行期間直接將其用作擁有物件存取

---

## 2. Immutable Objects（不可變物件）

### 核心概念

Sui 中的物件有不同的所有權類型，主要分為兩類：不可變物件和可變物件。不可變物件無法被變更、轉移或刪除。這些物件沒有擁有者，對所有人都是自由可存取的。

### 創建不可變物件

要使物件變為不可變，請從 transfer 模組呼叫 `public_freeze_object` 函數：

```move
public native fun public_freeze_object<T: key>(obj: T);
```

此呼叫永久使物件變為不可變。此操作無法逆轉。只有在確定永遠不需要修改時才凍結物件。

#### 基本範例 - ColorObject

```move
// 創建並立即凍結的 API
public fun create_immutable(red: u8, green: u8, blue: u8, ctx: &mut TxContext) {
    let color_object = new(red, green, blue, ctx);
    transfer::public_freeze_object(color_object)
}
```

這個函數創建一個新的 ColorObject 並在它有擁有者之前立即使其變為不可變。

#### 從已有物件創建不可變物件

```move
{
    ts.next_tx(alice);
    // 創建一個新的 ColorObject
    let c = new(255, 0, 255, ts.ctx());
    // 使其變為不可變
    transfer::public_freeze_object(c);
};
```

在這個測試中，您必須首先擁有一個 ColorObject。凍結後，物件變為不可變且無擁有者。

### 不可變物件的特性

#### 1. 永久只讀

物件變為不可變後，在 Sui Move 呼叫中使用此物件的規則會改變：您只能將不可變物件作為只讀、不可變引用 `&T` 傳遞給 Sui Move 入口函數。

所有網路參與者都可以存取不可變物件。

```move
// 複製一個物件的值到另一個物件的函數
public fun copy_into(from: &ColorObject, into: &mut ColorObject);
```

在這個函數中，任何人都可以將不可變物件作為第一個參數 `from` 傳遞，但不能作為第二個參數。因為您永遠無法變更不可變物件，所以即使多個交易同時使用相同的不可變物件，也不會有資料競爭。因此，不可變物件的存在不會對共識產生任何要求。

#### 2. 測試不可變物件

您可以在單元測試中使用 `test_scenario::take_immutable<T>` 從全域存儲中取得不可變物件包裝器，使用 `test_scenario::return_immutable` 將包裝器返回到全域存儲。

```move
let sender1 = @0x1;
let scenario_val = test_scenario::begin(sender1);
let scenario = &mut scenario_val;
{
    let ctx = test_scenario::ctx(scenario);
    color_object::create_immutable(255, 0, 255, ctx);
};
scenario.next_tx(sender1);
{
    // has_most_recent_for_sender 對不可變物件返回 false
    assert!(!test_scenario::has_most_recent_for_sender<ColorObject>(scenario))
};

// 任何發送者都可以工作
let sender2 = @0x2;
scenario.next_tx(sender2);
{
    let object = test_scenario::take_immutable<ColorObject>(scenario);
    let (red, green, blue) = color_object::get_color(object);
    assert!(red == 255 && green == 0 && blue == 255)
    test_scenario::return_immutable(object);
};
```

#### 3. CLI 互動範例

創建並凍結物件的完整流程：

```bash
# 1. 查看您擁有的物件
$ export ADDR=`sui client active-address`
$ sui client objects $ADDR

# 2. 發布合約
$ sui client publish $ROOT/examples/move/color_object

# 3. 創建新的 ColorObject
$ sui client call --package $PACKAGE --module "color_object" --function "create" --args 0 255 0

# 4. 將物件設為不可變
$ sui client call --package $PACKAGE --module "color_object" --function "freeze_object" --args \"$OBJECT\"

# 5. 驗證物件狀態
$ sui client object $OBJECT
```

回應包含：

```
Owner: Immutable  // 此欄位顯示物件的不可變狀態
```

如果嘗試變更不可變物件：

```bash
$ sui client call --package $PACKAGE --module "color_object" --function "update" --args \"$OBJECT\" 0 0 0
```

回應會指出您無法將不可變物件傳遞給可變參數。

### 不可變物件的特點

ColorObject 範例展示了不可變物件的核心特點：

-   **永久只讀**：物件無法被修改或移動
-   **無擁有者**：物件不屬於任何特定地址
-   **全域可存取**：所有網路參與者都可以讀取
-   **無共識需求**：讀取操作不需要網路共識
-   **測試友好**：提供專門的測試工具

---

## 3. Party Objects

### 核心概念

Party Objects 是使用 `sui::transfer::party_transfer` 或 `sui::transfer::public_party_transfer` 函數轉移的物件。它可以被轉移到的 Party 存取。

Party Objects 結合了地址擁有物件和共享物件的某些屬性。像地址擁有物件一樣，它們可以由單一地址擁有。像共享物件一樣，它們由共識進行版本控制。與共享物件不同，它們可以轉移到其他所有權類型並且可以被包裝。

> **注意**：目前，單一所有權是Party Objects唯一支援的模式。如果增加對多個擁有者或更細緻權限的支援，本主題將會更新。

### 創建Party Objects

使用以下函數（在 transfer 模組中定義）來創建Party Objects：

```move
public fun party_transfer<T: key>(obj: T, party: sui::party::Party)
public fun public_party_transfer<T: key + store>(obj: T, party: sui::party::Party)
```

如果您為物件定義自定義轉移政策，使用 `sui::transfer::party_transfer` 函數。如果物件具有 `store` 能力，使用 `sui::transfer::public_party_transfer` 函數。

Party Objects 的所有權可以在其生命週期內改變。例如，透過將其添加為動態物件欄位、將其轉移到不同地址或擁有者類型，或使其不可變。一個例外：在創建物件並設定其所有權後，您無法稍後共享它。

### 存取Party Objects

您可以像共享物件一樣將 Party Objects 指定為交易的輸入。Sui 驗證器確保交易的發送者可以存取該物件。如果輸入Party Objects的擁有者因較早的衝突交易而改變，驗證器可能會在執行時中止交易。

透過轉移到物件機制的存取不支援擁有地址對應於物件 ID 的Party Objects。

### 何時使用Party Objects

當您希望物件由共識進行版本控制時使用 Party Objects，例如為了操作便利性。如果物件僅與其他 Party 或共享物件一起使用，將其轉換為 Party Objects 不會產生額外的性能成本。

Party Objects 可以同時被多個進行中的交易使用。這與地址擁有物件形成對比，後者只允許單一進行中的交易。許多應用程式可以從在同一Party Objects上流水線多個交易的能力中受益。

> **重要**：Coin 可以是 Party Objects，包括 Coin<SUI>。但是，您不能使用 Party Objects Coin<SUI> 進行 gas 付款。要將 Party Objects Coin<SUI> 用於 gas，您必須首先將其轉移回地址擁有。

---

## 4. Shared Objects（共享物件）

### 核心概念

使用 `sui::transfer::share_object` 函數創建共享物件，使其在網路上公開可存取。共享物件的擴展功能和可存取性需要額外的努力來保護存取（如果需要）。

共享物件需要 `key` 能力。

### 共享物件的創建與使用

以下範例創建了一個出售數位甜甜圈的商店。每個人都需要存取商店來購買甜甜圈，因此使用 `sui::transfer::share_object` 將商店創建為共享物件。

```move
module examples::donuts;

use sui::sui::SUI;
use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance};

/// 當 Coin 餘額太低時的錯誤
const ENotEnough: u64 = 0;

/// 授予擁有者收取利潤權利的能力
public struct ShopOwnerCap has key { id: UID }

/// 可購買的甜甜圈
public struct Donut has key { id: UID }

/// 共享物件，需要 `key` 能力
public struct DonutShop has key {
    id: UID,
    price: u64,
    balance: Balance<SUI>
}

/// Init 函數通常是初始化共享物件的理想場所，因為它只被呼叫一次
fun init(ctx: &mut TxContext) {
    transfer::transfer(ShopOwnerCap {
        id: object::new(ctx)
    }, ctx.sender());

    // 共享物件使其對所有人都可存取！
    transfer::share_object(DonutShop {
        id: object::new(ctx),
        price: 1000,
        balance: balance::zero()
    })
}
```

### 共享物件的特性

#### 1. 多方存取

```move
/// 任何擁有 Coin 的人都可以使用的入口函數
public fun buy_donut(
    shop: &mut DonutShop,
    payment: &mut Coin<SUI>,
    ctx: &mut TxContext
) {
    assert!(coin::value(payment) >= shop.price, ENotEnough);

    // 從 Coin<SUI> 中取出金額 = `shop.price`
    let paid = payment.balance_mut.split(shop.price);

    // 將硬幣放入商店的餘額中
    shop.balance.join(paid);

    transfer::transfer(Donut {
        id: object::new(ctx)
    }, ctx.sender())
}

/// 消費甜甜圈然後什麼都不剩...
public fun eat_donut(d: Donut) {
    let Donut { id } = d;
    id.delete();
}

/// 從 `DonutShop` 取出硬幣並轉移給交易發送者
/// 需要 `ShopOwnerCap` 授權
public fun collect_profits(
    _: &ShopOwnerCap,
    shop: &mut DonutShop,
    ctx: &mut TxContext
) {
    let amount = shop.balance.value();
    let profits = shop.balance.split(amount).into_coin(ctx);

    transfer::public_transfer(profits, ctx.sender())
}
```

#### 2. 存取控制和權限管理

甜甜圈商店範例展示了如何在共享物件中實現存取控制：

-   **公開操作**：任何人都可以購買甜甜圈（`buy_donut`）
-   **受限操作**：只有店主可以收取利潤（`collect_profits`）

```move
/// 這個函數展示了權限控制
/// 只有擁有 ShopOwnerCap 的人（店主）才能呼叫
public fun collect_profits(
    _: &ShopOwnerCap,  // 這個參數驗證呼叫者的權限
    shop: &mut DonutShop,
    ctx: &mut TxContext
) {
    let amount = shop.balance.value();
    let profits = shop.balance.split(amount).into_coin(ctx);
    transfer::public_transfer(profits, ctx.sender())
}
```

**關鍵設計模式**：

-   **能力物件（Capability Object）**：`ShopOwnerCap` 作為權限憑證
-   **權限驗證**：函數參數要求特定能力物件
-   **操作分離**：公開操作與受限操作清楚分離

### 共享物件的特點

甜甜圈商店範例展示了共享物件的核心特點：

-   **多方存取**：任何人都可以購買甜甜圈
-   **權限管理**：透過能力物件（Capability Object）控制特定操作
-   **狀態共享**：商店狀態對所有人可見和可修改
-   **共識需求**：所有修改都需要通過網路共識

---

## 3. Immutable Objects（不可變物件）

### 核心概念

Sui 中的物件有不同的所有權類型，主要分為兩類：不可變物件和可變物件。不可變物件無法被變更、轉移或刪除。這些物件沒有擁有者，對所有人都是自由可存取的。

### 創建不可變物件

要使物件變為不可變，請從 transfer 模組呼叫 `public_freeze_object` 函數：

```move
public native fun public_freeze_object<T: key>(obj: T);
```

此呼叫永久使物件變為不可變。此操作無法逆轉。只有在確定永遠不需要修改時才凍結物件。

#### 基本範例 - ColorObject

```move
// 創建並立即凍結的 API
public fun create_immutable(red: u8, green: u8, blue: u8, ctx: &mut TxContext) {
    let color_object = new(red, green, blue, ctx);
    transfer::public_freeze_object(color_object)
}
```

這個函數創建一個新的 ColorObject 並在它有擁有者之前立即使其變為不可變。

#### 從已有物件創建不可變物件

```move
{
    ts.next_tx(alice);
    // 創建一個新的 ColorObject
    let c = new(255, 0, 255, ts.ctx());
    // 使其變為不可變
    transfer::public_freeze_object(c);
};
```

在這個測試中，您必須首先擁有一個 ColorObject。凍結後，物件變為不可變且無擁有者。

````

### 不可變物件的特性

#### 1. 永久只讀

物件變為不可變後，在 Sui Move 呼叫中使用此物件的規則會改變：您只能將不可變物件作為只讀、不可變引用 `&T` 傳遞給 Sui Move 入口函數。

所有網路參與者都可以存取不可變物件。

```move
// 複製一個物件的值到另一個物件的函數
public fun copy_into(from: &ColorObject, into: &mut ColorObject);
````

在這個函數中，任何人都可以將不可變物件作為第一個參數 `from` 傳遞，但不能作為第二個參數。因為您永遠無法變更不可變物件，所以即使多個交易同時使用相同的不可變物件，也不會有資料競爭。因此，不可變物件的存在不會對共識產生任何要求。

#### 2. 測試不可變物件

您可以在單元測試中使用 `test_scenario::take_immutable<T>` 從全域存儲中取得不可變物件包裝器，使用 `test_scenario::return_immutable` 將包裝器返回到全域存儲。

```move
let sender1 = @0x1;
let scenario_val = test_scenario::begin(sender1);
let scenario = &mut scenario_val;
{
    let ctx = test_scenario::ctx(scenario);
    color_object::create_immutable(255, 0, 255, ctx);
};
scenario.next_tx(sender1);
{
    // has_most_recent_for_sender 對不可變物件返回 false
    assert!(!test_scenario::has_most_recent_for_sender<ColorObject>(scenario))
};

// 任何發送者都可以工作
let sender2 = @0x2;
scenario.next_tx(sender2);
{
    let object = test_scenario::take_immutable<ColorObject>(scenario);
    let (red, green, blue) = color_object::get_color(object);
    assert!(red == 255 && green == 0 && blue == 255)
    test_scenario::return_immutable(object);
};
```

#### 3. CLI 互動範例

創建並凍結物件的完整流程：

```bash
# 1. 查看您擁有的物件
$ export ADDR=`sui client active-address`
$ sui client objects $ADDR

# 2. 發布合約
$ sui client publish $ROOT/examples/move/color_object

# 3. 創建新的 ColorObject
$ sui client call --package $PACKAGE --module "color_object" --function "create" --args 0 255 0

# 4. 將物件設為不可變
$ sui client call --package $PACKAGE --module "color_object" --function "freeze_object" --args \"$OBJECT\"

# 5. 驗證物件狀態
$ sui client object $OBJECT
```

回應包含：

```
Owner: Immutable  // 此欄位顯示物件的不可變狀態
```

如果嘗試變更不可變物件：

```bash
$ sui client call --package $PACKAGE --module "color_object" --function "update" --args \"$OBJECT\" 0 0 0
```

回應會指出您無法將不可變物件傳遞給可變參數。

### 不可變物件的特點

ColorObject 範例展示了不可變物件的核心特點：

-   **永久只讀**：物件無法被修改或移動
-   **無擁有者**：物件不屬於任何特定地址
-   **全域可存取**：所有網路參與者都可以讀取
-   **無共識需求**：讀取操作不需要網路共識
-   **測試友好**：提供專門的測試工具

---

## 5. Wrapped Objects（包裝物件）

### 核心概念

您可以嵌套結構來組織 Move 中的資料結構。包裝物件允許一個物件包含另一個物件，創建物件之間的層次關係。當物件被包裝時，它不再獨立存在於鏈上，只能通過包裝它的物件來存取。

### 基本概念 - 包裝物件（Wrapped Objects）

您可以嵌套結構來組織 Move 中的資料結構。這個範例展示了基本的包裝模式：

```move
public struct Foo has key {
    id: UID,
    bar: Bar,
}

public struct Bar has store {
    value: u64,
}
```

要將結構類型嵌入 Sui 物件結構（具有 `key` 能力），該結構類型必須具有 `store` 能力。

在前面的範例中，`Bar` 是一個普通結構，但它不是 Sui 物件，因為它沒有 `key` 能力。

以下程式碼將 `Bar` 轉換為物件，您仍然可以將其包裝在 `Foo` 中：

```move
public struct Bar has key, store {
    id: UID,
    value: u64,
}
```

現在 `Bar` 也是 Sui 物件類型。如果您將 `Bar` 類型的 Sui 物件放入 `Foo` 類型的 Sui 物件中，物件類型 `Foo` 就包裝了物件類型 `Bar`。物件類型 `Foo` 是包裝器或包裝物件。

````

### 包裝的重要特性

當物件被包裝時會發生一些有趣的後果：

1. **獨立性消失**：當物件被包裝時，該物件不再在鏈上獨立存在
2. **無法直接查詢**：您無法再透過其 ID 查詢該物件
3. **成為資料部分**：物件成為包裝它的物件的資料部分
4. **存取限制**：您無法再在 Sui Move 呼叫中以任何方式將被包裝的物件作為參數傳遞

最重要的是，唯一的存取點是透過包裝物件。

**重要原則**：
- 不可能創建循環包裝行為（A 包裝 B，B 包裝 C，C 也包裝 A）
- 包裝和解包裝過程中，物件的 ID 保持不變
- 解包裝後，物件重新成為獨立物件，可以直接在鏈上存取

### 三種包裝方式

有幾種方式可以將 Sui 物件包裝到另一個 Sui 物件中，它們的使用場景通常不同。

#### 1. 直接包裝（Direct Wrapping）

當 Sui 物件類型包含另一個 Sui 物件類型作為直接欄位時，就會發生直接包裝。通過直接包裝實現的最重要特性是：

- **強制提取限制**：沒有銷毀包裝器就無法提取被包裝的物件
- **強封裝保證**：提供強封裝保證
- **物件鎖定模式**：非常適合實現物件鎖定模式
- **明確合約呼叫**：需要明確的合約呼叫來修改存取

##### 信任交換範例

以下是使用直接包裝實現信任交換的範例。假設有一個 NFT 風格的 Object 類型，具有稀有度和風格屬性：

```move
public struct Object has key, store {
    id: UID,
    scarcity: u8,  // 稀有度
    style: u8,     // 風格
}

public fun new(scarcity: u8, style: u8, ctx: &mut TxContext): Object {
    Object { id: object::new(ctx), scarcity, style }
}
````

定義包裝器物件類型：

```move
public struct SwapRequest has key {
    id: UID,
    owner: address,
    object: Object,
    fee: Balance<SUI>,
}
```

請求交換的介面：

```move
public fun request_swap(
    object: Object,
    fee: Coin<SUI>,
    service: address,
    ctx: &mut TxContext,
) {
    assert!(coin::value(&fee) >= MIN_FEE, EFeeTooLow);

    let request = SwapRequest {
        id: object::new(ctx),
        owner: ctx.sender(),
        object,
        fee: coin::into_balance(fee),
    };

    transfer::transfer(request, service)
}
```

服務提供者執行交換：

```move
public fun execute_swap(s1: SwapRequest, s2: SwapRequest): Balance<SUI> {
    let SwapRequest {id: id1, owner: owner1, object: o1, fee: fee1} = s1;
    let SwapRequest {id: id2, owner: owner2, object: o2, fee: fee2} = s2;

    // 檢查交換合法性
    assert!(o1.scarcity == o2.scarcity, EBadSwap);
    assert!(o1.style != o2.style, EBadSwap);

    // 執行交換
    transfer::transfer(o1, owner2);
    transfer::transfer(o2, owner1);

    // 清理包裝器
    id1.delete();
    id2.delete();

    // 合併並返回費用
    fee1.join(fee2);
    fee1
}
```

#### 2. 透過 Option 包裝

當 Sui 物件類型 Bar 直接包裝到 Foo 中時，靈活性不足：Foo 物件必須包含 Bar 物件，要取出 Bar 物件必須銷毀 Foo 物件。為了更大的靈活性，包裝類型可能不總是包含被包裝的物件，被包裝的物件可能隨時被不同的物件替換。

##### 簡單戰士範例

設計一個簡單的遊戲角色：帶有劍和盾的戰士。戰士可能有劍和盾，也可能沒有。戰士應該能夠隨時添加劍和盾，並替換當前的裝備：

```move
public struct SimpleWarrior has key {
    id: UID,
    sword: Option<Sword>,
    shield: Option<Shield>,
}

public struct Sword has key, store {
    id: UID,
    strength: u8,
}

public struct Shield has key, store {
    id: UID,
    armor: u8,
}
```

創建新戰士時，將劍和盾設為 none：

```move
public fun create_warrior(ctx: &mut TxContext) {
    let warrior = SimpleWarrior {
        id: object::new(ctx),
        sword: option::none(),
        shield: option::none(),
    };
    transfer::transfer(warrior, ctx.sender())
}
```

定義裝備新劍的函數：

```move
public fun equip_sword(warrior: &mut SimpleWarrior, sword: Sword, ctx: &mut TxContext) {
    if (warrior.sword.is_some()) {
        let old_sword = warrior.sword.extract();
        transfer::transfer(old_sword, ctx.sender());
    };
    warrior.sword.fill(sword);
}
```

**重要注意事項**：因為 Sword 是沒有 drop 能力的 Sui 物件類型，如果戰士已經裝備了劍，就不能丟棄該劍。如果在沒有先檢查和取出現有劍的情況下呼叫 `option::fill`，會發生錯誤。

#### 3. 透過 Vector 包裝

透過 vector 包裝物件的概念與透過 Option 包裝非常相似：物件可以包含 0、1 或多個相同類型的被包裝物件。透過 vector 包裝類似於：

```move
public struct Pet has key, store {
    id: UID,
    cuteness: u64,
}

public struct Farm has key {
    id: UID,
    pets: vector<Pet>,
}
```

前面的範例將 Pet 的 vector 包裝在 Farm 中，只能透過 Farm 物件存取。

### 實際使用案例總結

物件擁有者模型的典型用例包括：

#### 遊戲系統

-   **角色 + 裝備**：英雄擁有武器、防具、道具
-   **農場 + 寵物**：農場管理多個寵物
-   **戰士 + 裝備**：可替換的劍和盾

#### 金融系統

-   **錢包 + 代幣**：錢包包含多種代幣餘額
-   **保險庫 + 資產**：安全存儲多種資產
-   **投資組合 + 股票**：管理多項投資

#### 交易系統

-   **交換請求 + 物品**：安全的 P2P 交換
-   **託管 + 資產**：第三方託管服務
-   **拍賣 + 競標品**：拍賣品的暫存

---

## 交易執行路徑與所有權的關係

不同的所有權模型會影響交易的執行路徑：

### 單一擁有者物件

-   **快速路徑**：可以並行執行，因為沒有競爭條件
-   **無需共識**：驗證器可以獨立處理

### 共享物件

-   **共識路徑**：需要驗證器達成共識
-   **序列化執行**：可能需要排隊處理
-   **較高延遲**：由於需要協調

### 不可變物件

-   **最快路徎**：無衝突，可以並行讀取
-   **無限制存取**：任何人可以隨時讀取

### 物件擁有者

-   **混合路徑**：取決於父物件的所有權類型
-   **遞歸檢查**：需要驗證整個所有權鏈

## 總結

### 所有權模型對比

| 特性         | Address-Owned  | Immutable    | Party        | Shared       | Wrapped      |
| ------------ | -------------- | ------------ | ------------ | ------------ | ------------ |
| **控制權**   | 單一帳戶獨佔   | 只讀存取     | 黨派控制     | 任何人可存取 | 透過父物件   |
| **修改權限** | 僅擁有者       | 無人         | 黨派成員     | 任何人       | 透過父物件   |
| **執行速度** | 快（並行）     | 最快（並行） | 中等（共識） | 慢（共識）   | 取決於父物件 |
| **適用場景** | Coin、個人資產 | 配置、常數   | 多人協作     | 市場、商店   | 遊戲系統     |
| **安全性**   | 最高           | 最安全       | 中等         | 需要設計     | 繼承父物件   |

### 選擇指南

1. **個人資產、Coin** → Address-Owned Objects
2. **配置、參考資料、常數** → Immutable Objects
3. **多人協作、組織管理** → Party Objects
4. **市場、交易所、共享資源** → Shared Objects
5. **遊戲角色+道具、複雜關係** → Wrapped Objects
