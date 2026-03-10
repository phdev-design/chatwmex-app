import UserNotifications

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    // ⚠️ 與 .env 中的 API_URL 一致
    private let apiBaseURL = "https://api-chat2mex.phdev.uk"
    
    // ⚠️ 替換成你在 Xcode 中設定的 App Group ID
    private let appGroupID = "group.com.phdev.chat2mex"

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        guard let bestAttemptContent = bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        // 1. 取出 OneSignal data payload 裡的 message_id
        let data = request.content.userInfo
        var payload: [String: Any] = [:]
        if let custom = data["custom"] as? [String: Any],
           let additionalData = custom["a"] as? [String: Any] {
            payload = additionalData
        } else {
            // Fallback：直接讀外層
            payload = data as? [String: Any] ?? [:]
        }

        let messageId = payload["message_id"] as? String ?? ""

        // 2. 從 App Group 讀取 JWT Token (方案 B)
        guard let userDefaults = UserDefaults(suiteName: appGroupID),
              let jwtToken = userDefaults.string(forKey: "jwt_token"),
              !jwtToken.isEmpty,
              !messageId.isEmpty else {
            // 沒有 messageId 或是沒有 Token (未登入狀態)，直接顯示通知
            contentHandler(bestAttemptContent)
            return
        }

        // 3. 非同步呼叫 Delivered API，設 4 秒超時（Extension 最多 30 秒）
        reportDelivered(messageId: messageId, jwtToken: jwtToken) {
            contentHandler(bestAttemptContent)
        }
    }

    // MARK: - Private

    private func reportDelivered(messageId: String, jwtToken: String, completion: @escaping () -> Void) {
        guard let url = URL(string: "\(apiBaseURL)/api/v1/messages/delivered") else {
            completion()
            return
        }

        var request = URLRequest(url: url, timeoutInterval: 4.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(jwtToken)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = ["message_ids": [messageId]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                // Timeout 或網路錯誤：不影響顯示
                NSLog("[NotifExt] Delivered ACK error: \(error.localizedDescription)")
            } else if let httpResponse = response as? HTTPURLResponse {
                NSLog("[NotifExt] Delivered ACK status: \(httpResponse.statusCode)")
            }
            completion()
        }
        task.resume()
    }
}