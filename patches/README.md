# DSH 源码补丁

这里存放给 DeepSeek Harness 源码仓库打的自定义补丁。补丁按提交整理，优先用 `git am` 应用，保留原始提交信息。

## dsh-api-response-compression.patch

- **提交**：`feat(connection): compress API responses with gzip/brotli`
- **基座**：deepseek-harness `master`，父提交 `99f6f02fec`（0.1.0-rc.7）
- **效果**：给 `/api` HTTP 桥接层增加响应压缩。`session.history` 等大 JSON 响应（实测 9.0 MB）压缩后约 808 KB，手机通过 frp 隧道加载历史消息从约 10 秒降到 1 秒内。
- **改动文件**：
  - `packages/client/connection/src/http-bridge.ts`
  - `packages/client/connection/tests/http-bridge.host.spec.ts`

### 应用

```bash
cd /path/to/deepseek-harness
git am /path/to/dsh-remote-access/patches/dsh-api-response-compression.patch
pnpm run build:lib:host
# 重启 dsh web 生效
```

### 回滚

```bash
cd /path/to/deepseek-harness
git reset --hard HEAD^   # 仅当 HEAD 就是该补丁提交时
# 或：git apply -R /path/to/dsh-remote-access/patches/dsh-api-response-compression.patch
```
