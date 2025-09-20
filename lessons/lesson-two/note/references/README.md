# Move References 參考型別

## 概述

Move 有兩種參考型別：

-   **不可變參考 `&`**：唯讀，無法修改底層值或其欄位
-   **可變參考 `&mut`**：允許透過參考修改底層值

Move 的型別系統強制執行所有權規範，防止參考錯誤。

## 參考運算子 (Reference Operators)

| 語法        | 型別                                                  | 描述                                       |
| ----------- | ----------------------------------------------------- | ------------------------------------------ |
| `&e`        | `&T` where `e: T` and `T` is a non-reference type     | 創建指向 `e` 的不可變參考                  |
| `&mut e`    | `&mut T` where `e: T` and `T` is a non-reference type | 創建指向 `e` 的可變參考                    |
| `&e.f`      | `&T` where `e.f: T`                                   | 創建指向結構體 `e` 的欄位 `f` 的不可變參考 |
| `&mut e.f`  | `&mut T` where `e.f: T`                               | 創建指向結構體 `e` 的欄位 `f` 的可變參考   |
| `freeze(e)` | `&T` where `e: &mut T`                                | 將可變參考 `e` 轉換為不可變參考            |

### 欄位參考示例

```move
let s = S { f: 10 };
let f_ref1: &u64 = &s.f; // 直接創建欄位參考
let s_ref: &S = &s;
let f_ref2: &u64 = &s_ref.f // 從結構體參考擴展到欄位參考
```

### 多層欄位參考

```move
public struct A { b: B }
public struct B { c : u64 }

fun f(a: &A): &u64 {
    &a.b.c  // 多層欄位參考，只要結構體在同一模組中即可
}
```

### ⚠️ 限制：不允許參考的參考

```move
let x = 7;
let y: &u64 = &x;
let z: &&u64 = &y; // 錯誤！無法編譯
```

## 透過參考讀取和寫入

### 讀取操作 `*`

-   可變和不可變參考都可以讀取，產生參考值的副本
-   使用 `*` 語法：`*e` 其中 `e` 是 `&T` 或 `&mut T`
-   底層型別必須有 `copy` 能力

### 寫入操作 `*=`

-   只有可變參考可以寫入
-   使用 `*x = v` 語法，丟棄 `x` 中先前的值並用 `v` 更新
-   底層型別必須有 `drop` 能力

| 語法       | 型別                                | 描述                     |
| ---------- | ----------------------------------- | ------------------------ |
| `*e`       | `T` where `e` is `&T` or `&mut T`   | 讀取 `e` 指向的值        |
| `*e1 = e2` | `()` where `e1: &mut T` and `e2: T` | 用 `e2` 更新 `e1` 中的值 |

### 💡 為什麼需要 copy 和 drop 能力？

```move
// 錯誤示例：複製資產
fun copy_coin_via_ref_bad(c: Coin) {
    let c_ref = &c;
    let counterfeit: Coin = *c_ref; // 不允許！會複製資產
    pay(c);
    pay(counterfeit);
}

// 錯誤示例：銷毀資源
fun destroy_coin_via_ref_bad(mut ten_coins: Coin, c: Coin) {
    let ref = &mut ten_coins;
    *ref = c; // 錯誤！會銷毀 10 個硬幣！
}
```

## Freeze 推斷 (Freeze Inference)

可變參考可以在需要不可變參考的上下文中使用：

```move
let mut x = 7;
let y: &u64 = &mut x;  // 編譯器自動插入 freeze 指令
```

### 更多 Freeze 推斷示例

```move
fun takes_immut_returns_immut(x: &u64): &u64 { x }
fun takes_mut_returns_immut(x: &mut u64): &u64 { x }

fun expression_examples() {
    let mut x = 0;
    let mut y = 0;
    takes_immut_returns_immut(&x);        // 無推斷
    takes_immut_returns_immut(&mut x);    // 推斷 freeze(&mut x)
    takes_mut_returns_immut(&mut x);      // 無推斷

    assert!(&x == &mut y, 42);            // 推斷 freeze(&mut y)
}

fun assignment_examples() {
    let x = 0;
    let y = 0;
    let imm_ref: &u64 = &x;

    imm_ref = &x;      // 無推斷
    imm_ref = &mut y;  // 推斷 freeze(&mut y)
}
```

## 子型別關係 (Subtyping)

由於 freeze 推斷，Move 型別檢查器將 `&mut T` 視為 `&T` 的子型別：

-   任何需要 `&T` 值的地方，都可以使用 `&mut T` 值
-   但反之不成立：需要 `&mut T` 的地方不能使用 `&T`

### 錯誤示例

```move
module a::example {
    fun read_and_assign(store: &mut u64, new_value: &u64) {
        *store = *new_value
    }

    fun subtype_examples() {
        let mut x: &u64 = &0;
        let mut y: &mut u64 = &mut 1;

        x = &mut 1;  // 有效：&mut u64 是 &u64 的子型別
        y = &2;      // 錯誤！&u64 不是 &mut u64 的子型別

        read_and_assign(y, x);  // 有效
        read_and_assign(x, y);  // 錯誤！x 是 &u64，需要 &mut u64
    }
}
```

## 所有權 (Ownership)

Move 的參考所有權規則比 Rust 更寬鬆：

```move
fun reference_copies(s: &mut S) {
    let s_copy1 = s;            // 可以
    let s_extension = &mut s.f; // 也可以
    let s_copy2 = s;            // 仍然可以
    // ...
}
```

**特點：**

-   可變和不可變參考都可以隨時複製和擴展
-   即使存在相同參考的其他副本或擴展也沒關係
-   Move 在複製方面更寬鬆，但在寫入前確保可變參考的唯一所有權方面同樣嚴格

## 重要限制：參考無法儲存

**參考和元組是唯一無法作為結構體欄位值儲存的型別**

這意味著：

-   參考無法存在於儲存或對象中
-   程式執行期間創建的所有參考在 Move 程式終止時都會被銷毀
-   參考完全是短暫的 (ephemeral)
-   這也適用於所有沒有 `store` 能力的型別

### 為什麼有這個限制？

1. **與 Rust 的差異**：Rust 允許參考儲存在結構體中，但 Move 不允許
2. **技術原因**：Move 有一個相當複雜的靜態參考安全追蹤系統
3. **未來發展**：要支援儲存參考，需要擴展 Move 的參考安全系統

## 總結

### 核心概念

-   兩種參考型別：`&T` (不可變) 和 `&mut T` (可變)
-   自動 freeze 推斷：`&mut T` 可以用於需要 `&T` 的地方
-   子型別關係：`&mut T` 是 `&T` 的子型別

### 安全保證

-   讀取需要 `copy` 能力
-   寫入需要 `drop` 能力
-   防止資產複製和資源銷毀

### 限制

-   不能有參考的參考
-   參考無法儲存在結構體中
-   參考是短暫的，程式結束時必須銷毀

### 實用建議

-   使用參考進行高效的資料訪問而不轉移所有權
-   利用 freeze 推斷簡化程式碼
-   注意型別系統的安全約束，特別是在處理資源時
