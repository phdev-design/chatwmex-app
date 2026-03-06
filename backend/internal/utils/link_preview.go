package utils

import (
	"errors"
	"html"
	"io"
	"net/http"
	neturl "net/url"
	"regexp"
	"strings"
	"time"

	"chatwmex_backend/internal/domain"
)

var firstURLPattern = regexp.MustCompile(`https?://[^\s<>"']+`)

// 抓取整個標籤，之後再萃取屬性，避免屬性順序顛倒導致抓不到
var metaTagPattern = regexp.MustCompile(`(?is)<meta\s+([^>]+)>`)
var linkTagPattern = regexp.MustCompile(`(?is)<link\s+([^>]+)>`)
var titlePattern = regexp.MustCompile(`(?is)<title[^>]*>(.*?)</title>`)

// getAttr 是一個小工具，用來從 HTML 標籤內文抓取特定屬性的值 (例如 property="..." 或 content="...")
func getAttr(tag string, attr string) string {
	re := regexp.MustCompile(`(?i)\b` + attr + `\s*=\s*(?:["']([^"']*)["']|([^"' >]+))`)
	match := re.FindStringSubmatch(tag)
	if len(match) > 1 {
		if match[1] != "" {
			return match[1]
		}
		if len(match) > 2 {
			return match[2]
		}
	}
	return ""
}

func FetchLinkPreview(input string) (*domain.LinkPreview, error) {
	targetURL := ExtractFirstURL(input)
	if targetURL == "" {
		return nil, errors.New("no url found")
	}

	client := &http.Client{Timeout: 5 * time.Second}
	req, err := http.NewRequest(http.MethodGet, targetURL, nil)
	if err != nil {
		return nil, err
	}

	// 【重要修正】加上常見的 User-Agent，避免被目標網站當成爬蟲阻擋
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	req.Header.Set("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	// 限制讀取前 1MB，防止遇到無限迴圈或極大檔案耗盡記憶體
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 1024*1024))
	if err != nil {
		return nil, err
	}
	htmlBody := string(raw)

	preview := &domain.LinkPreview{
		URL: targetURL,
	}

	// 1. 抓取 <title>
	if match := titlePattern.FindStringSubmatch(htmlBody); len(match) > 1 {
		preview.Title = strings.TrimSpace(html.UnescapeString(match[1]))
	}

	// 2. 抓取所有 <meta> 標籤，並彈性解析
	metaTags := metaTagPattern.FindAllString(htmlBody, -1)
	for _, tag := range metaTags {
		property := getAttr(tag, "property")
		name := getAttr(tag, "name")
		content := getAttr(tag, "content")

		if content == "" {
			continue
		}
		content = strings.TrimSpace(html.UnescapeString(content))

		// 解析標題
		if property == "og:title" || name == "twitter:title" {
			preview.Title = content
		}
		// 解析描述 (og:description 優先度高於一般 description)
		if property == "og:description" || name == "twitter:description" || name == "description" {
			if preview.Description == "" || strings.HasPrefix(property, "og:") {
				preview.Description = content
			}
		}
		// 解析圖片
		if property == "og:image" || name == "twitter:image" {
			if preview.ImageURL == "" || strings.HasPrefix(property, "og:") {
				preview.ImageURL = content
			}
		}
	}

	// 3. 【重要修正】如果沒抓到 og:image，嘗試抓取網站的 icon (favicon) 作為替代
	if preview.ImageURL == "" {
		linkTags := linkTagPattern.FindAllString(htmlBody, -1)
		var iconURL string
		for _, tag := range linkTags {
			rel := strings.ToLower(getAttr(tag, "rel"))
			href := getAttr(tag, "href")
			if (strings.Contains(rel, "icon") || strings.Contains(rel, "apple-touch-icon")) && href != "" {
				iconURL = href
				// apple-touch-icon 通常解析度比較高，優先使用
				if strings.Contains(rel, "apple-touch-icon") {
					break
				}
			}
		}
		if iconURL != "" {
			preview.ImageURL = iconURL
		}
	}

	// 4. 將可能拿到的相對路徑轉換為絕對路徑
	preview.ImageURL = resolveImageURL(targetURL, preview.ImageURL)

	if preview.Title == "" && preview.Description == "" && preview.ImageURL == "" {
		return nil, errors.New("no preview metadata found")
	}

	return preview, nil
}

func ExtractFirstURL(input string) string {
	return firstURLPattern.FindString(input)
}

// 【重要修正】確保相對路徑 (例如 "/images/icon.png") 被正確轉為完整的絕對路徑
func resolveImageURL(pageURL string, imageURL string) string {
	if imageURL == "" {
		return ""
	}
	imageURL = strings.TrimSpace(imageURL)

	base, err := neturl.Parse(pageURL)
	if err != nil {
		return imageURL
	}

	imgURL, err := neturl.Parse(imageURL)
	if err != nil {
		return imageURL
	}

	// ResolveReference 會自動處理各種相對/絕對路徑的拼接
	return base.ResolveReference(imgURL).String()
}
