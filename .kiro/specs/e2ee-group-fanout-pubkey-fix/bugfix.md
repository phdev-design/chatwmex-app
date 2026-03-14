# Bugfix Requirements Document

## Introduction

群組發訊時，系統對快取中沒有公鑰的成員靜默跳過加密，導致這些成員收到的 fanout payload 中缺少對應的密文，永久無法解密訊息。此 bug 影響新加入群組的成員或公鑰快取過期的成員，造成訊息無法送達。

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN 群組成員的公鑰不在本地快取中（例如新加入成員或快取過期）THEN 系統在 _encryptGroupMessage 中靜默跳過該成員，不為其生成密文

1.2 WHEN 被跳過的成員收到群組訊息 THEN 該成員的 fanout payload 中沒有對應的密文，導致永久無法解密訊息

1.3 WHEN 發生公鑰快取缺失 THEN 系統不會嘗試從後端補取公鑰，直接跳過加密

### Expected Behavior (Correct)

2.1 WHEN 準備發送群組訊息時 THEN 系統 SHALL 先批次預載所有群組成員的公鑰（透過 _prefetchMemberPublicKeys）

2.2 WHEN 批次預載後仍有成員公鑰缺失 THEN 系統 SHALL 單個補取該成員的公鑰（透過 _fetchPublicKeyFromServer）

2.3 WHEN 所有成員公鑰都已載入快取 THEN 系統 SHALL 為每個成員生成對應的密文並包含在 fanout payload 中

2.4 WHEN 成員收到群組訊息 THEN 該成員 SHALL 能在 fanout payload 中找到自己的密文並成功解密訊息

### Unchanged Behavior (Regression Prevention)

3.1 WHEN 所有群組成員的公鑰都已在快取中 THEN 系統 SHALL CONTINUE TO 正常加密並發送群組訊息

3.2 WHEN 發送一對一訊息 THEN 系統 SHALL CONTINUE TO 使用現有的加密流程

3.3 WHEN 群組訊息加密成功 THEN 系統 SHALL CONTINUE TO 使用相同的 fanout payload 格式和傳輸機制
