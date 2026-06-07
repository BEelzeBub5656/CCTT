# CCTT 项目开发记录文档

文档生成日期：2026-06-07（更新）
项目名称：CCTT（离线优先个人库存管理 App + Web 管理后台）
技术栈：Flutter + Dart + SQLite + MQTT + Node.js + Express + better-sqlite3
最新数据库版本：v6（新增 imagePath 留档照片字段）

## 一、项目概述

CCTT 是一款基于 Flutter 开发的离线优先（Offline-First）个人库存管理应用。核心理念是：所有交易数据首先存入本地 SQLite 数据库，仅在检测到后端 PC API 可达时，才将未同步数据批量推送。

App 支持多仓库管理，可通过摄像头拍摄发票单据或从相册选择照片作为留档凭证，照片绑定到每条出入库记录，在详情页可全屏查看。

## 二、开发历程与每次迭代记录

### 2.1 第一阶段：项目初始化与依赖配置

**时间：**2026-04-17 第一轮

**新增文件：**

* `pubspec.yaml` — 项目依赖清单
* `lib/models/transaction_record.dart` — 交易记录数据模型（已废弃）
* `lib/data/database_helper.dart` — SQLite 数据库单例辅助类

**实现功能：**

* 本地 SQLite 数据库的增、查、改操作
* TransactionRecord 不可变数据模型

### 2.2 第二阶段：UI 层与本地数据展示

**时间：**2026-04-17 第二轮

**新增文件：**

* `lib/main.dart` — 应用入口
* `lib/pages/home_page.dart` — 主页面（列表展示）
* `lib/pages/add_record_page.dart` — 新建交易页面（手动表单）

**实现功能：**

* 全部历史记录列表展示（时间倒序）
* 同步状态视觉区分（pending / synced）
* 空状态提示、手动表单录入
* 保存后自动返回并刷新主页列表

### 2.3 第三阶段：OCR 发票识别与自动填充

**时间：**2026-04-17 第三轮

**修改文件：**

* `lib/pages/add_record_page.dart` — 新增 OCR 拍照识别功能
* `android/app/src/main/AndroidManifest.xml` — 新增 CAMERA 权限
* `ios/Runner/Info.plist` — 新增 NSCameraUsageDescription
* `pubspec.yaml` — 新增 sqflite_common_ffi 依赖
* `lib/main.dart` — 新增 sqflite_common_ffi 初始化逻辑

**实现功能：**

* 相机权限动态申请（Android / iOS）
* 摄像头预览与拍照
* Google ML Kit 离线中文 OCR 文本识别
* 正则提取交易对象和金额
* 识别结果自动回填表单

### 2.4 第四阶段：P2P 网络同步机制

**时间：**2026-04-17 第四轮

**新增文件：**

* `lib/services/sync_service.dart` — 同步服务类

**实现功能：**

* 批量查询本地 pending 记录
* 向后端 POST /api/sync 推送 JSON 数组
* 网络不可达检测（超时 / 连接错误）
* 同步成功后批量更新本地 synced 状态

### 2.5 第五阶段：多仓库系统架构升级

**时间：**2026-04-17 第五轮

**新增文件：**

* `lib/models/warehouse.dart` — 仓库模型（id UUID + name）
* `lib/models/stock_movement.dart` — 库存移动记录模型（原 TransactionRecord 升级版）

**修改文件：**

* `lib/data/database_helper.dart` — 数据库版本 1 → 2，新增 warehouses 表和 stock_movements 表，含 onUpgrade 迁移
* `lib/pages/home_page.dart` — 列表展示仓库名、入库/出库标签、数量×单价、总金额
* `lib/pages/add_record_page.dart` — 表单新增仓库下拉选择、入库/出库 SegmentedButton、数量/单价输入框，动态计算总金额
* `lib/services/sync_service.dart` — 引用从 TransactionRecord 迁移到 StockMovement

**实现功能：**

* 多仓库数据模型（Warehouse + StockMovement）
* 库存移动类型区分（入库 / 出库）
* 数量 × 单价 = 总金额计算
* 数据库迁移机制（v1 → v2，onUpgrade）
* 外键约束与索引优化
* OCR 识别数量与单价并自动回填

### 2.6 第六阶段：主页仓库筛选与添加仓库弹窗

**时间：**2026-04-17 第六轮

**修改文件：**

* `lib/pages/home_page.dart` — 全面重构

**实现功能：**

* 主页顶部仓库筛选器（所有仓库 / 单仓库）
* 按仓库实时过滤流水记录
* 添加仓库弹窗（输入名称 → 存入数据库）
* 空状态智能适配（全局空 / 单仓库空 / 无仓库）

### 2.7 第七阶段：AddRecordPage 表单优化

**时间：**2026-04-17 第七轮

**修改文件：**

* `lib/pages/add_record_page.dart` — UI 全面优化

**实现功能：**

* 目标仓库强制确认（顶部 Card + 校验）
* 入库/出库视觉区分（绿色/红色 SegmentedButton）
* 数量 × 单价 实时计算总金额
* 无仓库时禁用操作（防误操作）

### 2.8 第八阶段：真机测试与 Bug 修复（第一轮）

**时间：**2026-04-17 第八轮

**修复文件：**

* `lib/pages/home_page.dart` — 修复 DropdownButton 红屏报错
* `lib/pages/add_record_page.dart` — 新增表达式计算 + 重构相机预览

**增删改详情：**

