# 動手實作：Sui 基礎命令行操作

完成環境設置後，現在讓我們動手實作！本練習將帶您完成 Sui 開發的基本操作，包括創建錢包、連接測試網路、獲取測試代幣等。

## 🎯 學習目標

通過本練習，您將學會：

-   創建和管理 Sui 錢包
-   連接到 Sui 測試網路
-   使用水龍頭獲取測試代幣
-   查看賬戶餘額和交易記錄

## 📋 前置要求

確保您已經：

-   ✅ 安裝了 Sui CLI
-   ✅ 可以執行 `sui --version` 命令
-   ✅ 有基本的命令行操作能力

## 🚀 步驟一：創建您的第一個錢包

### 1.1 檢查 Sui 客戶端狀態

首先，讓我們檢查 Sui 客戶端的當前狀態：

```bash
# 檢查當前網路環境
sui client envs
```

如果這是您第一次使用，會看到預設的網路環境設定。Sui CLI 會自動創建必要的配置文件，無需額外的初始化步驟。

### 1.2 自動創建的錢包

在步驟 2.1 的初次配置過程中，系統會自動創建您的第一個錢包地址。配置完成後，您會看到類似的輸出：

```
Generated new key pair for address with scheme "ed25519" [0xb9c83a8b40d3263c9ba40d551514fbac1f8c12e98a4005a0dac072d3549c2442]
Secret Recovery Phrase : [cap wheat many line human lazy few solid bored proud speed grocery]
```

⚠️ **重要提醒**：

-   請立即將 **Secret Recovery Phrase** (助記詞) 安全保存
-   這是恢復錢包的唯一方式
-   絕對不要與他人分享
-   建議寫在紙上並存放在安全的地方

### 1.3 創建額外的錢包地址 (可選)

如果您需要額外的錢包地址：

```bash
# 創建新的錢包地址 (使用 ed25519 簽名算法)
sui client new-address ed25519
```

### 1.4 匯入現有錢包 (可選)

如果您已經有 Sui 錢包的助記詞，可以匯入到 CLI 中：

#### 方法 1: 使用助記詞匯入

```bash
# 使用 12 個單詞的助記詞匯入錢包
sui keytool import "your twelve word mnemonic phrase here from previous wallet" ed25519
```

**範例**：

```bash
sui keytool import "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about" ed25519
```

#### 方法 2: 使用私鑰匯入

```bash
# 如果您有私鑰 (hex 格式)
sui keytool import-private-key "your-private-key-in-hex" ed25519
```

#### 匯入成功後

您會看到類似的輸出：

```
Key imported successfully!
Address: 0x1234567890abcdef...
```

匯入的錢包會自動加入到您的錢包列表中。

⚠️ **安全提醒**：

-   只在您信任的電腦上匯入錢包
-   確保助記詞或私鑰的正確性
-   匯入前請備份現有的錢包配置

### 1.5 查看您的錢包地址

```bash
# 查看所有錢包地址
sui client addresses
```

```bash
# 查看當前使用的地址
sui client active-address
```

### 1.6 切換錢包地址

如果您有多個錢包地址，可以在它們之間切換：

```bash
# 切換到特定的錢包地址
sui client switch --address 0x1234567890abcdef...
```

或者使用地址別名：

```bash
# 切換到有別名的地址
sui client switch --address your-alias-name
```

## 🌐 步驟二：配置網路環境

### 2.1 初次連接配置

如果這是您第一次使用 Sui CLI，當您執行任何 `sui client` 命令時，系統會提示您配置網路連接：

```bash
# 第一次執行客戶端命令會觸發配置
sui client envs
```

如果還沒有配置文件，會看到提示：

```
Config file ["/Users/your-username/.sui/sui_config/client.yaml"] doesn't exist, do you want to connect to a Sui full node server [y/N]?
```

**輸入 `y` 並按 Enter**

接下來會詢問 RPC 服務器 URL：

```
Sui full node server URL (Defaults to Sui Testnet if not specified) :
```

**直接按 Enter 使用預設的 Testnet**，或輸入特定網路的 URL：

-   **Testnet**: `https://fullnode.testnet.sui.io:443`
-   **Devnet**: `https://fullnode.devnet.sui.io:443`
-   **Mainnet**: `https://fullnode.mainnet.sui.io:443`

