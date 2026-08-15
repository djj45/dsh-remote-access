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
│   │   └── DSH-Tunnel-Win.cmd     # 登录自启脚本（已部署）
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
| 访问认证 | 手机 mTLS 客户端证书 + Nginx Basic Auth（DSH 本身无登录） |
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

8. （强烈建议）只允许你的手机访问：签发 mTLS 客户端证书，见下方「手机专属访问」。

## 手机专属访问（mTLS 客户端证书）

浏览器不会向服务器暴露手机硬件 ID（IMEI/序列号等），可靠的“硬件绑定”方式是
客户端证书：证书私钥只装在手机里，Nginx 在 TLS 握手阶段强制校验。
未安装证书的设备直接收到 `400 No required SSL certificate`，连 Basic Auth
登录框都看不到；安装证书后仍需通过 Basic Auth，形成设备 + 密码双重验证。

### 服务器签发（一次性）

```bash
sudo mkdir -p /etc/nginx/client-certs && sudo chmod 755 /etc/nginx/client-certs

# 1) 私有 CA（私钥永不离开服务器）
sudo openssl genrsa -out /etc/nginx/client-certs/dsh-client-ca.key 4096
sudo openssl req -x509 -new -nodes -key /etc/nginx/client-certs/dsh-client-ca.key \
  -sha256 -days 3650 -subj "/CN=DSH Remote Access Client CA" \
  -out /etc/nginx/client-certs/dsh-client-ca.crt

# 2) 手机客户端证书（把 djj45-android 换成你的设备名）
sudo openssl genrsa -out /etc/nginx/client-certs/dsh-android.key 2048
sudo openssl req -new -key /etc/nginx/client-certs/dsh-android.key \
  -subj "/CN=djj45-android" -out /etc/nginx/client-certs/dsh-android.csr
printf '%s\n' \
  'basicConstraints = critical, CA:FALSE' \
  'keyUsage = critical, digitalSignature, keyEncipherment' \
  'extendedKeyUsage = clientAuth' \
  'subjectKeyIdentifier = hash' \
  'authorityKeyIdentifier = keyid,issuer' \
  | sudo tee /etc/nginx/client-certs/dsh-android.ext >/dev/null
sudo openssl x509 -req -in /etc/nginx/client-certs/dsh-android.csr \
  -CA /etc/nginx/client-certs/dsh-client-ca.crt \
  -CAkey /etc/nginx/client-certs/dsh-client-ca.key -CAcreateserial \
  -out /etc/nginx/client-certs/dsh-android.crt -days 730 -sha256 \
  -extfile /etc/nginx/client-certs/dsh-android.ext

# 3) 导出给手机的 .p12（设置一个导入密码）
sudo openssl pkcs12 -export \
  -inkey /etc/nginx/client-certs/dsh-android.key \
  -in /etc/nginx/client-certs/dsh-android.crt \
  -certfile /etc/nginx/client-certs/dsh-client-ca.crt \
  -name "DSH Android" -out /etc/nginx/client-certs/dsh-android.p12

# 4) 收紧权限（nginx worker 只需读 CA 证书）
sudo chmod 644 /etc/nginx/client-certs/dsh-client-ca.crt /etc/nginx/client-certs/dsh-android.crt
sudo chmod 600 /etc/nginx/client-certs/dsh-client-ca.key /etc/nginx/client-certs/dsh-android.key /etc/nginx/client-certs/dsh-android.p12
```

Nginx 站点已在 443 块启用（与仓库中两个 conf 一致）：

```nginx
ssl_verify_client on;
ssl_client_certificate /etc/nginx/client-certs/dsh-client-ca.crt;
ssl_verify_depth 1;
```

### 安卓手机安装

1. 先设置锁屏 PIN/密码；
2. 把 `.p12` 安全传到手机（传完删除传输副本）；
3. 设置 → 安全 → 加密与凭据 → 安装证书 → VPN 和应用用户证书 → 选择 `.p12` 并输入导出密码；
4. 用 Chrome 访问 `https://dsh.djj45.cn` / `https://dsh-mac.djj45.cn`（Firefox 使用独立证书库，不保证兼容）。

### 换机 / 手机丢失

最简单的吊销方式：重新生成一个新的 CA 和客户端证书，并把
`ssl_client_certificate` 指向新 CA，`sudo nginx -t && sudo systemctl reload nginx`。
旧手机证书随即全部失效。

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
- Windows 双击启动脚本没反应 → frpc 以最小化窗口运行，日志在 `C:\frp\frpc.log`。

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