* **Bug 1：添加仓库后页面红屏** — Flutter 3.19+ 中 DropdownButton 在 items 从空变为非空时，内部路由依赖关系未正确清理，触发 `_dependents.isEmpty` assert 失败。修复：给 DropdownButton 添加 `key: ValueKey(_warehouses.hashCode)` 强制重建；在所有 setState 调用前增加 mounted 检查。
* **Bug 2：数量输入不支持表达式** — 用户反馈需要以千克为单位，支持 `146+92+131` 的输入方式。新增 `_evaluateExpression()` 方法，支持 +、-、\*、/ 四则运算，在 `onEditingComplete` 和 `onTapOutside` 时自动计算并回填结果。数量标签改为 **"数量(kg)"**。
* **Bug 3：相机拍摄后闪退** — `CameraController` 在 `showDialog` 的 builder 中初始化，但 dispose 由外部方法控制，弹窗关闭和 dispose 不同步，导致 `CameraException(Disposed CameraController)`。修复：将相机预览提取为独立的 `_CameraPreviewDialog` StatefulWidget，由它自己管理完整的生命周期（initState → initialize → dispose）。同时设置 `enableAudio: false`，避免申请麦克风权限。

**实现功能：**

* 数量表达式自动计算（如 146+92+131 → 369）
* 相机预览生命周期正确管理（修复 disposed 异常，真机仍闪退待排查）
* 仅申请相机权限，不再申请麦克风权限

### 2.9 第九阶段：真机测试与问题排查（第二轮）

**时间：**2026-04-17 第九轮

**修复文件：**

* `lib/pages/add_record_page.dart` — 修复拍照闪退 + 表达式焦点切换卡住 + 新增相册识别
* `lib/services/sync_service.dart` — 修复同步错误提示不明确
* `pubspec.yaml` — 新增 image_picker 依赖
* `android/app/src/main/AndroidManifest.xml` — 新增 READ_MEDIA_IMAGES / READ_EXTERNAL_STORAGE 权限

**增删改详情：**

* **已知问题：真机点击拍照/相册识别按钮后 App 闪退** — 在 PHB110（一加/OPPO，Android 16）真机上，无论是点击「拍照识别」还是「相册识别」按钮，App 都会瞬间闪退崩溃。先后尝试了以下措施，但问题**仍未解决**：① 将 `CameraController` 提取为独立 StatefulWidget 管理生命周期（修复 disposed 异常）；② 分辨率从 `ResolutionPreset.high` 降为 `ResolutionPreset.medium`；③ 增加 ML Kit 异常捕获；④ 在打开相册/相机前显式请求 `Permission.camera` 和 `Permission.photos`。根因可能涉及：**Android 13+ 权限模型变化**、**image_picker 底层 Activity 生命周期异常**、或 **Google ML Kit 中文语言包未下载导致引擎初始化失败**。需要进一步排查。
* **Bug 5：输入数量表达式后界面卡住** — 用户在数量框输入 `123+45` 后不点回车，直接点击单价输入框。此时 `onTapOutside` 触发 `_onQuantityEditingComplete()`，该方法修改 `_quantityController.text` 并调用 `setState(() {})`，但焦点正在转移到单价输入框，导致 Flutter FocusNode 树进入不一致状态，界面无响应。更深层的问题是：`_saveRecord()` 中使用 `double.parse(_quantityController.text.trim())` 直接解析，若表达式未被提前计算（如仍为 "123+45"），会抛出 `FormatException`，而 `_saveRecord` 没有 try-catch，异常导致页面状态损坏但导航栈未恢复。

  处理方式：① 去掉 `onTapOutside`，消除焦点切换竞态条件；② 将数量输入框的回调改为 `onFieldSubmitted`，仅在用户按回车/下一项时计算表达式；③ `_saveRecord()` 中不再使用 `double.parse` 直接解析数量，而是调用 `_evaluateExpression()` 安全计算，即使表达式未提前触发也能正确解析；④ `_saveRecord()` 整体包裹 try-catch，任何异常都会显示 SnackBar 而不是导致页面卡死。
* **Bug 6：同步显示"未知网络错误"** — 点击主页右上角同步按钮时提示"同步失败：未知网络错误"。根因是 `SyncService._baseUrl = 'http://100.x.x.x:3000'` 为占位符地址，Dio 连接时抛出 `DioExceptionType.unknown`（底层为 `SocketException`），而原代码仅捕获了 connectionTimeout / receiveTimeout / connectionError / sendTimeout 四种类型，未处理 `unknown`，导致错误信息不友好。

  处理方式：① 新增 `SyncResult.notConfigured()` 工厂方法；② 在 `syncPendingRecords()` 开头检测 `_baseUrl` 是否包含 `100.x.x.x` 占位符，若是则直接返回"后端地址未配置"提示；③ 在 `DioExceptionType.unknown` 分支中增加对 `SocketException`、`Connection refused`、`No route to host` 等常见错误的识别，返回"无法连接到 PC，请检查网络或后端是否运行"。

**新增功能：**

* 相册选择识别 — 在"拍照识别"旁新增"相册识别"按钮（OutlinedButton），使用 `image_picker` 从系统相册选取照片，支持最大 1920×1920 压缩，复用同一套 OCR 识别逻辑
* OCR 识别来源区分 — 识别成功提示中标注"相机识别成功"或"相册识别成功"
* _saveRecord 异常保护 — 所有解析和数据库操作包裹 try-catch，异常时显示 SnackBar 并恢复按钮状态

