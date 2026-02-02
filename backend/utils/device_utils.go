package utils

import (
	"net"
	"net/http"
	"regexp"
	"strings"
	"time"

	"chatwme/backend/models"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

// DeviceInfo 設備信息結構
type DeviceInfo struct {
	IPAddress   string
	UserAgent   string
	DeviceType  string
	OS          string
	Browser     string
	DeviceModel string
	ScreenSize  string
	Language    string
	Timezone    string
	IsMobile    bool
	IsTablet    bool
	IsDesktop   bool
}

// ExtractDeviceInfo 從 HTTP 請求中提取設備信息
func ExtractDeviceInfo(r *http.Request) DeviceInfo {
	// 獲取真實 IP 地址
	ip := getRealIP(r)

	// 獲取 User-Agent
	userAgent := r.Header.Get("User-Agent")

	// 解析設備信息
	deviceInfo := DeviceInfo{
		IPAddress:   ip,
		UserAgent:   userAgent,
		DeviceType:  detectDeviceType(userAgent),
		OS:          detectOS(userAgent),
		Browser:     detectBrowser(userAgent),
		DeviceModel: detectDeviceModel(userAgent),
		ScreenSize:  r.Header.Get("X-Screen-Size"), // 前端需要傳送此標頭
		Language:    r.Header.Get("Accept-Language"),
		Timezone:    r.Header.Get("X-Timezone"), // 前端需要傳送此標頭
		IsMobile:    isMobile(userAgent),
		IsTablet:    isTablet(userAgent),
		IsDesktop:   isDesktop(userAgent),
	}

	return deviceInfo
}

// getRealIP 獲取真實的客戶端 IP 地址
func getRealIP(r *http.Request) string {
	// 檢查 X-Forwarded-For 標頭（代理服務器）
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		ips := strings.Split(xff, ",")
		if len(ips) > 0 {
			return strings.TrimSpace(ips[0])
		}
	}

	// 檢查 X-Real-IP 標頭
	if xri := r.Header.Get("X-Real-IP"); xri != "" {
		return xri
	}

	// 檢查 X-Forwarded-Proto 標頭
	if xfp := r.Header.Get("X-Forwarded-Proto"); xfp != "" {
		// 這通常表示請求通過代理
	}

	// 使用 RemoteAddr
	ip, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}

	return ip
}

// detectDeviceType 檢測設備類型
func detectDeviceType(userAgent string) string {
	userAgent = strings.ToLower(userAgent)

	if isMobile(userAgent) {
		return "mobile"
	} else if isTablet(userAgent) {
		return "tablet"
	} else if isDesktop(userAgent) {
		return "desktop"
	}

	return "unknown"
}

// detectOS 檢測操作系統
func detectOS(userAgent string) string {
	userAgent = strings.ToLower(userAgent)

	// iOS
	if strings.Contains(userAgent, "iphone") || strings.Contains(userAgent, "ipad") {
		if strings.Contains(userAgent, "iphone") {
			return "iOS"
		} else if strings.Contains(userAgent, "ipad") {
			return "iPadOS"
		}
		return "iOS"
	}

	// Android
	if strings.Contains(userAgent, "android") {
		return "Android"
	}

	// Windows
	if strings.Contains(userAgent, "windows") {
		return "Windows"
	}

	// macOS
	if strings.Contains(userAgent, "mac os x") || strings.Contains(userAgent, "macintosh") {
		return "macOS"
	}

	// Linux
	if strings.Contains(userAgent, "linux") {
		return "Linux"
	}

	return "Unknown"
}

// detectBrowser 檢測瀏覽器
func detectBrowser(userAgent string) string {
	userAgent = strings.ToLower(userAgent)

	// Chrome
	if strings.Contains(userAgent, "chrome") && !strings.Contains(userAgent, "edg") {
		return "Chrome"
	}

	// Safari
	if strings.Contains(userAgent, "safari") && !strings.Contains(userAgent, "chrome") {
		return "Safari"
	}

	// Firefox
	if strings.Contains(userAgent, "firefox") {
		return "Firefox"
	}

	// Edge
	if strings.Contains(userAgent, "edg") {
		return "Edge"
	}

	// Opera
	if strings.Contains(userAgent, "opera") {
		return "Opera"
	}

	return "Unknown"
}

