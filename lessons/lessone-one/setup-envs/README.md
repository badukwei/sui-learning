# Lesson 1: 從零開始設置 Sui 開發環境

本課程將從最基礎開始，一步步指導完全新手設置 Sui 開發環境。即使您從未使用過命令行，也能輕鬆跟上。

## 💡 開始之前

### 什麼是命令行/終端機？

-   **macOS**: 應用程式 → 工具程式 → 終端機 (Terminal)
-   **Windows**: 開始選單搜尋 "PowerShell" 或 "命令提示字元"
-   **Linux**: Ctrl+Alt+T 或搜尋 "Terminal"

### 什麼是 sudo？

`sudo` 是 Linux 和 macOS 的管理員權限命令，相當於 Windows 的「以系統管理員身分執行」。

## 🖥️ 系統需求檢查

首先確認您的系統版本：

### macOS 用戶

```bash
# 檢查 macOS 版本
sw_vers
```

需要：**macOS Monterey (12.0) 或更新版本**

### Windows 用戶

```powershell
# 檢查 Windows 版本
winver
```

需要：**Windows 10 或 Windows 11**

### Linux 用戶

```bash
# 檢查 Ubuntu 版本
lsb_release -a
```

需要：**Ubuntu 22.04 或更新版本**

## 🛠️ 基礎工具安裝

### macOS 用戶：安裝 Homebrew

Homebrew 是 macOS 的套件管理器，讓安裝軟體變得簡單。

1. **打開終端機**
2. **安裝 Homebrew**：
    ```bash
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    ```
3. **按照螢幕提示完成安裝**（可能需要輸入密碼）
4. **驗證安裝**：
    ```bash
    brew --version
    ```

### Windows 用戶：安裝 Chocolatey

Chocolatey 是 Windows 的套件管理器。

1. **以管理員身分打開 PowerShell**（右鍵選單選擇「以系統管理員身分執行」）
2. **安裝 Chocolatey**：
    ```powershell
    Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    ```
3. **驗證安裝**：
    ```powershell
    choco --version
    ```

### Linux 用戶：更新套件管理器

```bash
# 更新套件清單
sudo apt-get update

# 安裝基本工具
sudo apt-get install -y curl wget git
```

## 🚀 Sui 安裝方法

### 方法 1: 一鍵安裝 (最簡單，推薦新手)

現在您已經安裝了套件管理器，可以輕鬆安裝 Sui：

#### macOS 用戶

```bash
# 安裝 Sui
brew install sui

# 驗證安裝
sui --version
```

#### Windows 用戶

```powershell
# 安裝 Sui（需要管理員權限的 PowerShell）
choco install sui

# 驗證安裝
sui --version
```

#### Linux 用戶

對於 Linux，我們需要先安裝 Rust，然後安裝 Sui：

```bash
# 1. 安裝 Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# 2. 重新載入環境
source ~/.bashrc

# 3. 安裝必要的系統依賴
sudo apt-get install -y build-essential pkg-config libssl-dev

# 4. 安裝 Sui
cargo install --locked --git https://github.com/MystenLabs/sui.git --branch testnet sui

# 5. 驗證安裝
sui --version
```

#### 🎉 安裝成功！

如果看到版本號（例如 `sui 1.x.x-xxxxxxx`），恭喜您成功安裝了 Sui！

### 方法 2: 手動安裝 (進階用戶)

如果方法 1 無法使用，可以手動下載：

#### 步驟 1: 下載 Sui