### 2.10 第十阶段：设置后端地址弹窗

**时间：**2026-04-17 第十轮

**修改文件：**

* `pubspec.yaml` — 新增 `shared_preferences` 依赖
* `lib/pages/home_page.dart` — AppBar 新增设置图标按钮 + `_showSettingsDialog()`
* `lib/services/sync_service.dart` — 移除硬编码 `_baseUrl`，改为从 SharedPreferences 动态读取

**增删改详情：**

* **解决硬编码后端地址问题** — 原 `SyncService` 中 `static const String _baseUrl = 'http://100.x.x.x:3000'` 为占位符，用户无法在 App 内修改。处理方式：① 引入 `shared_preferences`；② 主页 AppBar 右侧新增 `Icons.settings` 按钮，点击弹出 AlertDialog（标题"设置后端地址"）；③ 输入框默认值从 SharedPreferences 的 `server_base_url` key 读取；④ 用户输入纯 IP:port 时自动补全 `http://` 协议头；⑤ `SyncService` 每次同步前调用 `_resolveBaseUrl()` 读取最新配置；⑥ 未配置时提示"后端地址未配置，请在设置中配置 PC 地址"。

**实现功能：**

* 主页右上角设置按钮（⚙️）
* 设置弹窗：输入后端地址并持久化到本地
* SyncService 动态读取地址，支持热更新
* 自动补全 http:// 协议头

### 2.11 第十一阶段：毛厂出库单模型扩展（数据库 v3）

**时间：**2026-04-18 第十一轮

**修改文件：**

* `lib/models/stock_movement.dart` — 新增 5 个 nullable 字段
* `lib/data/database_helper.dart` — _databaseVersion 升级到 3，建表语句加入新字段，_onUpgrade 增加 ALTER TABLE 迁移

**增删改详情：**

* **业务需求** — 为适配「毛厂出库单」场景，`StockMovement` 模型需要扩展。原有 `quantity` 字段语义保持不变，现在代表**净重(kg)**。新增字段：
  ① `productName`（String?）— 品名
  ② `totalPieces`（int?）— 总计件数
  ③ `grossWeight`（double?）— 共计重（毛重，kg）
  ④ `tareWeight`（double?）— 扣皮（去皮，kg）
  ⑤ `deliveryPerson`（String?）— 送货人

  所有新字段均为 nullable，兼容旧数据（v2 表中的现有记录这些字段自动为 NULL）。

  **数据库迁移策略（v2 → v3）**：使用 `ALTER TABLE stock_movements ADD COLUMN ...` 平滑添加 5 个新列，**绝不 DROP 旧表**，确保旧数据完整保留。`_onUpgrade` 中通过 `oldVersion < 3` 条件判断执行迁移。

**实现功能：**

* StockMovement 模型支持毛厂出库单全部字段
* 数据库 v3 建表语句含新字段
* ALTER TABLE 平滑迁移，旧数据零丢失
* toJson / fromJson / copyWith 全面支持新字段

### 2.12 第十二阶段：AddRecordPage 重构（毛厂出库单 UI）

**时间：**2026-04-18 第十二轮

**修改文件：**

* `lib/pages/add_record_page.dart` — 全面重构表单布局与计算逻辑

**增删改详情：**

* **新增 5 个输入字段** — 在录入页表单中补充：① 品名（TextFormField，可选）；② 送货人（TextFormField，可选）；③ 总件数（TextFormField，整数类型，可选）；④ 毛重(kg)（TextFormField，小数类型，可选）；⑤ 扣皮(kg)（TextFormField，小数类型，可选）。布局采用三行双列 + 单行结构：品名/送货人同行、净重/单价同行、总件数/毛重同行、扣皮独占一行。
* **标签语义调整** — 数量输入框 label 从"数量(kg)"改为**"净重(kg) / 数量"**，保留表达式计算功能（支持 `146+92+131` 累加）。单价输入框 label 从"单价（元）"改为**"单价 (元/吨)"**。
* **总金额计算公式变更** — 原公式为 `净重(kg) × 单价(元)`，现改为 `(净重(kg) / 1000) × 单价(元/吨)`。例如净重 1500kg、单价 4000元/吨，总金额为 `(1500/1000) × 4000 = 6000` 元。
* **保存逻辑扩展** — `_saveRecord()` 中解析总件数（`int.tryParse`）、毛重/扣皮（`double.tryParse`）后，连同品名、送货人一并写入 `StockMovement` 对象。所有新字段均为 nullable，空值时写入 null。

**实现功能：**

* 录入页支持毛厂出库单完整字段（品名、送货人、总件数、毛重、扣皮、净重、单价）
* 净重支持表达式计算（如多个数量累加）
* 单价单位改为"元/吨"，总金额按 (净重/1000)×单价 计算
* 可选字段空值校验（总件数必须为整数，毛重/扣皮必须为数字）

### 2.13 第十三阶段：记录详情页（RecordDetailPage）

**时间：**2026-04-18 第十三轮

**新增文件：**

* `lib/pages/record_detail_page.dart` — 单据详情展示页

**修改文件：**

* `lib/pages/home_page.dart` — 列表卡片添加 onTap 跳转

**增删改详情：**

