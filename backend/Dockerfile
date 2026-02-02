# 使用官方的 Go 映像作為基礎映像
FROM golang:1.23.4-alpine AS builder

# 設定工作目錄
WORKDIR /app

# 安裝必要的依賴包（用於編譯）
RUN apk add --no-cache git

# 複製 go.mod 和 go.sum 文件
COPY go.mod go.sum ./

# 下載依賴包
RUN go mod download

# 複製所有源代碼
COPY . .

# 編譯應用程式
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main .

# 使用更小的映像作為運行環境
FROM alpine:latest

# 安裝 ca-certificates 和 wget（用於 HTTPS 連接和健康檢查）
RUN apk --no-cache add ca-certificates wget

# 設定工作目錄
WORKDIR /root/

# 從 builder 階段複製編譯好的二進制文件
COPY --from=builder /app/main .

# 創建 uploads 目錄並設定權限
RUN mkdir -p ./uploads/audio ./uploads/avatars && chmod -R 777 ./uploads

# 創建非 root 用戶
RUN adduser -D -s /bin/sh appuser && chown -R appuser:appuser /root
USER appuser

# 暴露端口
EXPOSE 8080

# 運行應用程式
CMD ["./main"]