package utils

import "strings"

// ExtractFilePathFromURL 從 URL 中提取文件路徑
func ExtractFilePathFromURL(url string) string {
	// 支持多種 URL 格式：
	// http://143.198.17.2:2025/uploads/audio/2025/09/24/filename.m4a
	// https://api-chatwmex.phdev.uk/uploads/audio/2025/09/24/filename.m4a
	// https://api-chatwmex.phdev.uk/uploads/avatars/2025/01/15/xxx.jpg
	// 我們需要提取：audio/2025/09/24/filename.m4a 或 avatars/2025/01/15/xxx.jpg

	uploadsIndex := strings.Index(url, "/uploads/")
	if uploadsIndex == -1 {
		return ""
	}

	// 跳過 "/uploads/" 部分
	filePath := url[uploadsIndex+9:] // 9 = len("/uploads/")

	return filePath
}