* **新建 RecordDetailPage** — 接收 `StockMovement` 和 `warehouseName` 两个参数，使用 `ListView` + 多个 `Card` 分组展示全部信息。页面布局分为四个区域：
  ① **头部概览卡片**：醒目的入库/出库标签（绿色/红色圆角 pill）+ 大号总金额显示，背景色与操作类型呼应；
  ② **基本信息**：流水号、时间、仓库、同步状态；
  ③ **交易信息**：交易对象、品名、送货人（nullable 字段为空时显示"—"并置灰）；
  ④ **重量明细**：总件数、毛重、扣皮、净重（高亮显示）。若同时存在毛重和扣皮，额外显示计算值 `毛重 - 扣皮` 供校验；
  ⑤ **金额明细**：单价(元/吨)、计算公式 `(净重 kg ÷ 1000) × 单价`、总金额（高亮 teal 色）。
* **主页列表点击跳转** — `_buildMovementCard` 的 `ListTile` 添加 `onTap`，通过 `Navigator.push(MaterialPageRoute(...))` 跳转到详情页并传入记录和仓库名。

**实现功能：**

* 点击主页列表任意记录，可查看完整单据详情
* 详情页按分组卡片展示全部 13+ 个字段
* nullable 字段为空时友好显示"—"
* 总金额计算公式透明展示
* 毛重-扣皮校验值自动计算显示

### 2.14 第十四阶段：极速连录 BottomSheet（工厂场景重量批量录入）

**时间：**2026-04-18 第十四轮

**修改文件：**

* `lib/pages/add_record_page.dart` — 新增极速连录功能（_showRapidEntrySheet + _RapidEntryBottomSheet）

**增删改详情：**

* **需求背景** — 毛厂出库单场景中，一批货通常包含几十甚至上百件，每件重量需要逐个称重后累加。传统方式在单个输入框中逐个输入再按计算器累加，效率极低且容易出错。
* **UI 设计** — 在"净重(kg) / 数量"输入框右侧新增**"极速连录"**按钮（TextButton.icon，teal 主色）。点击后从底部弹出 `BottomSheet`，占据屏幕 85% 高度。BottomSheet 内部布局分为：
  ① **顶部总计栏**：固定高度，实时显示"共计 XXX kg（共 X 件）"，背景 teal 浅色；
  ② **已录入列表区**：使用 `Wrap` 展示所有已录入重量，每项以 `Chip` 呈现（序号 CircleAvatar + 重量文本 + 删除按钮），点击 Chip 的删除图标可移除该项；
  ③ **当前输入栏**：灰色背景圆角卡片，显示当前正在输入的数字，字体 24px 加粗；
  ④ **自定义数字键盘**：左侧 3×4 网格（7/8/9、4/5/6、1/2/3、./0/⌫），每个按键尺寸足够大（适合工厂戴手套操作）。退格键为红色。右侧纵向排列"下一笔"（橙色 ElevatedButton）和"完成"（teal FilledButton）两个大按钮。
* **交互逻辑**：
  - 用户通过数字键盘输入重量（如 50.2），点击**"下一笔"**后，该重量以 Chip 形式加入列表，输入区清空等待下一个；
  - 如果发现输错了，直接点击对应 Chip 上的删除图标即可移除；
  - 点击**"完成"**后，BottomSheet 关闭，自动将**总净重**（所有 Chip 重量之和）填入表单"净重"输入框，将**总件数**（Chip 数量）填入表单"总件数"输入框；
  - 若点击完成时输入区还有未提交的内容，会自动先提交再加入总计。

**实现功能：**

* 净重输入框旁"极速连录"快捷入口
* 自定义纯数字大键盘（0-9、小数点、退格），按键尺寸适配手套操作
* 已录入重量 Chip 列表，支持点击删除
* 实时总计栏（总重量 + 总件数）
* 完成后自动回填表单净重和总件数字段

## 三、当前已实现功能汇总

| 层级 | 已实现功能 |
| --- | --- |
| **数据层** | SQLite 本地数据库（单例模式）  warehouses 表（id UUID + name）  stock_movements 表（UUID 主键、时间戳、交易对象、仓库外键、类型、净重(kg)、单价、同步状态、品名、总计件数、毛重、扣皮、送货人）  增（insert）、查（getAll / getByWarehouse / getPending）、改（updateSyncStatus）  数据库迁移机制（onUpgrade v1 → v2 → v3，ALTER TABLE 平滑添加列，不丢数据）  外键约束与索引优化（warehouseId、syncStatus）  桌面端 FFI 兼容（Windows / Linux / macOS） |
| **拍照留档层** | camera 摄像头预览与拍照（独立 StatefulWidget 生命周期管理，ResolutionPreset.medium）  image_picker 从系统相册选择照片（最大 1920×1920 压缩）  照片自动保存到 app 私有目录 invoice_photos/，以记录 UUID 命名  imagePath 字段绑定照片到每条出入库记录  记录详情页展示留档照片，点击全屏查看 + 双指缩放  主页列表有照片的记录显示相机图标标记  相机权限动态申请（仅相机，不含麦克风）  相册读取权限申请（READ_MEDIA_IMAGES / READ_EXTERNAL_STORAGE） |
| **UI 层 - 主页** | 全部记录列表展示（时间倒序）  仓库筛选器（所有仓库 / 单仓库切换）  按仓库实时过滤流水  pending（橙色）与 synced（绿色）状态视觉区分  入库/出库标签区分（绿色/红色）  **点击列表卡片查看完整单据详情（RecordDetailPage）**  下拉刷新、空状态提示、FAB 跳转  添加仓库弹窗  手动同步按钮 + 同步中指示器 + SnackBar 反馈（含占位符检测） |
| **UI 层 - 录入页** | 目标仓库强制确认（Card + 校验）  入库/出库切换开关（SegmentedButton，绿色/红色）  拍照留档按钮 + 相册选择按钮  交易对象、品名、送货人 表单字段  净重(kg) / 数量 输入框，支持表达式计算（如 146+92+131），按回车时自动回填  单价 (元/吨) 输入框  总件数、毛重(kg)、扣皮(kg) 可选字段  实时总金额计算（动态卡片）：公式为 (净重/1000) × 单价  表单校验（非空、正数、可选整数/小数）  无仓库时禁用操作  保存异常保护（try-catch + SnackBar） |
| **网络同步层** | Dio HTTP 客户端封装  批量推送 pending 记录到后端 POST /api/sync  超时与连接错误检测（判定后端不可达）  占位符 IP 预检测（直接提示未配置）  unknown 类型异常识别（SocketException 等）  同步成功后批量更新本地 synced 状态  手动同步按钮 + 同步中指示器 + SnackBar 反馈 |

