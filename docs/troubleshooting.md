# 排障手册

## 1. 手机能打开 DSH 页面，但看不到历史工作区

### 症状

- 页面正常加载，登录正常；
- 工作区列表为空，看不到 `dsh_prj` 等历史工作区；
- 本机浏览器一切正常。

### 原因

DSH `/api` 信任栅栏默认只信任 `127.0.0.1` / `localhost`。公网域名
`dsh.djj45.cn` 未加入 `trustedHosts` 时，所有工作区/会话 API 返回 403。

### 确认

```bash
curl -s -u 'dsh:密码' -H 'content-type: application/json' \
  -d '{"type":"client-request","rpcId":"11111111-1111-4111-8111-111111111111","method":"workspace.list","payload":{}}' \
  -w '\nHTTP=%{http_code}\n' \
  https://dsh.djj45.cn/api/workspace.list
```

- `403 forbidden` → 未放行；
- `200` 且返回 JSON 工作区列表 → 正常。

### 修复

把 `dsh-trust/cordis.patch.yml` 中的条目追加到 DSH Web profile 的
`cordis.patch.yml`，等待几秒热加载，然后刷新手机页面。

```yaml
- id: connection
  config:
    trustedHosts: ['dsh.djj45.cn', 'dsh-mac.djj45.cn']
```

修改前先备份原文件。

## 2. 认证后访问返回 502

含义：Nginx 正常，但 frps 无法把连接交给 frpc 或 frpc 连不上 DSH。

排查顺序：

1. 家庭电脑 frpc 是否运行：
   - Windows：任务管理器看 `frpc.exe`，或 `C:\frp\frpc.log`；
   - Mac：`launchctl list | grep dsh`。
2. 服务器上 remotePort 是否监听（仅本机回环）：

   ```bash
   sudo ss -lntp | grep 1808
   ```

   有 `127.0.0.1:18080` 才说明对应 frpc 已上线。
3. frpc 日志应有：
   - `login to server success`
   - `start proxy success`
4. 两台电脑不要用同一个 remotePort；Windows 是 18080，Mac 是 18081。

## 3. 手机访问返回 400 No required SSL certificate

含义：Nginx 已开启 mTLS 客户端证书校验，但浏览器没有出示有效客户端证书。

排查：

1. 手机是否已按「VPN 和应用用户证书」安装 `.p12`；
2. 是否使用 Chrome/Edge 访问（Firefox 使用独立证书库，不兼容安卓用户证书）；
3. 证书是否由当前 Nginx `ssl_client_certificate` 指向的 CA 签发；
4. 在服务器本机自测（有证书应返回 401 Basic Auth，而不是 400）：

   ```bash
   sudo curl -sk --resolve dsh-mac.djj45.cn:443:127.0.0.1 \
     --cert /etc/nginx/client-certs/dsh-android.crt \
     --key /etc/nginx/client-certs/dsh-android.key \
     -o /dev/null -w '%{http_code}\n' https://dsh-mac.djj45.cn/
   ```

## 4. frpc 连不上 7000 / 一直重试

1. 腾讯云安全组入站规则是否放行 `TCP 7000`。
2. 服务器本机防火墙是否拦截（本项目服务器 ufw 未启用）：

   ```bash
   sudo ufw status
   ```

3. 从家庭电脑测连通性：

   ```powershell
   Test-NetConnection -ComputerName 111.230.57.237 -Port 7000
   ```

4. 检查 token 是否与 `frps.toml` 一致。
5. 检查 frpc 是否写了 `transport.tls.enable = true`（服务端强制 TLS）。

## 5. Windows 双击 DSH-Tunnel-Win.cmd “没有输出”

这是正常现象：脚本用 `start /min` 启动 frpc，窗口最小化。
查看日志：

```powershell
Get-Content C:\frp\frpc.log -Tail 30
```

脚本已做防重复启动，重复双击不会开出多个实例。

## 6. SSH 密钥文件权限过宽

Windows OpenSSH 会拒绝权限过宽的 `.pem`：

```
Bad permissions ... UNPROTECTED PRIVATE KEY FILE!
```

修复（把用户名换成实际账户）：

```powershell
icacls D:\djj46.pem /inheritance:r
icacls D:\djj46.pem /grant "你的用户名:R"
```

## 7. frps 服务起不来 / 配置错误

查看日志：

```bash
journalctl -u frps -n 50 --no-pager
```

确认配置语法（frp v0.52+ 使用 TOML）：

```bash
/usr/local/frp/frps verify -c /usr/local/frp/frps.toml
/usr/local/frp/frpc verify -c /path/to/frpc.toml
```

## 8. 回滚

```bash
sudo rm /etc/nginx/sites-enabled/dsh.djj45.cn /etc/nginx/sites-enabled/dsh-mac.djj45.cn
sudo rm -rf /etc/nginx/client-certs
sudo nginx -t && sudo systemctl reload nginx
sudo systemctl disable --now frps
```

服务器原有配置备份（本次部署时创建）：
`/home/ubuntu/backups-dsh/nginx-etc-backup-*.tar.gz`

mTLS 改造前配置备份：
`/home/ubuntu/backups-dsh/nginx-mtls-*`

DSH patch 备份（本次修复时创建）：
`C:\Users\<用户>\.dsh\profiles\web\cordis.patch.yml.bak-*`
