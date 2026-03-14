# Bugfix Requirements Document

## Introduction

當用戶頻繁換鑰（例如重新安裝 app、切換裝置）超過 20 次後，系統會淘汰最舊的歷史私鑰，導致使用那些私鑰加密的歷史訊息永久無法解密。此 bug 影響頻繁換鑰的用戶，造成歷史訊息的永久性資料遺失。

本修正將歷史私鑰上限從 20 把提升到 50 把，並在接近上限時提供警告，以延長歷史訊息的可解密時間範圍。

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN 用戶累積的歷史私鑰數量超過 20 把 THEN 系統淘汰最舊的私鑰，導致使用該私鑰加密的歷史訊息永久無法解密

1.2 WHEN 用戶頻繁換鑰（例如每次重新安裝都強制生成新鑰） THEN 系統在第 21 次換鑰時開始淘汰歷史私鑰，造成資料遺失風險

1.3 WHEN 歷史私鑰接近或達到上限 THEN 系統沒有任何警告或提示，用戶無法得知即將發生的資料遺失風險

### Expected Behavior (Correct)

2.1 WHEN 用戶累積的歷史私鑰數量超過 50 把 THEN 系統才開始淘汰最舊的私鑰

2.2 WHEN 用戶頻繁換鑰 THEN 系統應該提供更長的歷史覆蓋範圍（50 把私鑰），減少資料遺失風險

2.3 WHEN 歷史私鑰數量超過 40 把 THEN 系統 SHALL 印出警告訊息提醒開發者或記錄日誌

### Unchanged Behavior (Regression Prevention)

3.1 WHEN 歷史私鑰數量在上限範圍內 THEN 系統 SHALL CONTINUE TO 正常儲存和管理所有歷史私鑰

3.2 WHEN 歷史私鑰數量超過上限（50 把） THEN 系統 SHALL CONTINUE TO 淘汰最舊的私鑰（這是設計限制）

3.3 WHEN 使用歷史私鑰解密舊訊息 THEN 系統 SHALL CONTINUE TO 正確使用對應的歷史私鑰進行解密

3.4 WHEN 生成新的密鑰對 THEN 系統 SHALL CONTINUE TO 將舊私鑰加入歷史私鑰列表