## 四、待检查验证的功能（TODO）

以下功能已在代码层面实现，但尚未在真实环境或真机上充分验证：

### 1. 后端 API 连通性

SyncService._baseUrl 当前为占位符 100.x.x.x。需在后端部署完成后验证 Tailscale / WireGuard 组网及 POST /api/sync 接口。

### 2. 网络恢复后的自动同步

当前仅支持手动触发同步。尚未实现「网络恢复后自动同步」的后台机制（如 workmanager + connectivity_plus 监听）。

### 3. 大量数据下的列表性能

当前 ListView.builder 未做分页，当记录数超过 1000 条时可能存在性能瓶颈。

### 4. 并发同步的边界情况

若用户在同步过程中新增记录，该记录不会被错误标记为 synced（读取 pending 列表在同步开始时完成），但需实际验证。

## 五、已修复的 Bug 清单

| Bug 描述 | 根因 | 修复方式 |
| --- | --- | --- |
| 添加仓库后页面红屏 `_dependents.isEmpty` | Flutter 3.19+ DropdownButton 在 items 变化时内部路由依赖未清理 | 添加 `key: ValueKey(_warehouses.hashCode)` 强制重建；所有 setState 前增加 mounted 检查 |
| 相机拍摄后闪退（已部分处理，真机仍闪退） `Disposed CameraController` | CameraController 在 showDialog builder 中初始化，dispose 由外部控制，弹窗关闭和 dispose 不同步 | 提取为独立 `_CameraPreviewDialog` StatefulWidget 自我管理生命周期；设置 `enableAudio: false`。**注：模拟器/低版本 Android 上不再报错，但 PHB110（Android 16）真机上点击拍照按钮仍直接闪退，根因待排查。** |
| 数量输入不支持表达式 | 只能输入纯数字 | 新增 `_evaluateExpression()`，支持 +、-、\*、/ 四则运算；onEditingComplete 自动计算回填 |
| 软件申请了麦克风权限 | CameraController 默认 enableAudio: true | 设置 `enableAudio: false`，仅申请相机权限 |
| flutter analyze 报 98k 个错误 | 项目根目录存在 Flutter SDK 副本（11/flutter/），分析器扫描了 SDK 源码 | 删除 SDK 副本；analysis_options.yaml 中 exclude flutter/\*\* 等目录 |
| VS Code 提示 SDK 无效 | 11/flutter/bin/ 下只有 cache 目录，缺少 flutter.bat | 删除 11/ 目录；重新 git clone 完整 Flutter SDK 到 d:\CCTT\flutter\ |
| NDK 编译报错 | 首次下载的 NDK 损坏，缺少 source.properties | 删除损坏的 NDK 目录，让 Gradle 重新下载 |
| 真机点击拍照/相册按钮后 App 闪退（**已解决 — 2026-06-07**） | Google ML Kit 中文 OCR 模型类 ChineseTextRecognizerOptions$Builder 未打包进 APK（OPPO 设备无 Google Play Services），拍照和选图正常但后续 OCR 步骤抛 NoClassDefFoundError | 移除 google_mlkit_text_recognition 依赖，删除全部 OCR 代码；拍照改为直接存档（保存到 app 私有目录 invoice_photos/，与记录 UUID 绑定）；按钮改为「拍照留档」「相册选择」；详情页新增照片查看（全屏+缩放） |
| 输入表达式后界面卡住 | onTapOutside 在焦点切换时修改 controller.text 并 setState，导致 FocusNode 不一致；saveRecord 中 double.parse 无法解析表达式且无 try-catch | ① 去掉 onTapOutside；② 改用 onFieldSubmitted；③ saveRecord 中使用 _evaluateExpression 安全解析；④ saveRecord 整体包裹 try-catch |
| 同步显示"未知网络错误" | 占位符 IP 100.x.x.x 导致 DioExceptionType.unknown，原代码未捕获该类型 | ① 增加占位符 IP 预检测；② DioExceptionType.unknown 分支中识别 SocketException 等常见错误，返回明确提示 |

## 六、可能的隐藏风险与注意事项

