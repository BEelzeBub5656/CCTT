# CCTT Android 应用更新方案

## 已固定的方案

- Flutter 客户端继续作为正式手机端，不因更新能力重写 Expo。
- Android 内部发行阶段采用“自建版本清单 + APK 下载 + 用户确认安装”。
- 本地 Node 服务先承载版本清单；迁移云服务器后保持相同 JSON 协议。
- App 更新不得静默安装，必须交给 Android 系统安装器并由用户确认。
- 正式发行前必须固定 applicationId 和 Release 签名密钥；签名密钥需要离线备份。
- 同一升级链始终使用相同 applicationId、相同签名证书，并递增 versionCode。

## 版本清单协议

`GET /api/app-update/latest`

```json
{
  "versionName": "1.0.0",
  "versionCode": 1,
  "mandatory": false,
  "apkUrl": null,
  "sha256": "",
  "releaseNotes": "首个版本检查骨架",
  "publishedAt": "2026-08-22T00:00:00+08:00",
  "available": false
}
```

- `versionCode`：Android 构建号，判断是否有新版的唯一数值依据。
- `versionName`：展示给用户的版本名。
- `mandatory`：是否为强制更新；第一阶段仅解析，不阻断使用。
- `apkUrl`：APK 下载地址。服务器本地存在 `apkFile` 时自动生成。
- `sha256`：下一阶段下载 APK 后用于完整性校验。
- `available`：安装包是否已就绪。

## 分阶段推进

1. 已开始：本地版本清单、App 当前版本读取、设置页手动检查。
2. 下一阶段：APK 下载、进度显示、SHA-256 校验。
3. 后续阶段：Android 安装器、启动自动检查、可选强制更新。
4. 正式发行前：固定正式包名、生成并备份 Release keystore、HTTPS 部署和回滚测试。

## 本地测试

1. 在 `admin/releases/latest.json` 中提高 `versionCode`。
2. 手机与电脑连接同一局域网，启动 `admin/server/index.js`。
3. App 设置页把更新清单地址改为：
   `http://<电脑局域网IP>:3456/api/app-update/latest`
4. 点击“检查更新”，确认版本比较和更新说明显示正确。

