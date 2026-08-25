# GitHub Actions 自动构建配置指南

## 功能概述

已配置完整的GitHub Actions自动构建流程，实现：
- ✅ 代码推送到main分支自动构建
- ✅ 打tag时自动创建Release
- ✅ 自动上传APK到服务器
- ✅ 自动更新版本信息API
- ✅ 多架构APK构建（arm64、armeabi、x86_64）

## 工作流程

```
代码推送到GitHub → GitHub Actions构建 → 上传到服务器 → 更新版本API → 手机自动检查更新
```

## 配置步骤

### 1. 添加GitHub Secrets

在GitHub仓库中配置服务器访问密钥：

1. 打开仓库页面：`https://github.com/BEelzeBub5656/CCTT`
2. 点击 `Settings` → `Secrets and variables` → `Actions`
3. 点击 `New repository secret`，添加以下3个密钥：

| Name | Value | 说明 |
|------|-------|------|
| `SERVER_HOST` | `你的服务器IP或域名` | 例如：`123.45.67.89` |
| `SERVER_USER` | `root` | SSH登录用户名 |
| `SERVER_PASSWORD` | `你的服务器密码` | SSH登录密码 |

### 2. 提交GitHub Actions配置

```bash
cd C:/Users/EDY/CCTT
git add .github/workflows/build.yml
git commit -m "添加GitHub Actions自动构建配置"
git push origin main
```

### 3. 触发构建

有3种方式触发构建：

#### 方式1：推送代码到main分支（推荐）
```bash
# 修改代码后
git add .
git commit -m "更新功能"
git push origin main
```

#### 方式2：创建版本tag
```bash
# 修改pubspec.yaml中的版本号，例如 version: 2.0.1+11
git add pubspec.yaml
git commit -m "发布v2.0.1"
git tag v2.0.1
git push origin main
git push origin v2.0.1
```

#### 方式3：手动触发
1. 打开 `https://github.com/BEelzeBub5656/CCTT/actions`
2. 选择 `Build and Release APK`
3. 点击 `Run workflow`
4. 选择分支并点击 `Run workflow`

## 查看构建状态

### 在GitHub上查看

1. 打开 `https://github.com/BEelzeBub5656/CCTT/actions`
2. 查看最新的workflow运行状态
3. 点击进入查看详细日志

### 构建成功后

**如果是main分支推送：**
- APK自动上传到服务器 `/opt/CCTT/admin/downloads/`
- 版本API自动更新
- 可在Actions页面下载APK文件（Artifacts）

**如果是tag推送（如v2.0.1）：**
- 自动创建GitHub Release
- APK附加到Release中
- 可在 `https://github.com/BEelzeBub5656/CCTT/releases` 下载

## 版本发布流程

### 标准发布流程

```bash
# 1. 修改版本号
# 编辑 pubspec.yaml，修改 version: 2.0.1+11
#                              ↑     ↑
#                         版本名  版本号

# 2. 提交代码
git add pubspec.yaml
git add .  # 添加其他修改的文件
git commit -m "发布v2.0.1: 新增xxx功能"

# 3. 创建tag
git tag v2.0.1

# 4. 推送到GitHub
git push origin main
git push origin v2.0.1

# 5. 等待构建完成（约5-10分钟）
# 访问 https://github.com/BEelzeBub5656/CCTT/actions 查看进度

# 6. 验证部署
curl https://www.beelzebub.top/api/version/latest

# 7. 测试自动更新
# 在旧版本APP上点击同步或重启，应该弹出更新提示
```

## 构建说明

### 构建环境
- 系统：Ubuntu Latest
- Java：17 (Zulu)
- Flutter：3.24.5 (stable)

### 构建产物

每次构建生成3个APK文件：

| 文件名 | 架构 | 适用设备 |
|--------|------|----------|
| `cctt-vX.X.X-arm64.apk` | arm64-v8a | 大多数现代手机（推荐） |
| `cctt-vX.X.X-armeabi.apk` | armeabi-v7a | 老旧32位设备 |
| `cctt-vX.X.X-x86_64.apk` | x86_64 | Android模拟器 |

### 自动上传逻辑

- **main分支**：上传arm64版本到服务器，自动更新版本API
- **tag推送**：创建Release，所有架构APK附加到Release
- **其他分支/PR**：只构建Debug版本，不上传

## 自定义配置

### 修改更新策略

编辑 `.github/workflows/build.yml`，找到更新版本API的部分：

```yaml
"forceUpdate": false,     # 改为true表示强制更新
"minVersion": 1           # 修改最低支持版本号
```

### 添加签名配置（可选）

为了让更新后的APP能正常覆盖安装，需要使用同一个签名：

```bash
# 1. 生成keystore
keytool -genkey -v -keystore cctt-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias cctt

# 2. 上传keystore到GitHub Secrets
# 将keystore转为base64
base64 cctt-release.jks > keystore.base64

# 3. 在GitHub Secrets添加：
# KEYSTORE_BASE64: (keystore.base64的内容)
# KEYSTORE_PASSWORD: 你的密码
# KEY_ALIAS: cctt
# KEY_PASSWORD: 你的密码
```

然后在workflow中添加签名步骤（参考Flutter官方文档）。

## 监控和调试

### 查看构建日志

```bash
# 在GitHub Actions页面点击workflow run
# 展开每个step查看详细输出
```

### 常见问题

**Q1: 构建失败 - Flutter版本问题**
```yaml
# 修改 .github/workflows/build.yml
flutter-version: '3.24.5'  # 改为项目兼容的版本
```

**Q2: 上传服务器失败**
```bash
# 检查GitHub Secrets是否正确配置
# 检查服务器SSH访问权限
# 查看workflow日志中的错误信息
```

**Q3: APK无法安装**
```bash
# 确保使用了签名
# 确保新旧版本签名一致
# 确保versionCode递增
```

## 成本估算

GitHub Actions免费额度：
- Public仓库：无限制
- Private仓库：每月2000分钟

每次构建约5-10分钟，足够日常使用。

## 下一步优化

### 1. 增量构建
使用缓存加速构建：
```yaml
- name: Cache Flutter dependencies
  uses: actions/cache@v3
  with:
    path: /opt/hostedtoolcache/flutter
    key: ${{ runner.os }}-flutter-${{ hashFiles('**/pubspec.lock') }}
```

### 2. 并行构建
分离测试和构建job，提高效率。

### 3. 构建通知
添加企业微信/钉钉通知，构建完成后自动提醒。

### 4. 自动化测试
集成UI测试，构建前自动运行。

## 快速开始

```bash
# 1. 配置GitHub Secrets
# 在仓库设置中添加 SERVER_HOST, SERVER_USER, SERVER_PASSWORD

# 2. 提交workflow配置
git add .github/workflows/build.yml
git commit -m "添加自动构建"
git push origin main

# 3. 修改版本号
# 编辑 pubspec.yaml: version: 2.0.1+11

# 4. 发布新版本
git add pubspec.yaml
git commit -m "发布v2.0.1"
git tag v2.0.1
git push origin main --tags

# 5. 等待构建完成，检查服务器
curl https://www.beelzebub.top/api/version/latest
```

## 相关链接

- GitHub Actions文档: https://docs.github.com/actions
- Flutter CI/CD: https://docs.flutter.dev/deployment/cd
- 项目Actions页面: https://github.com/BEelzeBub5656/CCTT/actions
