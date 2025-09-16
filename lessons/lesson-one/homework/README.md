# 作業：使用網站 Mint NFT 並探索區塊鏈交易

完成了基礎的 Sui CLI 操作後，現在讓我們學習如何與 Sui 網絡上的 dApp 互動！本作業將教您如何使用網站 mint NFT，並學習如何查看和分析區塊鏈交易。

## 🎯 學習目標

通過本作業，您將學會：

-   使用瀏覽器錢包與 dApp 互動
-   在網站上 mint NFT
-   使用區塊鏈瀏覽器查看交易詳情
-   分析智能合約調用
-   轉移 NFT 到其他地址

## 📋 前置要求

確保您已經：

-   ✅ 完成了前面的 CLI 實作練習
-   ✅ 在 testnet 上有 SUI 代幣
-   ✅ 安裝了瀏覽器錢包 (如 Sui Wallet)

## 🌐 步驟一：設置瀏覽器錢包

### 1.1 安裝 Sui Wallet 擴展

1. **前往 Chrome Web Store**
2. **搜索並安裝 "Sui Wallet"**
3. **或直接訪問**：[Sui Wallet Chrome Extension](https://chrome.google.com/webstore/detail/sui-wallet/opcgpfmipidbgpenhmajoajpbobppdil)

### 1.2 匯入您的錢包

您有兩種方式將 CLI 錢包匯入瀏覽器：

#### 方法 1: 使用助記詞匯入

1. 打開 Sui Wallet 擴展
2. 選擇 "Import an Existing Wallet"
3. 輸入您之前保存的 12 個助記詞
4. 設置錢包密碼

#### 方法 2: 創建新錢包 (然後用 CLI 匯入)

1. 創建新的瀏覽器錢包
2. 複製助記詞
3. 使用 CLI 匯入：
    ```bash
    sui keytool import "your browser wallet mnemonic" ed25519
    ```

### 1.3 連接到 Testnet

1. 在錢包中點擊網絡選擇器
2. 選擇 **Testnet**
3. 確認您能看到之前獲得的 SUI 代幣餘額

## 🎨 步驟二：Mint NFT

### 2.1 訪問 Mint 網站

前往 NFT Minting 網站：[https://mint-nft-olive-nine.vercel.app/](https://mint-nft-olive-nine.vercel.app/)

### 2.2 Mint NFT

1. **填寫 NFT 資訊**：

    - NFT 名稱
    - 描述
    - 圖片 URL (如果需要)

2. **點擊 "Mint NFT" 按鈕**

### 2.3 記錄交易信息

Mint 成功後，請記錄以下信息：

-   **交易哈希 (Transaction Hash)**
-   **NFT Object ID**
-   **智能合約地址**

## 🔍 步驟三：使用 Suivision 分析交易

### 3.1 訪問 Suivision

前往 Sui 區塊鏈瀏覽器：[https://suivision.xyz/](https://suivision.xyz/)

### 3.2 切換到 Testnet

1. 在頁面右上角找到網絡選擇器
2. 選擇 **Testnet**

### 3.3 查詢您的交易

1. **使用交易哈希查詢**：

    - 在搜索框中輸入您的交易哈希
    - 按 Enter 搜索

2. **或使用錢包地址查詢**：
    - 輸入您的錢包地址
    - 查看最近的交易記錄

### 3.4 分析交易詳情

在交易詳情頁面，您可以看到：

#### 基本信息

-   **Transaction Hash**: 唯一的交易標識符
-   **Status**: 交易狀態 (Success/Failed)
-   **Block**: 交易所在的區塊
-   **Timestamp**: 交易時間

#### Gas 信息

-   **Gas Used**: 實際使用的 Gas
-   **Gas Price**: Gas 價格
-   **Gas Budget**: Gas 預算

#### 對象變更 (Object Changes)

-   **Created Objects**: 新創建的對象 (您的 NFT！)
-   **Mutated Objects**: 修改的對象
-   **Deleted Objects**: 刪除的對象

#### 函數調用 (Function Calls)

查看智能合約調用詳情：

-   **Package ID**: 智能合約套件 ID
-   **Module**: 調用的模組名稱
-   **Function**: 調用的函數名稱
-   **Arguments**: 傳遞的參數

### 3.5 找到您的 NFT

1. **在 Object Changes 中找到 Created Objects**
2. **點擊 NFT 的 Object ID**
3. **查看 NFT 詳情**：
    - 名稱和描述
    - 擁有者地址
    - 創建時間
    - 類型信息

## 🔄 步驟四：轉移 NFT (進階)

如果您有多個錢包地址，可以練習轉移 NFT：

### 4.1 準備接收地址

使用您的另一個錢包地址作為接收方：

```bash
# 查看所有地址
sui client addresses

# 創建新地址（如果需要）
sui client new-address ed25519
```

### 4.2 使用 CLI 轉移 NFT

```bash
# 轉移 NFT 到另一個地址
sui client transfer --to <RECIPIENT_ADDRESS> --object-id <OBJECT_ID>
```

### 4.3 使用瀏覽器錢包轉移

1. **在 Sui Wallet 中找到您的 NFT**
2. **點擊 NFT 查看詳情**
3. **點擊 "Send" 或"傳送"**
4. **輸入接收地址**
5. **確認交易**

### 4.4 驗證轉移

1. **在 Suivision 中查詢新的轉移交易**
2. **確認 NFT 的新擁有者**
3. **在接收錢包中確認 NFT**

## 📊 步驟五：深入分析

### 5.1 智能合約分析

在 Suivision 中深入了解：

1. **Package 詳情**：

    - 點擊智能合約的 Package ID
    - 查看模組和函數列表
    - 了解合約的功能

2. **Function Call 分析**：

    - 查看 mint 函數的參數
    - 了解 NFT 創建的過程
    - 分析 Gas 消耗

3. **Event Logs**：
    - 查看交易產生的事件
    - 了解 NFT 創建事件的結構

### 5.2 比較不同操作

對比分析不同類型的交易：

-   **Mint 交易**: 創建新對象
-   **Transfer 交易**: 改變對象所有權
-   **Gas 消耗差異**
-   **調用的函數差異**

## ✅ 作業檢查清單

完成以下所有項目：

-   [ ] ✅ 成功安裝並設置瀏覽器錢包
-   [ ] ✅ 連接錢包到 NFT minting 網站
-   [ ] ✅ 成功 mint 一個 NFT
-   [ ] ✅ 記錄交易哈希和 NFT Object ID
-   [ ] ✅ 在 Suivision 中找到並分析 mint 交易
-   [ ] ✅ 理解交易的基本組成部分
-   [ ] ✅ 查看 NFT 的詳細信息
-   [ ] ✅ 分析智能合約調用
-   [ ] ✅ (可選) 成功轉移 NFT 到另一個地址
-   [ ] ✅ (可選) 分析轉移交易的差異

## 📝 作業提交

請準備以下信息作為作業完成證明：

### 必需信息

1. **Mint 交易哈希**
2. **NFT Object ID**
3. **Suivision 交易頁面截圖**
4. **NFT 詳情頁面截圖**

### 可選信息 (加分項)

5. **轉移交易哈希** (如果完成了轉移)
6. **對智能合約調用的分析筆記**
7. **Gas 費用分析**

### 反思問題

請回答以下問題：

1. **Mint NFT 的過程中，哪個步驟最讓您印象深刻？為什麼？**

2. **在 Suivision 中，您發現了哪些有趣的交易詳情？**

3. **比較 CLI 操作和網頁操作，您更喜歡哪種方式？為什麼？**

4. **您認為智能合約調用的過程是如何工作的？**

## 🔧 常見問題排除

### Q1: 錢包無法連接到網站

**解決方案**：

-   確保錢包擴展已啟用
-   刷新網頁並重試
-   檢查錢包是否在 Testnet

### Q2: Mint 失敗

**解決方案**：

-   檢查 SUI 餘額是否足夠支付 Gas 費
-   確認在正確的網絡 (Testnet)
-   重試交易

### Q3: 在 Suivision 找不到交易

**解決方案**：

-   確認已切換到 Testnet
-   等待幾分鐘讓交易被確認
-   檢查交易哈希是否正確

### Q4: NFT 沒有顯示在錢包中

**解決方案**：

-   在錢包中切換到 NFT 或收藏品標籤
-   刷新錢包
-   使用 Object ID 在 Suivision 中確認 NFT 存在

## 🎯 下一步學習

完成這個作業後，您可以：

1. **探索其他 Sui dApps**
2. **學習 Move 智能合約開發**
3. **嘗試創建自己的 NFT 合約**
4. **深入學習 Sui 對象模型**

## 📚 相關資源

-   [Sui Wallet 官方文檔](https://docs.sui.io/build/wallet)
-   [Suivision 區塊鏈瀏覽器](https://suivision.xyz/)
-   [Sui NFT 標準](https://docs.sui.io/standards/nft)
-   [Sui dApp 開發指南](https://docs.sui.io/build/dapp)

---

**恭喜！** 🎉 通過這個作業，您已經學會了如何與 Sui 生態系統互動，從簡單的 CLI 操作到複雜的 dApp 互動，為成為 Sui 開發者奠定了堅實的基礎！