1. 前往 [Sui GitHub 頁面](https://github.com/MystenLabs/sui)
2. 點擊右側的 **Releases**
3. 點擊最新版本 (**Latest**)
4. 下載對應您系統的檔案：
    - macOS: `sui-macos-x86_64.tgz` 或 `sui-macos-arm64.tgz`
    - Linux: `sui-ubuntu-x86_64.tgz`
    - Windows: `sui-windows-x86_64.tgz`

#### 步驟 2: 安裝檔案

##### macOS/Linux 用戶

```bash
# 1. 解壓縮到家目錄
cd ~
tar -xzf ~/Downloads/sui-*.tgz

# 2. 移動到適當位置
mkdir -p ~/bin
mv sui-*/bin/* ~/bin/

# 3. 加入 PATH（選擇您使用的 shell）
# 如果使用 zsh (macOS 預設)
echo 'export PATH=$PATH:~/bin' >> ~/.zshrc
source ~/.zshrc

# 如果使用 bash (Linux 預設)
echo 'export PATH=$PATH:~/bin' >> ~/.bashrc
source ~/.bashrc

# 4. (僅 macOS) 移除安全限制
xattr -d com.apple.quarantine ~/bin/*
```

##### Windows 用戶

1. 解壓縮檔案到 `C:\sui`
2. 按下 `Win + R`，輸入 `sysdm.cpl`
3. 點擊「環境變數」
4. 在「系統變數」中找到 `Path`，點擊「編輯」
5. 點擊「新增」，輸入 `C:\sui`
6. 點擊「確定」關閉所有視窗
7. 重新開啟 PowerShell

## ✅ 驗證安裝

不論使用哪種安裝方法，都需要驗證安裝是否成功：

### 基本驗證

```bash
# 檢查版本（應該顯示版本號）
sui --version

# 查看可用命令
sui --help
```

### 預期輸出

成功的話會看到：

```
sui 1.x.x-xxxxxxx
```

### 初始化 Sui 配置

```bash
# 初始化 Sui 客戶端配置
sui client

# 如果是第一次運行，會看到設置選項
# 選擇 'y' 建立新的配置
```

### 安裝 VS Code (程式碼編輯器)

VS Code 是最受歡迎的免費程式碼編輯器：

#### 下載安裝 VS Code

1. 前往 [VS Code 官網](https://code.visualstudio.com/)
2. 點擊「Download」下載對應您系統的版本
3. 安裝完成後打開 VS Code

#### 安裝 Move 語言擴展

Move 是 Sui 使用的程式語言，需要安裝擴展來支援：

1. **在 VS Code 中**按下：

    - Windows/Linux: `Ctrl + Shift + X`
    - macOS: `Cmd + Shift + X`

2. **搜尋並安裝**：

    ```
    Mysten.move
    ```

3. **或使用快速安裝**：
    - 按 `Ctrl+P` (Windows/Linux) 或 `Cmd+P` (macOS)
    - 輸入：`ext install mysten.move`
    - 按 Enter

#### Move 擴展功能

安裝後您將獲得：

-   ✅ Move 語法高亮
-   ✅ 自動完成
-   ✅ 錯誤檢查
-   ✅ 調試工具
-   ✅ 格式化工具

### 其他編輯器選項

如果您偏好其他編輯器：

-   **Emacs**: [Move 模式](https://github.com/amnn/move-mode)
-   **Vim**: [Move 語法](https://github.com/damirka/move.vim)
-   **Zed**: [Move 支援](https://github.com/zed-industries/zed)

## 📋 Sui 工具包說明

安裝 Sui 後，您將獲得以下工具：

| 工具名稱             | 用途說明                     | 新手是否常用 |
| -------------------- | ---------------------------- | ------------ |
| `sui`                | 主要 CLI，管理錢包、部署合約 | ✅ 常用      |
| `sui-test-validator` | 本地測試網路                 | ✅ 常用      |
| `sui-node`           | 運行完整節點                 | ❌ 進階      |
| `sui-faucet`         | 本地測試代幣水龍頭           | ✅ 常用      |
| `move-analyzer`      | Move 語言服務器              | ✅ 自動      |
| `sui-tool`           | 其他實用工具                 | ❌ 偶爾      |

## 🎯 下一步學習路徑

完成環境設置後，建議按以下順序學習：

### 立即可做的事情

1. **測試 Sui CLI**

    ```bash
    # 查看所有可用命令
    sui --help

    # 檢查網路連接
    sui client envs
    ```

2. **建立您的第一個錢包**

    ```bash
    # 建立新錢包
    sui client new-address ed25519

    # 查看錢包地址
    sui client addresses
    ```

### 接下來的課程

-   **Lesson 2**: 連接到 Sui 測試網路
-   **Lesson 3**: 獲取測試代幣
-   **Lesson 4**: 第一個 Move 智能合約
-   **Lesson 5**: 部署和測試合約

## ❓ 常見問題與解決方案

### 🚨 無法找到 sui 命令

**症狀**: 輸入 `sui --version` 顯示 "command not found"

**解決方案**:

```bash
# 1. 檢查 PATH 設置
echo $PATH

# 2. 重新載入環境變數
# macOS/Linux
source ~/.zshrc
# 或
source ~/.bashrc

# 3. 重新開啟終端機
```

### 🍎 macOS 安全警告

**症狀**: "無法打開，因為無法驗證開發者"

**解決方案**:

```bash
# 移除隔離屬性
xattr -d com.apple.quarantine ~/bin/sui*
# 或如果檔案在不同位置
xattr -d com.apple.quarantine /path/to/sui/files/*
```

### 🐧 Linux 權限問題

**症狀**: "Permission denied"

**解決方案**:

```bash
# 確保檔案有執行權限
chmod +x ~/bin/sui*

# 檢查檔案權限
ls -la ~/bin/sui
```

### 🪟 Windows PATH 設定

**症狀**: PowerShell 找不到 sui 命令

**解決方案**:

1. 按 `Win + R`，輸入 `sysdm.cpl`
2. 「進階」→「環境變數」
3. 編輯「系統變數」中的 `Path`
4. 新增 Sui 安裝路徑
5. **重新啟動 PowerShell**

### 🔧 Homebrew 安裝失敗

**解決方案**:

```bash
# 更新 Homebrew
brew update

# 如果還是失敗，重新安裝
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

## 📚 學習資源

### 官方文檔

-   [Sui 開發者文檔](https://docs.sui.io/)
-   [Move 語言教學](https://docs.sui.io/concepts/sui-move-concepts)
-   [Sui CLI 完整參考](https://docs.sui.io/references/cli)

### 社群資源

-   [Sui GitHub](https://github.com/MystenLabs/sui)
-   [Sui Discord](https://discord.gg/sui)
-   [Sui 論壇](https://forums.sui.io/)

### 開發工具

-   [Sui Explorer](https://explorer.sui.io/) - 區塊鏈瀏覽器
-   [Sui Wallet](https://chrome.google.com/webstore/detail/sui-wallet/opcgpfmipidbgpenhmajoajpbobppdil) - 瀏覽器錢包

## 🏁 檢查清單

在進入下一課之前，請確認：

-   [ ] ✅ 已成功安裝套件管理器 (Homebrew/Chocolatey)
-   [ ] ✅ `sui --version` 顯示版本號
-   [ ] ✅ `sui --help` 顯示幫助資訊
-   [ ] ✅ 已安裝 VS Code 和 Move 擴展
-   [ ] ✅ 已初始化 Sui 客戶端配置
-   [ ] ✅ 能夠執行基本 Sui CLI 命令

**恭喜！** 🎉 您已經成功設置了 Sui 開發環境，準備開始 Sui 開發之旅！

---

**參考資料**: 本指南基於 [Sui 官方安裝文檔](https://docs.sui.io/guides/developer/getting-started/sui-install) 編寫，適合完全新手使用。