| 风险项 | 严重程度 | 说明 |
| --- | --- | --- |
| 真机相机/相册闪退（**已解决 — 2026-06-07**） | ★★★ | 根因确认为 Google ML Kit 中文 OCR 模型类 Android 侧缺失（NoClassDefFoundError）。已移除 ML Kit 依赖，拍照改为直接存档留底，不再闪退。详见 2.17 阶段。 |
| camera 不支持 Windows / Web | ★★☆ | camera 和 image_picker 插件不支持 Windows 桌面端。在 Windows 上开发调试需使用 Android 模拟器或真机。生产使用仅限 Android/iOS。 |
| 硬编码后端地址（**已解决**） | ★☆☆ | 原 SyncService._baseUrl 为硬编码占位符。现已通过 SharedPreferences + 设置弹窗实现动态配置，用户可在 App 内修改后端地址。 |
| 数据库迁移导致数据丢失 | ★★★ | v1 → v2 的 onUpgrade 直接 DROP 旧表。若用户已有旧数据，升级后数据丢失。生产环境需编写数据迁移脚本而非直接删除。 |
| 表达式计算无优先级 | ★★☆ | _evaluateExpression() 采用从左到右计算，不支持运算符优先级。例如 "100+2\*50" 会得到 5100 而不是 200。建议用户仅使用纯加法或简单乘法。 |
| 同步失败后的重试机制缺失 | ★★☆ | 当前仅做一次请求，失败即返回。没有指数退避重试、断点续传或离线队列持久化。网络抖动导致偶发失败需用户手动再次点击。 |
| 无数据加密 | ★★☆ | SQLite 数据库文件以明文存储。若设备被 root 或越狱，数据可被直接读取。 |
| BLoC / 依赖注入尚未接入 | ★★☆ | pubspec.yaml 已引入 flutter_bloc、get_it、injectable，但 UI 层仍使用 StatefulWidget + setState。 |

## 七、当前工程文件结构总览

cctt/
├── flutter/ Flutter SDK（git clone stable）
├── pubspec.yaml 依赖清单（含 image_picker、shared_preferences）
├── analysis_options.yaml Dart 分析器配置（排除 flutter/ 等目录）
├── android/app/src/main/AndroidManifest.xml Android 权限配置（CAMERA + READ_MEDIA_IMAGES）
├── ios/Runner/Info.plist iOS 权限配置
├── lib/
│ ├── main.dart 应用入口（FFI 初始化 + MaterialApp）
│ ├── pages/
│ │ ├── home_page.dart 主页（列表 + 仓库筛选 + 同步按钮 + 设置弹窗）
│ │ ├── add_record_page.dart 新建页（仓库确认 + 入出库 + 拍照留档 + 表达式计算）
│ │ ├── record_detail_page.dart 单据详情页（含留档照片查看）
│ │ └── edit_record_page.dart 编辑记录页
│ └── services/
│ └── sync_service.dart P2P 同步服务（Dio，动态读取 SharedPreferences 配置）
│ ├── models/
│ │ ├── stock_movement.dart 库存移动记录模型（v6 版，含 imagePath 照片字段）
│ │ └── warehouse.dart 仓库模型
│ ├── data/
│ │ └── database_helper.dart SQLite 单例（数据库版本 6， ALTER TABLE 迁移 v1→v6）
└── windows/ linux/ ios/ android/ macos/ web/ 原生平台工程

### 2.15 第十五阶段：Web 管理后台（Node.js + SQLite + MQTT）

**时间：**2026-04-27 第一轮

**新增目录：**

* `admin/` — 完整的 Web 管理后台项目

**新增文件（后端）：**

* `admin/package.json` — Node.js 依赖清单（express, better-sqlite3, mqtt, dotenv, uuid, cors）
* `admin/.env.example` — MQTT Broker 配置模板
* `admin/start.bat` — Windows 一键启动脚本
* `admin/server/index.js` — Express 入口，端口 3456，挂载 API 路由 + 静态文件 + MQTT 启动
* `admin/server/db.js` — better-sqlite3 初始化，Schema 完全匹配 Flutter v5（warehouses + stock_movements 建表 + 索引 + 外键）
* `admin/server/mqtt.js` — MQTT 订阅者（长连接，订阅 cctt/sync/inbound）+ 快照发布者（按需连接，发布 retain 消息到 cctt/sync/snapshot）
* `admin/server/routes/warehouses.js` — 仓库 CRUD（含外键引用检查，DELETE 时验证无关联记录）
* `admin/server/routes/movements.js` — 出入库记录 CRUD（分页 + 筛选 + 业务逻辑：净重=毛重-扣皮、总金额=(净重/1000)×单价、软删除、编辑后重置 syncStatus）
* `admin/server/routes/stats.js` — 仪表盘聚合统计（总记录数、按类型/同步状态分布、最近活动）
* `admin/server/routes/sync.js` — MQTT 连接状态查询 + 手动触发快照发布 + 同步日志

**新增文件（前端）：**

* `admin/public/index.html` — SPA 入口，Teal 主题导航栏 + MQTT 状态指示器
* `admin/public/css/app.css` — 完整样式系统（工业精致风、CSS 变量、响应式、凭证卡片、Toast、模态框）
* `admin/public/js/api.js` — REST API 封装（fetch-based）
* `admin/public/js/router.js` — Hash 路由（支持参数 :id）
* `admin/public/js/state.js` — 简易响应式状态管理
* `admin/public/js/pages/dashboard.js` — 仪表盘：4 统计卡片 + 最近活动表
* `admin/public/js/pages/movements.js` — 记录列表：筛选（仓库/类型/同步/搜索）+ 分页 + 作废/恢复
* `admin/public/js/pages/movement-form.js` — 新增/编辑表单：14 字段 + 净重/金额实时计算（匹配 Flutter AddRecordPage/EditRecordPage）
* `admin/public/js/pages/movement-detail.js` — 凭证详情：毛重-扣皮校验（匹配 Flutter RecordDetailPage）
* `admin/public/js/pages/warehouses.js` — 仓库管理：增删改 + 关联保护模态框
* `admin/public/js/pages/settings.js` — 同步设置：MQTT 状态 + 快照发布 + 同步日志

