# Visibilities 

## 核心問題

**Visibilities 為什麼有些有寫有些沒寫？**

舊版 Move struct 沒有 visibility 修飾詞，型別總是 public，但操作受限於 module。
新版 Move（2024 edition）struct 必須標註 visibility，否則編譯錯誤。
visibility 幫助你更好地控制 struct 的可見性與安全性。
