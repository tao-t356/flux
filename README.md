# 爱转角转发面板

爱转角转发面板基于 [go-gost/gost](https://github.com/go-gost/gost) 和 [go-gost/x](https://github.com/go-gost/x) 二次开发，提供面板端、节点端、Web 前端和移动端壳应用。

## 特性

- 支持按隧道账号级别管理流量转发数量，可用于用户/隧道配额控制
- 支持 TCP 和 UDP 协议转发
- 支持端口转发与隧道转发
- 支持指定用户、指定隧道的限速配置
- 支持单向或双向流量计费方式
- 支持节点状态、流量统计和基础诊断
- 默认启用更安全的节点通信配置

## 部署流程

### 方式一：Docker Compose

```bash
git clone https://github.com/tao-t356/flux.git
cd flux
```

创建 `.env`：

```bash
cat > .env <<EOF
JWT_SECRET=$(openssl rand -hex 32)
JWT_EXPIRE_DAYS=7
CORS_ALLOWED_ORIGINS=*
FRONTEND_PORT=6366
BACKEND_PORT=6365
FLUX_PANEL_ACCESS_HOST=你的域名或服务器IP
BACKEND_IMAGE=ghcr.io/tao-t356/flux-springboot-backend:2.0.8-beta
FRONTEND_IMAGE=ghcr.io/tao-t356/flux-vite-frontend:2.0.8-beta
FLUX_PANEL_VERSION=2.0.8-beta
FLUX_PANEL_REPO=tao-t356/flux
FLUX_FORCE_SECURE_NODE_TRANSPORT=true
LOGIN_MAX_ATTEMPTS=5
LOGIN_WINDOW_SECONDS=300
LOGIN_LOCK_SECONDS=900
JAVA_OPTS="-Xms128m -Xmx384m -Dfile.encoding=UTF-8 -Duser.timezone=Asia/Shanghai"
EOF
```

启动：

```bash
docker compose -f docker-compose-v4.yml up -d
```

如果服务器支持 IPv6，可改用：

```bash
docker compose -f docker-compose-v6.yml up -d
```

### 方式二：一键脚本

一键脚本会从当前仓库的 Release 下载对应文件。使用前请确保 Release 中已有需要的 compose 文件和节点二进制文件。

面板端：

```bash
curl -L https://raw.githubusercontent.com/tao-t356/flux/refs/heads/main/panel_install.sh -o panel_install.sh && chmod +x panel_install.sh && FLUX_PANEL_REPO=tao-t356/flux ./panel_install.sh
```

安装脚本会自动安装 Docker、自动分配前端/后端端口，并提示填写访问域名或服务器 IP，用于生成访问地址和预填“面板后端地址”。没有域名时直接回车使用自动检测到的公网 IP。部署完成后脚本会自检本机前端端口、域名解析和访问地址，并尝试放行本机 `ufw`/`firewalld` 端口。外网访问还需要在 VPS 控制台安全组放行前端端口和后端端口；如果域名开启 CDN/代理，非 80/443 端口可能无法访问。需要固定配置时，可提前设置 `FRONTEND_PORT`、`BACKEND_PORT`、`CORS_ALLOWED_ORIGINS`、`FLUX_PANEL_ACCESS_HOST` 环境变量。若 Release 文件暂未生成，脚本会自动从 `main` 分支下载 compose 配置。

节点端：

```bash
curl -L https://raw.githubusercontent.com/tao-t356/flux/refs/heads/main/install.sh -o install.sh && chmod +x install.sh && FLUX_PANEL_REPO=tao-t356/flux ./install.sh
```

## 默认管理员账号

- 账号：`facker668`
- 密码：`wohenshuai`

首次登录后请立即修改默认账号和密码。

## 目录结构

- `springboot-backend`：后端服务
- `vite-frontend`：前端面板
- `go-gost`：节点端程序
- `android-app`：Android 壳应用
- `ios-app`：iOS 壳应用

## 免责声明

本项目仅供个人学习与研究使用，基于开源项目进行二次开发。

使用本项目所带来的任何风险均由使用者自行承担，包括但不限于：

- 配置不当或使用错误导致的服务异常或不可用
- 使用本项目引发的网络攻击、封禁、滥用等行为
- 服务器因使用本项目被入侵、渗透、滥用导致的数据泄露、资源消耗或损失
- 因违反当地法律法规所产生的任何法律责任

本项目为开源的流量转发工具，仅限合法、合规用途。使用者必须确保其使用行为符合所在国家或地区的法律法规。

作者不对因使用本项目导致的任何法律责任、经济损失或其他后果承担责任，亦不提供任何形式的担保、承诺或技术支持。