**实现功能：**

* Web 端完整 CRUD（仓库 + 出入库记录），100% 沿用 Flutter 端业务逻辑
* MQTT 订阅者自动接收 Flutter 端同步的数据（INSERT OR REPLACE 写入 SQLite）
* Web 端新建/编辑记录后 syncStatus = pending，发布快照后全部标记 synced
* MQTT 接收的记录强制标记 synced（数据本就来自手机）
* 仓库删除 FK 保护（有关联记录时返回 409）
* 软删除 + 恢复（isDeleted=1 ↔ 0，syncStatus 同步更新）
* 仪表盘聚合统计（总记录数、仓库数、按类型/同步状态分布）
* 快照手动发布（retain 消息到 cctt/sync/snapshot，手机端可拉取）
* 同步日志（最近 50 条，含时间戳 + 记录数 + 状态）

### 2.16 第十六阶段：UTF-8 编码统一 + 手机端自动检测云端差异

**时间：**2026-04-27 第二轮

**修改文件（Web 端）：**

* `admin/server/mqtt.js` — MQTT 消息接收显式 `toString('utf8')`；快照发布显式 `Buffer.from(payload, 'utf8')`
* `admin/server/index.js` — API 路由统一设置 `Content-Type: application/json; charset=utf-8`
* `admin/public/js/api.js` — fetch 请求加 `Accept: application/json; charset=utf-8`

**修改文件（Flutter 端）：**

* `lib/data/database_helper.dart` — insertMovement / insertWarehouse 新增可选参数 conflictAlgorithm（默认 replace）
* `lib/services/sync_service.dart` — 新增 PullResult 返回类型；pullSnapshot() 拉取前统计本地记录数，拉取后计算实际新增量；使用 ConflictAlgorithm.ignore 实现本地优先、只添加不覆盖
* `lib/pages/home_page.dart` — 新增 _unpushedCount（未推送云端数）、_cloudNewCount（云端新数据数）；启动时自动静默拉取云端快照 + 检测未推送记录；AppBar 上传按钮显示未推送角标，下载按钮显示云端新数据角标（teal）/ 绿色已同步图标

**实现功能：**

* 全链路 UTF-8 编码统一（Flutter ↔ MQTT ↔ Node.js ↔ SQLite ↔ 前端），消除乱码
* Web 端 SQLite 数据库持久化到本地磁盘（重启不丢数据）
* 手机启动时自动检测本地未推送记录 → SnackBar 通知"有 N 条记录尚未同步到云端"
* 手机启动时静默拉取云端快照 → 发现新数据时 teal SnackBar 通知"云端有 N 条新记录已同步到本地"
* 快照拉取采用本地优先策略（ConflictAlgorithm.ignore），只添加新记录，不覆盖不删除本地数据
* AppBar 双向状态指示器：☁️↑ 红色角标（待推送数量）+ ☁️↓ teal 角标/绿色图标（云端新数据/已同步）

### 2.17 第十七阶段：OCR 闪退修复 + 照片留档功能（v6）

**时间：**2026-06-07

**背景：**真机上点击「拍照识别」或「相册识别」按钮后 App 闪退。经 adb logcat 排查，根因确认为：

FATAL EXCEPTION: main
java.lang.NoClassDefFoundError: Failed resolution of:
Lcom/google/mlkit/vision/text/chinese/ChineseTextRecognizerOptions$Builder;
at TextRecognizer.initialize()
at TextRecognizer.handleDetection()

**根因：**`TextRecognizer(script: TextRecognitionScript.chinese)` 触发中文 OCR 模型类加载，但 `ChineseTextRecognizerOptions$Builder` 未打包进 APK（OPPO 设备无 Google Play Services，ML Kit 中文模型不可用）。拍照和选图功能本身正常，崩溃发生在后续的 OCR 步骤。

**修改决策：**既然发票是中文的，且 OPPO 设备上 Google ML Kit 中文模型不可用，与其继续与不可靠的本地 OCR 较劲，不如将拍照定位为「留档凭证」——照片绑定到每条记录，后期查证时直接看原始照片比 OCR 识别更可靠。

**修改文件：**

* `lib/pages/add_record_page.dart` — 移除 OCR 全部代码（_processOcrImage、_recognizeInvoice、_OcrResult 类），改为 _savePhotoToStorage；按钮标签改为「拍照留档」「相册选择」
* `lib/models/stock_movement.dart` — 新增 `String? imagePath` 字段，覆盖 constructor / toJson / fromJson / copyWith
* `lib/data/database_helper.dart` — 数据库版本 5→6；ALTER TABLE ADD COLUMN imagePath TEXT；建表语句同步更新
* `lib/pages/record_detail_page.dart` — 新增「留档照片」卡片（Card + Image.file），点击全屏查看（Dialog.fullscreen + InteractiveViewer 支持双指缩放）
* `lib/pages/home_page.dart` — 列表卡片有照片的记录在仓库/时间行显示 📷 小图标
* `pubspec.yaml` — 移除 google_mlkit_text_recognition: ^0.14.0 和 image: ^4.5.2 依赖

**照片存储流程：**

