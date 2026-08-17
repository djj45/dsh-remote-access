# dsh-remote-access

通过 **腾讯云 CVM + frp 内网穿透 + Nginx 反向代理**，让手机或外网浏览器安全访问家里电脑上的 **DeepSeek Harness (DSH)** Web 页面。

本仓库整理了本次部署用到的全部配置、安装脚本和文档。**仓库内不包含任何真实密钥、token 或 Basic Auth 密码**，统一使用占位符。

## 架构

```
手机浏览器
   │  https://dsh.djj45.cn / https://dsh-mac.djj45.cn
   ▼
域名 A 记录 → 腾讯云 CVM 公网 IP（Nginx 80/443）
   ▼
Nginx 站点（TLS 终止 + Basic Auth + WebSocket 反代）
   ▼
127.0.0.1:18080 / 18081（仅 CVM 本机回环）
   ▼
frps :7000（token 认证 + 强制 TLS）
   │  frp 加密隧道（家里电脑主动连出，无需公网 IP）
   ▼
frpc（Windows 18080 / Mac 18081）
   ▼
http://127.0.0.1:3080  ← DSH Web 服务
```

## 目录结构

```
.
├── README.md
├── docs/
│   ├── architecture.md        # 架构与安全设计
│   └── troubleshooting.md     # 排障手册
├── server/
│   ├── frps/frps.example.toml # frps 服务端配置模板
│   ├── systemd/frps.service   # 服务端 systemd 单元（已部署）
│   ├── nginx/                 # 已部署的 Nginx 站点配置
│   │   ├── dsh.djj45.cn.conf
│   │   └── dsh-mac.djj45.cn.conf
│   └── scripts/
│       ├── install-frps.sh        # CVM 一键安装 frps
│       ├── setup-basic-auth.sh    # 生成 Nginx Basic Auth 账号
│       └── apply-nginx-sites.sh   # 安装并启用两个 Nginx 站点
├── client/
│   ├── windows/
│   │   ├── frpc.example.toml      # Windows frpc 配置模板
│   │   ├── install-frpc.ps1       # Windows 一键安装脚本
│   │   ├── DSH-Tunnel-Win.vbs     # 隐藏窗口启动器（放入启动文件夹，登录自启）
│   │   ├── DSH-Tunnel-Win.cmd     # 手动启动（无窗口）
│   │   └── Stop-DSH-Tunnel-Win.cmd# 手动停止
│   └── macos/
│       ├── frpc.example.toml      # Mac frpc 配置模板
│       ├── install-frpc.sh        # Mac 一键安装脚本
│       └── com.dsh.frpc.plist     # Mac LaunchAgent 常驻配置
└── dsh-trust/
    └── cordis.patch.yml           # DSH /api 信任栅栏 trustedHosts 片段
```

## 本次实际部署环境

| 项目 | 值 |
|---|---|
| CVM | 腾讯云，Ubuntu 24.04，Nginx 1.24，公网 IP `111.230.57.237` |
| SSH | 端口 `27353`，Ubuntu 用户，密钥登录 |
| 域名 | `dsh.djj45.cn` → Windows DSH；`dsh-mac.djj45.cn` → Mac DSH |
| 证书 | `*.djj45.cn` 通配符证书，certbot + dns-aliyun，已有续期任务 |
| frp | v0.71.0，frps `7000`，隧道 `18080/18081`（仅绑 `127.0.0.1`） |
| DSH | `http://127.0.0.1:3080`，由 `dsh web` 启动 |
| 访问认证 | Nginx Basic Auth（DSH 本身无登录） |
| DSH API 信任 | `~/.dsh/profiles/web/cordis.patch.yml` 中配置 `trustedHosts` |

## 快速部署

1. DNS：为 `dsh` 和 `dsh-mac` 添加 A 记录指向 CVM 公网 IP。
2. 腾讯云安全组放行：`80/443`（Nginx）、`7000`（frps）、SSH 端口；**不要放行 18080/18081**。
3. 服务器安装 frps：

   ```bash
   FRP_TOKEN="$(openssl rand -hex 32)" sudo -E bash server/scripts/install-frps.sh
   ```

4. 服务器安装 Nginx 站点与 Basic Auth：

   ```bash
   sudo bash server/scripts/apply-nginx-sites.sh
   sudo bash server/scripts/setup-basic-auth.sh
   ```

5. Windows 安装 frpc（PowerShell）：

   ```powershell
   .\client\windows\install-frpc.ps1 -ServerAddr 111.230.57.237 -Token "<与 frps 相同的 token>"
   ```

6. Mac 安装 frpc：

   ```bash
   FRP_SERVER_ADDR=111.230.57.237 FRP_TOKEN="<与 frps 相同的 token>" sudo bash client/macos/install-frpc.sh
   ```

7. 关键一步：让 DSH 信任公网域名。把 `dsh-trust/cordis.patch.yml` 中的条目追加到
   `C:\Users\<用户>\.dsh\profiles\web\cordis.patch.yml`（Mac 同理为 `~/.dsh/profiles/web/cordis.patch.yml`）。
   DSH 支持该文件热加载，通常无需重启；也可重启 `dsh web` 生效。

## 验证

```bash
# 未认证应返回 401
curl -s -o /dev/null -w '%{http_code}\n' https://dsh.djj45.cn/

# 认证后，frpc 在线时应返回 200
curl -s -o /dev/null -w '%{http_code}\n' -u 'dsh:你的密码' https://dsh.djj45.cn/

# DSH API 应返回工作区 JSON（手机看不到历史工作区时，用这条确认）
curl -s -u 'dsh:你的密码' -H 'content-type: application/json' \
  -d '{"type":"client-request","rpcId":"11111111-1111-4111-8111-111111111111","method":"workspace.list","payload":{}}' \
  https://dsh.djj45.cn/api/workspace.list
```

## 常见问题

- 手机能打开页面但看不到历史工作区 → DSH `/api` 信任栅栏未放行域名，见 `docs/troubleshooting.md`。
- 认证后返回 502 → 对应机器的 frpc 未上线或远程端口冲突。
- `frpc` 连不上 7000 → 检查腾讯云安全组入站规则。
- Windows 双击启动脚本“没反应”→ 这是正常现象，frpc 通过 VBS 以完全无窗口方式运行，日志在 `C:\frp\frpc.log`。

## 回滚

```bash
sudo rm /etc/nginx/sites-enabled/dsh.djj45.cn /etc/nginx/sites-enabled/dsh-mac.djj45.cn
sudo nginx -t && sudo systemctl reload nginx
sudo systemctl disable --now frps
```

## 安全说明

- 公网只暴露 Nginx 的 `80/443` 和带 token + TLS 的 frps `7000`。
- frps 的远程端口通过 `proxyBindAddr = "127.0.0.1"` 只绑本机回环，外部无法直连隧道端口。
- DSH 本身没有认证，必须保留 Nginx Basic Auth。
- 不要把真实的 `frps.toml` / `frpc.toml` / `.htpasswd` 提交进仓库（已在 `.gitignore` 中排除）。