然後選擇金鑰方案：

```
Select key scheme to generate key pair (0 for ed25519, 1 for secp256k1, 2 for secp256r1):
```

**輸入 `0` 選擇 ed25519 (推薦)**

### 2.2 查看已配置的環境

```bash
# 查看所有可用的網路環境
sui client envs
```

您會看到類似輸出：

```
testnet => https://fullnode.testnet.sui.io:443 (active)
```

### 2.3 新增其他網路環境 (可選)

如果您想要新增其他網路：

```bash
# 新增 Devnet 環境
sui client new-env --alias devnet --rpc https://fullnode.devnet.sui.io:443

# 新增 Mainnet 環境 (僅查看用)
sui client new-env --alias mainnet --rpc https://fullnode.mainnet.sui.io:443
```

### 2.4 切換網路環境

```bash
# 切換到不同的網路
sui client switch --env testnet
# 或
sui client switch --env devnet
```

### 2.5 驗證當前網路

```bash
# 確認當前使用的環境
sui client envs
```

確保您想要使用的網路旁邊有 `(active)` 標記。

## 💰 步驟三：獲取測試代幣

### 3.1 使用命令行水龍頭

```bash
# 向測試網路水龍頭請求 SUI 代幣
sui client faucet
```

如果成功，您會看到類似的輸出：

```
Request successful. It can take up to 1 minute to get the coin. Run sui client gas to check your gas coins.
```

⏰ **等待時間**：通常需要 30 秒到 1 分鐘完成轉帳

### 3.2 使用 Discord 水龍頭 (推薦)

根據官方文檔，您也可以通過 Discord 請求測試代幣：

