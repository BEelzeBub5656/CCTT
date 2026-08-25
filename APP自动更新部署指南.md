# CCTT APP 自动更新功能部署指南

## 功能概述

实现了完整的APP自动更新功能，无需用户手动下载APK，支持：
- ✅ 启动时自动检查更新
- ✅ 手动检查更新
- ✅ 强制更新（低版本必须更新）
- ✅ 更新日志展示
- ✅ 下载进度显示
- ✅ 自动安装APK

## 架构说明

```
APP启动 → 检查更新API → 有新版本 → 显示更新对话框 → 下载APK → 安装
         ↓
    www.beelzebub.top/api/version/check
```

## 服务器端部署

### 1. 更新服务器代码

在服务器上执行：

```bash
# 进入项目目录
cd /opt/CCTT

# 拉取最新代码
git pull origin main

# 或者手动上传新增的文件：
# - admin/server/routes/version.js
# - admin/server/index.js (已修改)

# 重启服务
pm2 restart cctt-admin

# 查看日志确认启动成功
pm2 logs cctt-admin --lines 20
```

### 2. 创建下载目录

```bash
# 创建APK存放目录
mkdir -p /opt/CCTT/admin/downloads

# 设置权限
chmod 755 /opt/CCTT/admin/downloads
```

### 3. 配置Nginx（推荐）

如果使用Nginx作为反向代理，需要增加下载目录的访问配置：

```nginx
# /etc/nginx/conf.d/cctt.conf
server {
    listen 443 ssl http2;
    server_name www.beelzebub.top;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    # API代理
    location /api/ {
        proxy_pass http://localhost:3456;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
    
    # 下载目录
    location /downloads/ {
        alias /opt/CCTT/admin/downloads/;
        autoindex off;
        # 限制只能下载APK文件
        location ~* \.apk$ {
            add_header Content-Type application/vnd.android.package-archive;
            add_header Content-Disposition 'attachment';
        }
    }
}
```

重启Nginx：
```bash
sudo nginx -t
sudo systemctl restart nginx
```

## 发布新版本流程

### 步骤1：构建APP

在开发机上：

```bash
cd C:/Users/EDY/CCTT

# 修改版本号 pubspec.yaml
# version: 2.0.1+11  (格式：版本名+版本号)

# 构建release版本
flutter build apk --release --split-per-abi

# 生成的APK位置：
# build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

### 步骤2：上传APK到服务器

```bash
# 在本地执行，上传APK
scp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
    root@your-server:/opt/CCTT/admin/downloads/cctt-v2.0.1.apk

# 或者使用SFTP、FTP等工具上传
```

### 步骤3：更新版本信息

使用API更新版本信息（可以用Postman、curl或Web界面）：

```bash
curl -X POST https://www.beelzebub.top/api/version/update \
  -H "Content-Type: application/json" \
  -d '{
    "versionCode": 11,
    "versionName": "2.0.1",
    "downloadUrl": "https://www.beelzebub.top/downloads/cctt-v2.0.1.apk",
    "fileSize": 25165824,
    "md5": "abc123...",
    "changelog": [
      "新增：表单字段映射实体出库单",
      "新增：离线数据同步功能",
      "优化：订单详情页面显示",
      "修复：数据库迁移问题"
    ],
    "forceUpdate": false,
    "minVersion": 1
  }'
```

**参数说明：**
- `versionCode`: 版本号（整数，必须递增）
- `versionName`: 版本名称（如：2.0.1）
- `downloadUrl`: APK下载地址
- `fileSize`: 文件大小（字节）
- `md5`: 文件MD5校验值（可选）
- `changelog`: 更新日志数组
- `forceUpdate`: 是否强制更新
- `minVersion`: 最低支持版本号（低于此版本强制更新）

### 步骤4：验证版本信息

```bash
# 检查版本信息
curl https://www.beelzebub.top/api/version/latest

# 模拟APP检查更新
curl 'https://www.beelzebub.top/api/version/check?currentVersion=10'
```

## APP端集成

### 1. 在main.dart中添加启动检查

```dart
import 'package:flutter/material.dart';
import 'widgets/update_dialog.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CCTT',
      home: Builder(
        builder: (context) {
          // 启动后检查更新
          WidgetsBinding.instance.addPostFrameCallback((_) {
            checkUpdateOnStartup(context);
          });
          return const HomePage();
        },
      ),
    );
  }
}
```

### 2. 在设置或关于页面添加手动检查

```dart
import '../widgets/update_dialog.dart';

