# CCTT 库存管理

离线优先的库存管理 App，专为**毛纺厂出入库场景**设计。支持本地 SQLite 持久化、拍照/相册留档、极速连录重量、MQTT over TLS 同步到 PC 后端。

## 版本历史

| 版本 | 同步协议 | 说明 |
|------|----------|------|
| [**v0.7**](https://github.com/BEelzeBub5656/CCTT/releases/tag/v0.7) | **MQTT over TLS** | EMQX Broker，主题 `cctt/sync/inbound`，QoS 1 |
| [v0.5](https://github.com/BEelzeBub5656/CCTT/releases/tag/v0.5) | Dio HTTP POST | 直连 `$baseUrl/api/sync`，已归档 |

## 核心功能

| 模块 | 说明 |
|------|------|
| **出入库录入** | 颜色/品种/毛重/扣皮/净重/件数/送货人，毛重-扣皮联动自动算净重 |
| **极速连录** | 自定义数字键盘 BottomSheet，连续录入重量自动汇总回填 |
| **单据详情** | 卡片分组展示全部字段，含毛重-扣皮净重校验 |
| **同步状态** | 四色标签：🟠未同步 / 🔵正在同步 / 🟢已同步 / 🔴同步失败 |
| **MQTT 同步** | EMQX 公有云 Broker，8883/TLS，自动重试非 synced 记录 |
| **照片留档** | camera + image_picker，将票据照片保存到本地并绑定到单据/明细 |

## 技术栈

- **Flutter 3.x** / Dart 3.11
- **SQLite** (`sqflite`) 本地持久化，v4 平滑迁移
- **MQTT** (`mqtt_client`) over TLS，QoS 1
- **shared_preferences** 本地配置持久化

## 数据库版本

| 版本 | 变更 |
|------|------|
| v4 | 拆分 `productName` → `color` + `variety`，新增 `grossWeight`/`tareWeight`/`totalPieces`/`deliveryPerson` |

## 同步机制

```
pending ──点击同步──► syncing ──MQTT Publish──► synced（绿色）
                          │
                          └──异常──► failed（红色）
```

- 只要 `syncStatus != synced`，统统抓取重试，防止中断卡在 `syncing`
- `toJson()` 转换在 try-catch 内部执行，转换崩溃也会把状态复位为 `failed`
- **异常安全**: `client.disconnect()` 在 `finally` 中无条件调用，任何异常（断网、超时、broker 不可用）都会正确释放连接
- 同步过程不阻断 UI，SnackBar 提示 + 列表实时刷新

## MQTT 消息格式

### Broker 配置（v0.7）

| 参数 | 值 |
|------|-----|
| Broker | `kf33d077.ala.cn-hangzhou.emqxsl.cn` |
| Port | `8883` |
| Protocol | MQTT v3.1.1 over TLS |
| Topic | `cctt/sync/inbound` |
| QoS | `1` (At least once) |

### 消息 Payload

```json
{
  "records": [
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
  ],
  "warehouses": [
    { "id": "wh-uuid", "name": "主仓库" }
  ]
}
```

> PC 后端订阅 `cctt/sync/inbound` 即可接收数据。同步时打包**全量仓库列表**，确保快照恢复时不会丢失未关联待同步记录的仓库。

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
│   ├── sync_service.dart         # MQTT 同步引擎
│   └── settings_service.dart     # SharedPreferences 封装
└── main.dart
```

## 开发记录

| 提交 | 说明 |
|------|------|
| `291899c` | **v0.7+**: 快照同步、设置中心、长按编辑、仓库管理 |
| `3c99050` | **v0.7**: Dio → MQTT over TLS 迁移 |
| `f1412b1` | **v0.5**: 统一四色同步状态标签，修复 syncing 卡死问题 |
| `d96c945` | 全面 UI 重构：颜色/品种拆分、毛重扣皮联动 |
| `c22773a` | 极速连录 BottomSheet |
| `9a8105d` | 单据详情页 |

---

## OCR 拍照识别集成方案

> **目标**：用户在 APP 中拍照出入库单据 → 服务器 OCR 识别 → 自动预填 Order 表单 → 用户确认修改后保存。

### 架构总览

```
Flutter APP                    Cloud Server (beelzebub.top)
┌──────────────────┐   HTTPS   ┌─────────────────────────────────┐
│  📸 拍照/选图     │──────────→│  nginx (/api/ocr → :3457)       │
│  📤 上传图片      │           │         ↓                       │
│  📋 接收结构化数据 │←─────────│  OCR Service (Python FastAPI)   │
│  ✏️ 预填 Order 表单│           │    PP-OCRv6 Small (ONNX, 30MB) │
│  ✅ 用户确认保存   │           │    + 结构化文本解析器            │
└──────────────────┘           │    端口 3457, 常驻 ~280MB 内存  │
                               └─────────────────────────────────┘
```

PP-OCRv6 Small 已部署在服务器 `/opt/ppocr-env/`，模型缓存在 `~/.paddlex/official_models/`。

### API 规范

#### `POST /api/ocr`

**Request:** `multipart/form-data`

| 字段 | 类型 | 说明 |
|------|------|------|
| `image` | File (JPEG/PNG) | 单据照片，建议 ≤ 1920px 长边 |

**Response:**

```json
{
  "success": true,
  "elapsed_ms": 1800,
  "raw_texts": [
    { "text": "4.22.老朱：回毛.5132×5.8=29765元.", "confidence": 0.96 },
    "..."
  ],
  "document_type": "handwritten | formal",
  "orders": [
    {
      "partnerName": "老朱",
      "type": "inbound",
      "date_hint": "4.22",
      "items": [
        {
          "itemName": "回毛",
          "quantity": 5132.0,
          "unitPrice": 5800.0,
          "grossWeight": 0.0,
          "tareWeight": 0.0,
          "totalPieces": null,
          "deliveryPerson": null
        }
      ],
      "fees": [
        { "feeName": "铲车", "amount": 200.0 }
      ],
      "total_hint": 39050.0
    }
  ]
}
```

**字段说明：**
- `unitPrice` 统一为 **元/吨**（手写单上的 5.8 元/kg 会自动 ×1000 → 5800）
- `date_hint` 仅供参考（如 "4.22"），APP 用当前时间戳作为 `timestamp`
- `total_hint` 是单据上写的合计金额，用于 APP 端校验展示
- `raw_texts` 返回 OCR 原始识别结果，调试和兜底用

**错误响应：**

```json
{ "success": false, "error": "No text detected" }
```

### 单据类型与解析规则

#### 类型 1：手写进货记录（`handwritten`）

**特征**：包含 `×` 和 `=` 符号，格式为 `品名.数量×单价=金额`

**OCR 原文示例：**
```
4.22.老朱：回毛.5132×5.8=29765元.
回丝、1975×4.6.=9085元.
铲车.200元.
总：39050元.
```

**解析规则：**

1. **交易头检测**：匹配 `\d+\.\d+[\.。](.+?)[:：]` → 提取日期 + 对方名
2. **明细行匹配**：`(品名)[\.,、](\d+\.?\d*)\s*[×xX*]\s*(\d+\.?\d*)\s*=\s*(\d+\.?\d*)` → 拆出 itemName / quantity / unitPrice / amount
3. **费用行匹配**：费用关键词 `铲车|车费|搬运|装车|卸车|运费|卸` + `(\d+)元` → feeName / amount
4. **合计行匹配**：`总[:：]\s*(\d+\.?\d*)元` → total_hint
5. **单价转换**：若 `unitPrice < 50`，判定为元/kg，自动 `× 1000` 转为元/吨
6. **一页多单**：同一张照片可能有多笔交易（如老朱 + 宿迁），按交易头分割为多个 order

**已知品类词库**（用于辅助分词）：
```
回丝, 回毛, 涤纶, 毛晴, 羊毛, 丝束, 棉纺回丝, 手套, 毛球
```

**已知费用词库**：
```
铲车, 车费, 搬运, 装车费, 卸车费, 运费, 卸
```

#### 类型 2：正式出库单（`formal`）

**特征**：包含 `出库单` 关键词，表格式布局

**OCR 原文示例：**
```
开毛厂出库单
购货单位：毛旭强
小计 363
扣皮 3
净重 360kg
价格 6500吨元
总金额 2340元
汤剑忠
```

**解析规则：**

1. **对方名**：`购货单位[:：]\s*(.+)` → partnerName
2. **type**：包含 `出库` → outbound；包含 `入库` → inbound
3. **毛重**：`小计\s*(\d+\.?\d*)` → grossWeight
4. **扣皮**：`扣皮\s*(\d+\.?\d*)` → tareWeight
5. **净重**：`净重\s*(\d+\.?\d*)` → quantity；或 grossWeight - tareWeight
6. **单价**：`(?:价格|单价)\s*(\d+\.?\d*)\s*(?:吨|元)` → unitPrice（已为元/吨）
7. **总金额**：`总金额\s*(\d+\.?\d*)` → total_hint
8. **件数**：`(\d+)\s*件` → totalPieces
9. **送货/出库人**：最后的独立人名行 → deliveryPerson（低置信度，标记供用户确认）

### 实现清单

#### 1. Python OCR 微服务（服务器端，Hermes 部署）

**路径**：`/opt/cctt-server/ocr_service/`

```
ocr_service/
├── main.py          # FastAPI 应用，POST /ocr 端点
├── ocr_engine.py    # PP-OCRv6 封装，模型单例加载
├── parser.py        # 结构化文本解析器（正则规则）
└── requirements.txt # fastapi, uvicorn, python-multipart
```

**关键实现要点**：
- 模型在进程启动时加载一次（`@app.on_event("startup")`），后续请求复用
- 图片接收后先 resize 到长边 ≤ 1920px（减少推理时间）
- CORS 允许 `*`（APP 直连场景）
- 部署为 systemd 服务 `cctt-ocr.service`，监听 `127.0.0.1:3457`
- nginx 配置 `location /api/ocr { proxy_pass http://127.0.0.1:3457/ocr; }`

#### 2. Flutter APP 修改

##### 2a. 新建 `lib/services/ocr_service.dart`

```dart
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

class OcrResult {
  final bool success;
  final String? error;
  final String? documentType;
  final List<OcrOrder> orders;
  final List<OcrRawText> rawTexts;

  OcrResult({
    required this.success,
    this.error,
    this.documentType,
    this.orders = const [],
    this.rawTexts = const [],
  });

  factory OcrResult.fromJson(Map<String, dynamic> json) {
    return OcrResult(
      success: json['success'] ?? false,
      error: json['error'],
      documentType: json['document_type'],
      orders: (json['orders'] as List?)
          ?.map((o) => OcrOrder.fromJson(o))
          .toList() ?? [],
      rawTexts: (json['raw_texts'] as List?)
          ?.map((t) => OcrRawText.fromJson(t))
          .toList() ?? [],
    );
  }
}

class OcrOrder {
  final String partnerName;
  final String type; // "inbound" | "outbound"
  final String? dateHint;
  final double? totalHint;
  final List<OcrItem> items;
  final List<OcrFee> fees;

  OcrOrder({
    required this.partnerName,
    required this.type,
    this.dateHint,
    this.totalHint,
    this.items = const [],
    this.fees = const [],
  });

  factory OcrOrder.fromJson(Map<String, dynamic> json) => OcrOrder(
    partnerName: json['partnerName'] ?? '',
    type: json['type'] ?? 'inbound',
    dateHint: json['date_hint'],
    totalHint: (json['total_hint'] as num?)?.toDouble(),
    items: (json['items'] as List?)?.map((i) => OcrItem.fromJson(i)).toList() ?? [],
    fees: (json['fees'] as List?)?.map((f) => OcrFee.fromJson(f)).toList() ?? [],
  );
}

class OcrItem {
  final String itemName;
  final double quantity;
  final double unitPrice;
  final double grossWeight;
  final double tareWeight;
  final int? totalPieces;
  final String? deliveryPerson;

  OcrItem({
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    this.grossWeight = 0,
    this.tareWeight = 0,
    this.totalPieces,
    this.deliveryPerson,
  });

  factory OcrItem.fromJson(Map<String, dynamic> json) => OcrItem(
    itemName: json['itemName'] ?? '',
    quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
    unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
    grossWeight: (json['grossWeight'] as num?)?.toDouble() ?? 0,
    tareWeight: (json['tareWeight'] as num?)?.toDouble() ?? 0,
    totalPieces: json['totalPieces'] as int?,
    deliveryPerson: json['deliveryPerson'] as String?,
  );
}

class OcrFee {
  final String feeName;
  final double amount;

  OcrFee({required this.feeName, required this.amount});

  factory OcrFee.fromJson(Map<String, dynamic> json) => OcrFee(
    feeName: json['feeName'] ?? '',
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
  );
}

class OcrRawText {
  final String text;
  final double confidence;

  OcrRawText({required this.text, required this.confidence});

  factory OcrRawText.fromJson(dynamic json) {
    if (json is Map) {
      return OcrRawText(
        text: json['text'] ?? '',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      );
    }
    return OcrRawText(text: json.toString(), confidence: 0);
  }
}

class OcrService {
  // 服务器 OCR 端点（走 nginx 反向代理）
  static const String _baseUrl = 'https://www.beelzebub.top/api/ocr';

  /// 上传图片并获取 OCR 结构化结果
  static Future<OcrResult> recognize(File imageFile) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_baseUrl));
      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );

      final response = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final body = await response.stream.bytesToString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      return OcrResult.fromJson(json);
    } catch (e) {
      return OcrResult(success: false, error: e.toString());
    }
  }
}
```

##### 2b. 新增依赖 `pubspec.yaml`

```yaml
dependencies:
  http: ^1.2.0  # 如果尚未添加
```

##### 2c. 修改 `lib/pages/add_order_page.dart`

**改动要点**：

1. 在页面顶部（AppBar 或表单上方）添加一个 **"📸 拍照识别"** 按钮
2. 点击后调用 `ImagePicker` 拍照或选择图片
3. 将图片传给 `OcrService.recognize()`
4. 显示 loading 状态（CircularProgressIndicator + "正在识别..."）
5. 收到结果后：
   - 如果 `orders` 只有 1 条 → 直接预填当前表单
   - 如果 `orders` 有多条 → 弹出选择 Dialog，让用户选择要录入哪一笔
   - 预填逻辑：
     - `partnerName` → 填入对方名称输入框
     - `type` → 设置入库/出库/进货按钮
     - 遍历 `items` → 自动创建对应 OrderItem（调用已有的"添加明细"逻辑）
     - 遍历 `fees` → 自动创建对应 OrderFee
   - 预填后弹出 SnackBar：`"已识别 X 条明细 + Y 笔费用，请检查确认"`
6. 用户可以在预填后自由修改任何字段，然后正常保存

**UI 布局参考**：

```
┌─────────────────────────────────┐
│ [📸 拍照识别]  [🖼 从相册选择]    │  ← 新增按钮行
├─────────────────────────────────┤
│ 对方名称: [老朱          ]       │  ← OCR 预填
│ 类型:     ● 进货  ○ 出库  ○ 入库│
├─────────────────────────────────┤
│ 明细 1:  回毛  5132kg  ¥5800/吨 │  ← OCR 自动创建
│ 明细 2:  回丝  1975kg  ¥4600/吨 │
│ [+ 添加明细]                     │
├─────────────────────────────────┤
│ 费用 1:  铲车  ¥200              │  ← OCR 自动创建
│ [+ 添加费用]                     │
├─────────────────────────────────┤
│ 合计: ¥39050                     │
│        [保存]                    │
└─────────────────────────────────┘
```

##### 2d. OCR 结果 → Order 数据模型映射

```dart
// 伪代码：OCR 结果转 Order + Items + Fees
void applyOcrResult(OcrOrder ocrOrder) {
  // 1. 填充 Order 头
  partnerNameController.text = ocrOrder.partnerName;
  selectedType = ocrOrder.type == 'outbound'
      ? MovementType.outbound
      : ocrOrder.type == 'supply'
          ? MovementType.supply
          : MovementType.inbound;

  // 2. 清空已有明细，填入 OCR 识别的明细
  orderItems.clear();
  for (final item in ocrOrder.items) {
    orderItems.add(OrderItem(
      orderId: currentOrderId,
      itemName: item.itemName,
      quantity: item.quantity,
      unitPrice: item.unitPrice,        // 已为元/吨
      grossWeight: item.grossWeight,
      tareWeight: item.tareWeight,
      totalPieces: item.totalPieces,
      deliveryPerson: item.deliveryPerson,
    ));
  }

  // 3. 清空已有费用，填入 OCR 识别的费用
  orderFees.clear();
  for (final fee in ocrOrder.fees) {
    orderFees.add(OrderFee(
      orderId: currentOrderId,
      feeName: fee.feeName,
      amount: fee.amount,
    ));
  }

  // 4. 刷新 UI
  setState(() {});
}
```

### OCR 识别已知局限（供 APP 端 UI 提示用）

| 场景 | 表现 | 建议 |
|------|------|------|
| 手写人名 | "毛旭强"→"毛至九强"，准确率 ~70% | 预填后高亮提示用户检查 |
| 小数点 | 偶尔丢失（4.65→465） | 金额校验：若 qty×price ≠ amount，提示异常 |
| 元/kg vs 元/吨 | 自动转换，阈值 <50 视为元/kg | APP 端可增加单位切换开关 |
| 一页多单 | 支持，按交易头分割 | 返回多条 order，用户选择 |
| 印刷表单 | 数字识别率 98%+ | 几乎无需修改 |
| 模糊/歪斜照片 | 识别率下降 | 提示用户重拍 |

### 部署备忘（服务器端，Hermes 负责）

```bash
# OCR 微服务路径
/opt/cctt-server/ocr_service/

# 虚拟环境（已就绪）
/opt/ppocr-env/

# PP-OCRv6 Small 模型（已缓存）
~/.paddlex/official_models/PP-OCRv6_small_{det,rec}_onnx/

# systemd 服务
sudo systemctl start cctt-ocr
sudo systemctl enable cctt-ocr

# nginx 添加 location（在 beelzebub.top server block 中）
location /api/ocr {
    proxy_pass http://127.0.0.1:3457/ocr;
    client_max_body_size 10M;
    proxy_read_timeout 30s;
}
```

---

详见 [AGENTS.md](AGENTS.md) 获取 AI 开发规范。
