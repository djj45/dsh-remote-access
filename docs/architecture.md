# 架构与安全设计

## 目标

在家里的 Windows/Mac 上运行 DSH Web（`http://127.0.0.1:3080`），通过已有的腾讯云 CVM 和域名，让手机在公网安全访问，并保留历史工作区与实时会话。

## 组件与数据流

```
手机/外网浏览器
   │  HTTPS + Basic Auth
   ▼
Nginx (CVM)
   │  TLS 终止；server_name 区分 dsh / dsh-mac
   │  WebSocket Upgrade 透传
   ▼
frps (CVM)
   │  remotePort 只监听 127.0.0.1，公网不可达
   │  frpc 通过 7000 主动连入；token 认证 + TLS
   ▼
frpc (家庭电脑)
   ▼
DSH Web 127.0.0.1:3080
```

## 为什么这样设计

1. **家里没有公网 IP**：frp 由内向外建连，NAT 环境可用。
2. **两台电脑都可能跑 DSH**：用两个子域名 + 两个 remotePort（18080/18081），互不影响。
3. **复用现有 Nginx 与通配符证书**：新增两个 vhost，不动原有站点。
4. **DSH 只监听 127.0.0.1**：不需要把 DSH 暴露到 `0.0.0.0`，由 frpc 在本机回环转发。

## 端口矩阵

| 位置 | 端口 | 绑定 | 暴露范围 |
|---|---|---|---|
| CVM Nginx | 80/443 | 0.0.0.0 | 公网（安全组放行） |
| CVM frps | 7000 | 0.0.0.0 | 公网（安全组放行，token+TLS） |
| CVM frps remote | 18080/18081 | 127.0.0.1 | 仅 CVM 本机 |
| 家庭 DSH | 3080 | 127.0.0.1 | 仅家庭本机 |

## DSH 的 `/api` 信任栅栏（关键）

DSH 的 `dsh-client-connection` 插件对所有 `/api` HTTP 请求和 WebSocket
upgrade 做 Host/Origin 校验，默认只信任 loopback 权威：

- 公网域名访问时，Host 是 `dsh.djj45.cn`；
- 不配置 `trustedHosts` 时，`/api/*` 一律返回 `403 forbidden`；
- 表现：页面能打开、能渲染，但工作区/会话列表为空。

修复方式：在 DSH Web profile 的 patch 层声明可信权威：

```yaml
- id: connection
  config:
    trustedHosts: ['dsh.djj45.cn', 'dsh-mac.djj45.cn']
```

文件位置：

- Windows：`C:\Users\<用户>\.dsh\profiles\web\cordis.patch.yml`
- macOS/Linux：`~/.dsh/profiles/web/cordis.patch.yml`

该 patch 支持热加载；修改保存后数秒生效。DSH 重启后依然生效。

## 认证与安全

- DSH Web 本身不提供认证，因此外层必须加 **Nginx Basic Auth**。
- 只允许指定手机访问时，再叠加 **mTLS 客户端证书**：Nginx 在 TLS 握手阶段
  校验 `ssl_verify_client on`，未装证书的设备直接收到 400，连登录框都看不到。
- Basic Auth 只在 HTTPS 上生效（HTTP 会 301 跳转）。
- frps 使用 `auth.token` 与 `transport.tls.force = true`，防止未授权 frpc 注册隧道。
- 建议把 Basic Auth 密码设为 16 位以上随机串；公网 7000 来源为 `0.0.0.0/0` 是可接受的，
  因为 token 强度足够，且远程端口不对外。
- 若要求更高，可在 Nginx 前增加 IP 白名单或 fail2ban 拦截 401 爆破。

## 证书与续期

- 使用已有 `*.djj45.cn` 通配符证书，新增子域名无需签发。
- 当前续期由 certbot 管理（dns-aliyun 验证），`renew_hook` 会 reload Nginx。
- 新增的 vhost 直接引用 `/etc/letsencrypt/live/djj45.cn/fullchain.pem`，
  不影响原有续期流程。
