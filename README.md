# CCTT 库存管理

离线优先的库存管理 App，专为**毛纺厂出入库场景**设计。支持本地 SQLite 持久化、拍照 OCR 录入、极速连录重量、局域网/Tailscale P2P 同步到 PC 后端。

## 核心功能

| 模块 | 说明 |
|------|------|
| **出入库录入** | 颜色/品种/毛重/扣皮/净重/件数/送货人，毛重-扣皮联动自动算净重 |
| **极速连录** | 自定义数字键盘 BottomSheet，连续录入重量自动汇总回填 |
| **单据详情** | 卡片分组展示全部字段，含毛重-扣皮净重校验 |
| **同步状态** | 四色标签：🟠未同步 / 🔵正在同步 / 🟢已同步 / 🔴同步失败 |
| **P2P 同步** | 动态配置 PC 后端地址（支持 Tailscale），Dio 15 秒超时 |
| **OCR 识别** | camera + google_mlkit_text_recognition + image_picker（真机调优中） |

## 技术栈

- **Flutter 3.x** / Dart 3.11
- **SQLite** (`sqflite`) 本地持久化，v4 平滑迁移
- **Dio** 网络同步，15 秒连接/接收超时
- **shared_preferences** 动态后端地址配置

## 数据库版本

| 版本 | 变更 |
|------|------|
| v4 | 拆分 `productName` → `color` + `variety`，新增 `grossWeight`/`tareWeight`/`totalPieces`/`deliveryPerson` |

## 同步机制

```
pending ──点击同步──► syncing ──POST 200──► synced（绿色）
                          │
                          └──异常──► failed（红色）
```

- 只要 `syncStatus != synced`，统统抓取重试，防止中断卡在 `syncing`
- `toJson()` 转换在 try-catch 内部执行，转换崩溃也会把状态复位为 `failed`
- 同步过程不阻断 UI，SnackBar 提示 + 列表实时刷新

## PC 后端 API 对接

### 配置地址

App 右上角 ⚙️ 设置 → 输入 PC 后端地址，例如：

```
http://100.x.x.x:3000
```

### 接收接口

```http
POST /api/sync
Content-Type: application/json
```

**Request Body**（JSON 数组）：

```json
[
  {
    "id": "uuid-string",
    "timestamp": 1713331200000,
    "partnerName": "张三纺织",
    "warehouseId": "warehouse-uuid",
    "type": "outbound",
    "quantity": 1523.50,
    "unitPrice": 8500.00,
    "syncStatus": "pending",
    "color": "白色",
    "variety": "羊毛",
    "totalPieces": 12,
    "grossWeight": 1550.00,
    "tareWeight": 26.50,
    "deliveryPerson": "李四"
  }
]
```

**Response**: HTTP 200 表示接收成功，App 将批量标记为 `synced`。

## 构建

```bash
flutter build apk --debug
```

产物：`build/app/outputs/flutter-apk/app-debug.apk`

## 项目结构

```
lib/
├── data/
│   └── database_helper.dart      # SQLite 单例 + v4 迁移
├── models/
│   ├── stock_movement.dart       # 库存移动记录（v4 字段）
│   └── warehouse.dart            # 仓库模型
├── pages/
│   ├── home_page.dart            # 主列表 + 同步 + 筛选
│   ├── add_record_page.dart      # 新建单据（毛厂出库单）
│   └── record_detail_page.dart   # 单据详情
├── services/
│   ├── sync_service.dart         # Dio P2P 同步引擎
│   └── settings_service.dart     # SharedPreferences 封装
└── main.dart
```

## 开发记录

| 提交 | 说明 |
|------|------|
| `f1412b1` | 统一四色同步状态标签，修复 syncing 卡死问题 |
| `d96c945` | 全面 UI 重构：颜色/品种拆分、毛重扣皮联动 |
| `c22773a` | 极速连录 BottomSheet |
| `9a8105d` | 单据详情页 |

---

详见 [AGENTS.md](AGENTS.md) 获取 AI 开发规范。