// detectDeviceModel 檢測設備型號
func detectDeviceModel(userAgent string) string {
	userAgent = strings.ToLower(userAgent)

	// iPhone 型號檢測
	iphoneRegex := regexp.MustCompile(`iphone os (\d+)_(\d+)`)
	if matches := iphoneRegex.FindStringSubmatch(userAgent); len(matches) > 0 {
		// 根據 iOS 版本推測 iPhone 型號
		version := matches[1] + "." + matches[2]
		return "iPhone (iOS " + version + ")"
	}

	// Android 設備檢測
	androidRegex := regexp.MustCompile(`android (\d+\.\d+)`)
	if matches := androidRegex.FindStringSubmatch(userAgent); len(matches) > 0 {
		version := matches[1]
		return "Android " + version
	}

	// 嘗試從 User-Agent 中提取設備名稱
	if strings.Contains(userAgent, "samsung") {
		return "Samsung Device"
	}

	if strings.Contains(userAgent, "huawei") {
		return "Huawei Device"
	}

	if strings.Contains(userAgent, "xiaomi") {
		return "Xiaomi Device"
	}

	return "Unknown Device"
}

// isMobile 檢測是否為手機
func isMobile(userAgent string) bool {
	userAgent = strings.ToLower(userAgent)

	// 檢查移動設備關鍵字
	mobileKeywords := []string{
		"mobile", "android", "iphone", "ipod", "blackberry", "windows phone",
		"opera mini", "iemobile", "mobile safari",
	}

	for _, keyword := range mobileKeywords {
		if strings.Contains(userAgent, keyword) {
			return true
		}
	}

	return false
}

// isTablet 檢測是否為平板
func isTablet(userAgent string) bool {
	userAgent = strings.ToLower(userAgent)

	// 檢查平板設備關鍵字
	tabletKeywords := []string{
		"ipad", "tablet", "kindle", "playbook", "nexus 7", "nexus 10",
	}

	for _, keyword := range tabletKeywords {
		if strings.Contains(userAgent, keyword) {
			return true
		}
	}

	return false
}

// isDesktop 檢測是否為桌面設備
func isDesktop(userAgent string) bool {
	userAgent = strings.ToLower(userAgent)

	// 檢查桌面設備關鍵字
	desktopKeywords := []string{
		"windows nt", "macintosh", "linux", "x11", "ubuntu",
	}

	for _, keyword := range desktopKeywords {
		if strings.Contains(userAgent, keyword) {
			return true
		}
	}

	return false
}

// CreateDeviceInfoModel 創建設備信息模型
func CreateDeviceInfoModel(userID primitive.ObjectID, deviceInfo DeviceInfo) models.DeviceInfo {
	now := time.Now()

	return models.DeviceInfo{
		ID:          primitive.NewObjectID(),
		UserID:      userID,
		IPAddress:   deviceInfo.IPAddress,
		UserAgent:   deviceInfo.UserAgent,
		DeviceType:  deviceInfo.DeviceType,
		OS:          deviceInfo.OS,
		Browser:     deviceInfo.Browser,
		DeviceModel: deviceInfo.DeviceModel,
		ScreenSize:  deviceInfo.ScreenSize,
		Language:    deviceInfo.Language,
		Timezone:    deviceInfo.Timezone,
		IsMobile:    deviceInfo.IsMobile,
		IsTablet:    deviceInfo.IsTablet,
		IsDesktop:   deviceInfo.IsDesktop,
		LoginTime:   now,
		LastActive:  now,
		CreatedAt:   now,
		UpdatedAt:   now,
	}
}

// CreateLoginSession 創建登入會話
func CreateLoginSession(userID primitive.ObjectID, deviceInfo DeviceInfo, sessionToken string) models.LoginSession {
	now := time.Now()

	return models.LoginSession{
		ID:           primitive.NewObjectID(),
		UserID:       userID,
		DeviceInfo:   CreateDeviceInfoModel(userID, deviceInfo),
		SessionToken: sessionToken,
		IsActive:     true,
		LoginTime:    now,
		LastActive:   now,
		CreatedAt:    now,
		UpdatedAt:    now,
	}
}