// 在设置页面添加按钮
ListTile(
  leading: const Icon(Icons.system_update),
  title: const Text('检查更新'),
  trailing: const Icon(Icons.chevron_right),
  onTap: () => checkUpdateManually(context),
),
```

## 版本号管理规则

### pubspec.yaml 版本格式

```yaml
version: 2.0.1+11
         ↑     ↑
    版本名  版本号(versionCode)
```

- **版本名（versionName）**：给用户看的，如 2.0.1
- **版本号（versionCode）**：整数，用于比较版本，必须递增

### 版本号递增规则

| 更新类型 | versionCode | versionName | 示例 |
|---------|-------------|-------------|------|
| 重大更新 | +1 | x.0.0 | 10 → 11, 2.0.0 → 3.0.0 |
| 功能更新 | +1 | x.y.0 | 11 → 12, 2.0.0 → 2.1.0 |
| 修复补丁 | +1 | x.y.z | 12 → 13, 2.1.0 → 2.1.1 |

**注意：versionCode 必须严格递增，不能回退！**

## 测试流程

### 1. 测试版本检查

```bash
# 安装旧版本APP（versionCode=10）
adb install app-v2.0.0.apk

# 启动APP
# 应该弹出更新提示
```

### 2. 测试强制更新

```bash
# 修改服务器版本信息
curl -X POST https://www.beelzebub.top/api/version/update \
  -H "Content-Type: application/json" \
  -d '{
    "versionCode": 12,
    "versionName": "2.0.2",
    "forceUpdate": true,
    "minVersion": 11,
    ...
  }'

# 安装versionCode=10的APP
# 应该强制更新，无法取消
```

### 3. 测试下载安装

1. 点击"立即更新"
2. 观察下载进度
3. 下载完成后自动打开安装界面
4. 安装完成后重启APP

## 常见问题

### Q1: 更新对话框不显示
**检查：**
- 服务器API是否正常：`curl https://www.beelzebub.top/api/version/check?currentVersion=0`
- APP网络权限是否配置
- 版本号是否正确递增

### Q2: 下载失败
**检查：**
- APK文件是否正确上传到服务器
- downloadUrl是否正确
- 服务器downloads目录权限
- 手机存储权限

### Q3: 无法安装APK
**检查：**
- Android 8.0+ 需要"安装未知应用"权限
- APK文件是否完整（校验MD5）
- 签名是否一致

### Q4: 强制更新无效
**检查：**
- `minVersion` 设置是否正确
- APP的versionCode是否低于minVersion
- `forceUpdate` 是否设置为true

## 高级配置

### 1. 增量更新（可选）

可以实现差分更新，只下载差异部分：

```dart
// TODO: 实现增量更新逻辑
// 需要服务器支持差分包生成
```

### 2. 更新统计

在version.js中添加下载统计：

```javascript
router.get('/download-count', (req, res) => {
  // 记录下载次数
});
```

### 3. 分渠道更新

支持不同渠道的APP使用不同更新策略：

```json
{
  "versionCode": 11,
  "channels": {
    "production": "https://www.beelzebub.top/downloads/cctt-v2.0.1.apk",
    "beta": "https://www.beelzebub.top/downloads/cctt-v2.0.1-beta.apk"
  }
}
```

## 安全建议

1. **启用HTTPS**：确保下载链接使用HTTPS
2. **MD5校验**：下载后校验文件完整性
3. **签名验证**：确保APK签名一致
4. **访问控制**：API可以添加认证机制
5. **限流保护**：防止恶意下载消耗带宽

## 监控和维护

### 日志监控

```bash
# 查看更新API访问日志
pm2 logs cctt-admin | grep version

# 统计更新检查次数
grep "GET /api/version/check" /var/log/nginx/access.log | wc -l
```

### 磁盘清理

定期清理旧版本APK：

```bash
# 保留最近3个版本
cd /opt/CCTT/admin/downloads
ls -t cctt-*.apk | tail -n +4 | xargs rm -f
```

## 完整示例

参考 `admin/server/routes/version.js` 中的完整实现。

---

## 快速开始

```bash
# 1. 服务器部署
cd /opt/CCTT
git pull
pm2 restart cctt-admin

# 2. 构建APP
flutter build apk --release

# 3. 上传APK
scp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
    root@server:/opt/CCTT/admin/downloads/cctt-v2.0.1.apk

# 4. 更新版本信息
curl -X POST https://www.beelzebub.top/api/version/update \
  -H "Content-Type: application/json" \
  -d '{"versionCode": 11, "versionName": "2.0.1", ...}'

# 5. 测试
curl https://www.beelzebub.top/api/version/check?currentVersion=10
```
