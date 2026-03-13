# Bugfix Requirements Document

## Introduction

本文件描述 Flutter 專案中 `flutter analyze` 報告的多個問題的修復需求。這些問題分為四個階段：致命的編譯錯誤（Undefined name '_'）、BuildContext 非同步問題、被棄用的 API，以及無用的 import。修復這些問題將確保專案能夠正常編譯、避免潛在的崩潰風險，並符合 Flutter 最新的 API 規範。

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN `flutter analyze` 在 lib/core/backup/backup_manager.dart 第 103 行執行時 THEN 系統報告 "Undefined name '_'" 錯誤，因為正則表達式字串被錯誤地分割成多行

1.2 WHEN `flutter analyze` 在 lib/core/crypto/crypto_service.dart 第 225 行執行時 THEN 系統報告 "Undefined name '_'" 錯誤，因為 catch 區塊中的註解位置不正確

1.3 WHEN `flutter analyze` 在 lib/features/chat/providers/chat_room_provider.dart 第 617 行執行時 THEN 系統報告 "Undefined name '_'" 錯誤

1.4 WHEN `flutter analyze` 在 lib/features/chat/ui/contact_info_page.dart 第 378 行執行時 THEN 系統報告 "Undefined name '_'" 錯誤

1.5 WHEN 在 lib/core/notification/notification_service.dart、lib/features/auth/ui/qr_scanner_page.dart 中使用 BuildContext 跨越 async 間隙時 THEN 系統報告 "use_build_context_synchronously" 警告

1.6 WHEN 在 lib/features/chat/ui/contact_info_page.dart 中使用 BuildContext 跨越 async 間隙時 THEN 系統報告多個 "use_build_context_synchronously, guarded by an unrelated 'mounted' check" 警告，表示現有的 mounted 檢查可能用錯了對象

1.7 WHEN 多個檔案（lib/core/notification/notification_service.dart、lib/features/chat/ui/backup_conversations_page.dart 等）同時 import 'package:flutter/foundation.dart' 和 'package:flutter/material.dart' 時 THEN 系統報告 "unnecessary_import" 警告，因為 material.dart 已經包含了 foundation.dart 的所有元素

### Expected Behavior (Correct)

2.1 WHEN `flutter analyze` 在 lib/core/backup/backup_manager.dart 第 103 行執行時 THEN 系統應該能夠正確解析正則表達式字串，不報告任何錯誤

2.2 WHEN `flutter analyze` 在 lib/core/crypto/crypto_service.dart 第 225 行執行時 THEN 系統應該能夠正確識別 catch 區塊，不報告任何錯誤

2.3 WHEN `flutter analyze` 在 lib/features/chat/providers/chat_room_provider.dart 第 617 行執行時 THEN 系統應該能夠正確解析程式碼，不報告任何錯誤

2.4 WHEN `flutter analyze` 在 lib/features/chat/ui/contact_info_page.dart 第 378 行執行時 THEN 系統應該能夠正確解析程式碼，不報告任何錯誤

2.5 WHEN 在 lib/core/notification/notification_service.dart、lib/features/auth/ui/qr_scanner_page.dart 中使用 BuildContext 跨越 async 間隙時 THEN 系統應該在 await 呼叫後正確加入 `if (!context.mounted) return;` 檢查

2.6 WHEN 在 lib/features/chat/ui/contact_info_page.dart 中使用 BuildContext 跨越 async 間隙時 THEN 系統應該使用正確的 context.mounted 檢查（而非 mounted），確保檢查的是正確的 BuildContext 對象

2.7 WHEN 檔案已經 import 'package:flutter/material.dart' 時 THEN 系統應該移除多餘的 'package:flutter/foundation.dart' import

### Unchanged Behavior (Regression Prevention)

3.1 WHEN 其他檔案中的 catch 區塊使用 `catch (e)` 或 `catch (_)` 且格式正確時 THEN 系統應該繼續正常運作，不受修復影響

3.2 WHEN 其他檔案中正確使用 `if (!mounted) return;` 或 `if (!context.mounted) return;` 檢查時 THEN 系統應該繼續正常運作，不受修復影響

3.3 WHEN 檔案需要使用 foundation.dart 中特定的元素且 material.dart 未提供時 THEN 系統應該保留該 import（但根據分析結果，所有標記的檔案都不需要）

3.4 WHEN 應用程式的業務邏輯執行時 THEN 所有功能應該繼續正常運作，包括備份、加密、聊天室管理等功能

3.5 WHEN 使用者與 UI 互動時 THEN 所有使用者介面應該繼續正常顯示和響應，不受程式碼格式修復的影響