拍照/选图
→ 拷贝到 app 私有目录 invoice_photos/temp\_{timestamp}.jpg
→ _capturedImagePath 暂存
→ 保存记录时用 record UUID 重命名为 {uuid}.jpg
→ imagePath 字段写入 SQLite

**实现功能：**

* 拍照和相册选择不再闪退（确认通过 adb logcat 验证）
* 照片自动保存到 app 私有存储目录，与记录 UUID 绑定
* 记录详情页展示留档照片，点击可全屏缩放查看
* 主页列表有照片的记录显示相机图标标记
* 数据库平滑迁移 v5→v6（ALTER TABLE，不丢数据）
* 移除不可用的 google_mlkit_text_recognition 依赖，APK 体积减小

### 2.18 第十八阶段：MQTT Master-Slave 同步架构修复 + 长按 Bug

**时间：**2026-06-07

**背景：**双端数据不同步的问题根因有两点：(1) Node.js Master 在收到 MQTT 消息或 CRUD 后不自动发布快照；(2) Flutter Slave 使用 ConflictAlgorithm.ignore 拒绝接受 Master 的覆盖。

**修改文件（Web 端）：**

- `admin/server/mqtt.js` — client.on('message') 改为 async，入库后自动调用 publishSnapshot()
- `admin/server/routes/movements.js` — 引入 publishSnapshot，POST/PUT/DELETE/restore 后异步触发 triggerSnapshot()
- `admin/server/routes/warehouses.js` — POST/PUT/DELETE 后触发 triggerSnapshot()
- `admin/server/routes/sync.js` — 新增快照发布后的全量 synced 标记

**修改文件（Flutter 端）：**

- `lib/services/sync_service.dart` — PullResult 改为包含 addedCount（实际新增）；pullSnapshot() 拉取前统计本地数，拉取后计算差异；ConflictAlgorithm 从 ignore 改为 replace（Master 快照强制覆盖）
- `lib/pages/home_page.dart` — 预加载 _longPressDuration 到内存；onTapDown 改为同步；所有导航前调用 _cancelLongPress()；自动拉取成功时总刷新列表

**实现功能：**

- MQTT 消息入库后自动发布 retain 快照
- Web CRUD 操作后自动触发快照更新
- 手机拉取快照时 Master 数据强制覆盖本地
- 修复长按异步竞态条件导致的「手指抬起后仍弹出修改对话框」Bug
- 自动拉取成功后总刷新列表（修复替换数据但不刷新 UI 的 Bug）
- 同步超时从 5 秒缩短到 3 秒

### 2.19 第十九阶段：UI 交互重构 — 左滑改弹出菜单 + 垃圾桶 + 作废原因

**时间：**2026-06-07

**修改文件：**

- `lib/pages/home_page.dart` — 大规模重构：
  - 删除手动左滑/拖动手势代码（_SwipeableRecordCard 从复杂 StatefulWidget 简化为 StatelessWidget）
  - 卡片右上角放置羽毛笔图标（PopupMenuButton），点击弹出「修改记录」「作废记录」下拉菜单
  - 删除长按修改功能及 SettingsPage 入口
  - AppBar 设置齿轮图标替换为垃圾桶图标（Icons.delete_sweep），点击进入「已作废记录」列表页
  - 已作废记录从主页隐藏（_filteredMovements 过滤 isDeleted）
  - 新增 _DeletedRecordsPage 组件（含空状态、记录列表、点击进入详情）
  - 新增 _confirmDeleteRecord 作废二次确认对话框（含 5 个预设原因 ChoiceChip + 自定义输入框）
  - 已作废记录不显示操作菜单按钮
  - 同步失败对话框增加「重试」按钮
- `lib/pages/record_detail_page.dart` — 新增已作废标记：
  - 顶部红色横幅「此记录已作废」
  - 头部卡片入库/出库标签旁红色圆形「已作废」徽章
- `lib/pages/home_page.dart` imports — 移除 settings_service 和 intl 依赖

**实现功能：**

- 每条记录右上角羽毛笔图标 → 点击弹出自定义下拉菜单（修改/作废）
- 垃圾桶页面集中管理所有已作废记录，可点击查看详情
- 作废确认时可选 5 个预设原因或自定义输入
- 已作废记录不出现在主页
- 详情页醒目标记已作废状态
- 同步操作失败时提供对话框 + 重试按钮

1. **（已完成）**将硬编码的 _baseUrl 改为从 Settings 页面读取。
2. **（已完成）**搭建 Web 管理后台（Node.js + Express + SQLite），实现图形化 CRUD。
3. **（已完成）**手机端启动时自动检测云端差异，双向同步状态指示。
4. **（已完成）**MQTT Master-Slave 同步架构修复（自动快照 + Master 强制覆盖）。
5. **（已完成）**左滑删除改为羽毛笔弹出菜单 + 垃圾桶页面 + 作废原因选择。
6. **（已完成）**长按修改竞态条件 Bug 修复 + 详情页已作废标记。
7. 引入 flutter_bloc + get_it 重构状态管理，替换现有 setState。
5. 实现后台自动同步（connectivity_plus 监听网络恢复 + workmanager 定时任务）。
6. 如有需要，可接入云端 OCR API（如百度 OCR、阿里云 OCR）实现中文发票智能识别。
7. 添加库存统计报表（按仓库计算实时库存 = 入库合计 − 出库合计）。
8. 添加单元测试和 Widget 测试（flutter_test 已引入）。