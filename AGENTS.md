# CCTT Agent 指南

## 项目背景

CCTT（库存管理 App）是面向**毛纺厂出入库场景**的离线优先 Flutter 应用。核心场景：仓库管理员在地磅旁用手机录入毛重/扣皮/颜色/品种等字段，数据先本地 SQLite 暂存，再通过 MQTT over TLS 推送到 PC 后端。

## 版本对照

| 版本 | 同步协议 | 关键提交 |
|------|----------|----------|
| v0.7 | **MQTT over TLS** | `3c99050` |
| v0.5 | Dio HTTP POST | `f1412b1` |

## 技术约束

- **Flutter SDK**: `d:\CCTT\flutter`（stable, Dart 3.11.5），**不能修改此路径**
- **目标平台**: Android（PHB110 真机 + emulator-5554）
- **数据库**: SQLite via `sqflite`，当前 **v4**，严禁 DROP 旧表，必须 `ALTER TABLE`
- **构建产物**: `build\app\outputs\flutter-apk\app-debug.apk`（~190MB）

## 代码规范

### 模型层
- `StockMovement` 所有新字段必须有默认值（`color = ''`, `variety = '', grossWeight = 0.0`, `tareWeight = 0.0`）
- `toJson()` / `fromJson()` 必须处理 `null`（`as String? ?? ''`, `(as num?)?.toDouble() ?? 0.0`）

### 数据库层
- 版本升级在 `_onUpgrade` 中用 `ALTER TABLE ... ADD COLUMN ... NOT NULL DEFAULT ''`
- 批量更新优先用 `Batch`（`db.batch()` + `batch.commit(noResult: true)`）

### UI 层
- Dialog 中的 `TextEditingController` 必须在 `WidgetsBinding.instance.addPostFrameCallback` 中 dispose
- 状态标签统一使用 `_buildSyncStatusBadge(SyncStatus)`，四色：🟠pending / 🔵syncing / 🟢synced / 🔴failed

### 同步层（v0.7 MQTT）
- `SyncService.syncPendingRecords()` 是 **static** 方法，返回 `String`
- Broker: `kf33d077.ala.cn-hangzhou.emqxsl.cn:8883`（TLS）
- Topic: `cctt/sync/inbound`，QoS 1
- ClientId: `const Uuid().v4()` 随机生成
- 抓取条件：`syncStatus == pending || syncStatus == failed`
- `toJson()` 转换必须在 try-catch 内部，崩溃时状态复位为 `failed`
- **异常安全**: `client.disconnect()` 必须在 `finally` 中调用；`MqttServerClient? client` 声明为 nullable，确保即使构造函数异常也不会 NPE
- **`pullSnapshot` 超时**: `updates.first.timeout(Duration(seconds: 5))`，防止云端无 retain 消息时永远挂起；超时后在 UI 层以 AlertDialog 弹窗提示
- **全量仓库**: `syncPendingRecords` 打包 `warehouses` 时必须传全量列表（`getAllWarehouses()`），不能只传关联仓库

## 文件清单

```
lib/
├── data/
│   └── database_helper.dart      # SQLite 单例，v4 迁移逻辑
├── models/
│   ├── stock_movement.dart       # SyncStatus 枚举: pending, syncing, synced, failed
│   └── warehouse.dart
├── pages/
│   ├── home_page.dart            # 主列表、同步按钮、筛选、长按编辑
│   ├── add_record_page.dart      # 新建/编辑单据（毛重扣皮联动）
│   ├── record_detail_page.dart   # 单据详情（统一状态标签）
│   └── settings_page.dart        # MQTT 配置 + 长按时间设置
├── services/
│   ├── sync_service.dart         # MQTT 同步引擎（异常安全）
│   └── settings_service.dart     # SharedPreferences 封装
└── main.dart
```

## 已知问题

- **真机 OCR 闪退**: PHB110（Android 16）点击拍照/相册瞬间崩溃。已尝试独立 StatefulWidget 生命周期、`ResolutionPreset.medium`、权限显式申请、全局 try-catch，均无效。根因待通过 `adb logcat` 排查 native crash。

## 已修复问题

| 问题 | 修复方案 |
|------|----------|
| MQTT `updates.first` 无 timeout 挂起 | 设为 3 秒超时，超时后 throw Exception |
| `client.disconnect()` 泄漏 | 全部移到 `finally` 块，`client` 声明为 nullable |
| Loading Dialog 异常后未关闭 | `try-finally` 包裹 `SyncService.pullSnapshot()` |
| 同步只打包关联仓库 | 改为 `getAllWarehouses()` 全量打包 |
