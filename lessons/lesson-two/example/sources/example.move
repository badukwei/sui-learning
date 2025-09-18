module example::example;

use std::ascii::{Self as string, String};
use sui::object::{Self, UID};
use sui::tx_context::TxContext;

/// 無能力 - Hot Potato 模式
/// 用途：強制性回調、閃電貸、借用保證
/// 特性：必須被手動處理，不能存儲、複製或丟棄
/// 應用場景：
/// - 閃電貸票據，確保資金必須歸還
/// - 購買票據，確保必須完成付款
/// - 借用憑證，確保物品必須歸還
/// - 工作流程步驟，確保必須處理下一步
public struct Example {
    name: String,
    description: String,
}

/// Key 能力 - 獨立頂層物件
/// 用途：系統配置、全域狀態、獨特 NFT
/// 特性：只能獨立存在，無法被包含在其他物件中
/// 應用場景：
/// - 系統全域配置物件
/// - 管理員權限物件
/// - 獨一無二的藝術品 NFT
/// - 遊戲世界的單例物件（如世界設定）
public struct Example2 has key {
    id: UID,
    name: String,
    description: String,
}

/// Key + Store 能力 - 標準 NFT
/// 用途：遊戲道具、藝術品、收藏品
/// 特性：既可獨立存在，也可被收藏或包含
/// 應用場景：
/// - 標準 NFT（藝術品、音樂、影片）
/// - 遊戲裝備和道具
/// - 數位收藏品
/// - 可交易的遊戲角色
/// - 房地產 NFT
public struct Example3 has key, store {
    id: UID,
    name: String,
    description: String,
}

/// Copy + Store 能力 - 可複製資料
/// 用途：元資料、配置參數、統計資料
/// 特性：最常見的資料結構組合，可存儲和複製
/// 應用場景：
/// - NFT 元資料（藝術家資訊、屬性）
/// - 遊戲角色屬性（血量、攻擊力）
/// - 系統配置參數
/// - 統計資料和記錄
/// - 產品規格和描述
public struct Example4 has copy, store {
    name: String,
    description: String,
}

/// Copy 能力 - 純值類型
/// 用途：簡單計算結果、臨時資料
/// 特性：可複製，隱含 drop，但無法存儲
/// 應用場景：
/// - 計算結果和中間值
/// - 函數間傳遞的簡單資料
/// - 臨時狀態資訊
/// - 演算法處理的資料結構
/// 注意：無法持久化存儲，只能在函數間傳遞
public struct Example5 has copy {
    name: String,
    description: String,
}

/// Drop 能力 - 臨時資料
/// 用途：計算中間結果、臨時狀態
/// 特性：可自動銷毀，無法存儲或複製
/// 應用場景：
/// - 計算過程中的臨時資料
/// - 函數內部的工作變數
/// - 一次性使用的狀態
/// - 需要明確控制生命週期的資料
/// 注意：無法複製，必須轉移所有權
public struct Example6 has drop {
    name: String,
    description: String,
}

/// 更多能力組合範例

/// Store + Drop 能力 - 可銷毀資料
/// 用途：會話資料、臨時記錄
/// 特性：可存儲但不可複製，可自動銷毀
/// 應用場景：
/// - 用戶會話資料
/// - 臨時交易記錄
/// - 一次性使用的憑證
/// - 需要存儲但不能複製的敏感資料
public struct Example7 has drop, store {
    session_id: String,
    timestamp: u64,
}

/// Copy + Drop 能力 - 純值類型
/// 用途：計算結果、簡單狀態
/// 特性：類似基本型別，可複製和銷毀
/// 應用場景：
/// - 數學計算結果
/// - 簡單的狀態標記
/// - 配置選項
/// - 輕量級的資料傳遞
/// 注意：這是最接近傳統程式語言中普通資料類型的組合
public struct Example8 has copy, drop {
    value: u64,
    is_active: bool,
}

/// Key + Store + Drop 能力 - 完整標準物件
/// 用途：功能完整的物件
/// 特性：可獨立、可包含、可銷毀
/// 應用場景：
/// - 靈活的遊戲物件
/// - 可選擇銷毀的 NFT
/// - 臨時但可交易的資產
/// - 具有完整生命週期管理的物件
/// 注意：UID 沒有 drop 能力，所以這個組合實際上困難
/// 這裡作為概念展示，實際使用時需要特殊處理 UID
public struct Example9 has key, store {
    id: UID,
    name: String,
    can_be_destroyed: bool,
}

/// Store + Copy + Drop 能力 - 最靈活資料
/// 用途：通用資料結構
/// 特性：支援所有資料操作
/// 應用場景：
/// - 通用的設定檔案
/// - 靈活的元資料
/// - 多用途的資料容器
/// - 可在任何地方使用的輔助資料
/// 這是最靈活的非物件資料結構
public struct Example10 has copy, drop, store {
    title: String,
    content: String,
    tags: vector<String>,
    created_at: u64,
}
