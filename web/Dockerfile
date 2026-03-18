# ==========================================
# Stage 1: Build
# ==========================================
FROM node:22-alpine AS builder

WORKDIR /app

# 複製 package 檔案並安裝依賴
COPY package.json package-lock.json ./
RUN npm ci

# 複製原始碼並建置
COPY . .
RUN npm run build

# ==========================================
# Stage 2: Serve with Nginx
# ==========================================
FROM nginx:alpine AS runner

# 移除預設設定，並加入自訂 Nginx 設定
RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d/default.conf

# 從 build stage 複製打包後的靜態檔案
COPY --from=builder /app/dist /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]