1. **加入 Sui Discord**: [https://discord.gg/sui](https://discord.gg/sui)

2. **找到對應的水龍頭頻道**：

    - Testnet: `#testnet-faucet`
    - Devnet: `#devnet-faucet`

3. **在頻道中輸入命令**：

    ```
    !faucet <your-wallet-address>
    ```

4. **例如**：
    ```
    !faucet 0x1234567890abcdef...
    ```

### 3.3 使用網頁水龍頭 (備用)

如果上述方法無法使用，可以嘗試網頁版：

1. **Testnet 水龍頭**: [https://faucet.testnet.sui.io/](https://faucet.testnet.sui.io/)
2. **Devnet 水龍頭**: [https://faucet.devnet.sui.io/](https://faucet.devnet.sui.io/)
3. 輸入您的錢包地址
4. 點擊 "Request SUI" 按鈕

📝 **注意**：

-   測試網路的代幣沒有實際價值
-   每個地址通常有請求限制 (例如每 24 小時一次)
-   Mainnet 沒有水龍頭服務

## 🔍 步驟四：檢查賬戶餘額

### 4.1 查看 Gas 代幣

```bash
# 查看所有可用的 gas 代幣
sui client gas
```

成功獲取代幣後，您會看到：

```
╭────────────────────────────────────────────────────────────────────┬─────────────────╮
│ gasCoinId                                                          │ gasBalance      │
├────────────────────────────────────────────────────────────────────┼─────────────────┤
│ 0x1234567890abcdef...                                              │ 1000000000      │
╰────────────────────────────────────────────────────────────────────┴─────────────────╯
```

📝 **說明**：餘額以 MIST 為單位顯示（1 SUI = 1,000,000,000 MIST）

### 4.2 查看總餘額

```bash
# 查看賬戶總餘額
sui client balance
```

### 4.3 查看所有擁有的物件

```bash
# 查看賬戶擁有的所有物件
sui client objects
```

### 4.4 查看賬戶詳細資訊

```bash
# 查看完整的賬戶摘要
sui client objects --json
```

## 📊 步驟五：交易記錄查詢

### 5.1 查看最近的交易

```bash
# 查看最近 5 筆交易
sui client transactions --limit 5
```

### 5.2 查看特定交易詳情

```bash
# 查看特定交易的詳細資訊（替換為實際的交易ID）
sui client transaction --digest [TRANSACTION_DIGEST]
```

## 🎉 完成驗證

### 驗證清單

請確認以下項目都已完成：

-   [ ] ✅ 成功創建了錢包地址（或匯入了現有錢包）
-   [ ] ✅ 安全保存了助記詞
-   [ ] ✅ 能夠查看和切換錢包地址
-   [ ] ✅ 成功切換到 testnet 環境
-   [ ] ✅ 成功獲取了測試代幣
-   [ ] ✅ 能夠查看賬戶餘額
-   [ ] ✅ 能夠查看交易記錄

### 成功標準

如果您看到以下內容，表示操作成功：

1. **錢包地址**: 以 `0x` 開頭的 64 字符地址
2. **網路環境**: testnet 旁有 `*` 標記
3. **代幣餘額**: 顯示 1000000000 MIST (約 1 SUI)

## 🔧 常見問題排除

### Q1: 水龍頭請求失敗

```bash
# 錯誤：Too Many Requests
```

**解決方案**: 等待 1 小時後重試，或使用網頁版水龍頭

### Q2: 找不到錢包地址

```bash
# 查看所有地址
sui client addresses

# 切換到特定地址
sui client switch --address [ADDRESS]
```

### Q5: 錢包匯入失敗

**症狀**: "Invalid mnemonic phrase" 或 "Failed to import key"

**解決方案**:

```bash
# 檢查助記詞格式 (確保是 12 個單詞，用空格分隔)
sui keytool import "word1 word2 word3 ... word12" ed25519

# 檢查是否有額外的空格或特殊字符
# 確保助記詞用雙引號包圍
```

### Q6: 匯入的錢包餘額為 0

**症狀**: 匯入錢包後餘額顯示為 0

**解決方案**:

```bash
# 確認您在正確的網路
sui client envs

# 檢查該地址在區塊鏈瀏覽器上的餘額
# Testnet: https://explorer.sui.io/?network=testnet
# Mainnet: https://explorer.sui.io/?network=mainnet
```

### Q7: 助記詞來自其他錢包

**症狀**: 從 Sui Wallet 或其他錢包匯出的助記詞無法匯入

**解決方案**:

-   確保助記詞來自 Sui 錢包（不是 Ethereum 等其他鏈）
-   嘗試不同的金鑰方案：

```bash
# 嘗試 ed25519
sui keytool import "your mnemonic" ed25519

# 如果失敗，嘗試 secp256k1
sui keytool import "your mnemonic" secp256k1
```

### Q3: 餘額顯示為 0

```bash
# 檢查是否在正確的網路
sui client envs

# 等待更長時間，然後重新檢查
sui client gas
```

### Q4: 無法連接到測試網路

```bash
# 檢查網路連接
ping google.com

# 重新切換環境
sui client switch --env testnet
```

## 📚 實用命令參考

### 錢包管理

```bash
# 基本錢包操作
sui client addresses                    # 查看所有地址
sui client active-address              # 查看當前地址
sui client switch --address <addr>     # 切換地址
sui client new-address ed25519         # 創建新地址

# 錢包匯入
sui keytool import "mnemonic phrase" ed25519    # 匯入助記詞
sui keytool import-private-key "hex-key" ed25519 # 匯入私鑰

# 錢包資訊
sui keytool list                        # 查看所有金鑰
sui keytool show <address>              # 查看特定地址資訊
```

### 網路環境

```bash
sui client envs                  # 查看所有環境
sui client switch --env testnet  # 切換環境
```

### 代幣和物件

```bash
sui client balance               # 查看餘額
sui client gas                   # 查看 gas 代幣
sui client objects               # 查看所有物件
```

### 交易相關

```bash
sui client transactions          # 查看交易歷史
sui client faucet                # 請求測試代幣
```

## 🎯 下一步

完成這個練習後，您已經掌握了 Sui 的基本操作！接下來可以：

1. **Lesson 2**: 探索 Sui Move 程式語言
2. **Lesson 3**: 創建您的第一個智能合約
3. **Lesson 4**: 部署和互動合約

## 💡 小技巧

-   使用 `sui --help` 查看所有可用命令
-   在任何命令後加 `--help` 查看詳細說明
-   使用 `--json` 參數獲取機器可讀的輸出
-   定期備份您的配置文件 (`~/.sui/sui_config/client.yaml`)

---

**恭喜！** 🎊 您已經完成了 Sui 的基礎實作練習！現在您擁有了一個功能完整的 Sui 開發環境，可以開始探索更高級的功能了。
