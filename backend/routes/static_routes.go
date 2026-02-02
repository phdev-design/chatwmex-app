package routes

import (
	"log"
	"net/http"
	"os"
	"path/filepath"

	"github.com/gorilla/mux"
)

// SetupStaticRoutes 設置靜態文件服務
func SetupStaticRoutes(router *mux.Router) {
	// 獲取上傳目錄路徑
	uploadPath := os.Getenv("UPLOAD_PATH")
	if uploadPath == "" {
		uploadPath = "./uploads"
	}

	// 確保上傳目錄存在
	if err := os.MkdirAll(uploadPath, 0755); err != nil {
		log.Printf("Warning: Failed to create upload directory: %v", err)
		// 不要panic，而是警告並繼續
	}

	// 獲取絕對路徑
	absUploadPath, err := filepath.Abs(uploadPath)
	if err != nil {
		log.Printf("Warning: Could not get absolute path for upload directory: %v", err)
		absUploadPath = uploadPath
	}

	log.Printf("Setting up static file server for uploads at: %s", absUploadPath)

	// 🔥 修复：设置静态文件服务，支持音频文件
	fileServer := http.FileServer(http.Dir(absUploadPath))
	
	// 🔥 关键修复：正确设置静态文件路由
	router.PathPrefix("/uploads/").Handler(
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// 设置适当的Content-Type头
			if filepath.Ext(r.URL.Path) == ".m4a" || filepath.Ext(r.URL.Path) == ".aac" {
				w.Header().Set("Content-Type", "audio/mp4")
			} else if filepath.Ext(r.URL.Path) == ".mp3" {
				w.Header().Set("Content-Type", "audio/mpeg")
			}
			
			// 允许跨域访问
			w.Header().Set("Access-Control-Allow-Origin", "*")
			w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Origin, X-Requested-With, Content-Type, Accept")
			
			// 处理OPTIONS请求
			if r.Method == "OPTIONS" {
				w.WriteHeader(http.StatusOK)
				return
			}
			
			// 记录访问日志
			log.Printf("Serving static file: %s", r.URL.Path)
			
			// 使用原始文件服务器
			http.StripPrefix("/uploads/", fileServer).ServeHTTP(w, r)
		}),
	)
	
	log.Println("✓ Static file routes configured successfully")
}