# CCTT — PP-OCRv6 云端 OCR 集成

## 背景

用户在云服务器 (`beelzebub.top`) 部署了 PP-OCRv6 服务，通过 nginx 代理 `/api/ocr` → Python FastAPI (3457)。OCR 效果已验证，现在需要 Flutter App 端接入：拍照 → 上传识别 → 自动预填订单表单。

## 目标

1. App 拍照/选图后上传到 OCR 服务器
2. 解析返回的结构化数据（客户、类型、货物明细、费用）
3. 自动预填 AddOrderPage 表单 + AddOrderItemPage 明细
4. 用户可修改 OCR 结果后保存（OCR 辅助提速，人工兜底）
5. 手动录入流程完全不受影响

## OCR API 规范

```
POST {baseUrl}/api/ocr
Content-Type: multipart/form-data
Field: image (JPEG/PNG)

Response:
{
  "success": true,
  "orders": [{
    "partnerName": "老朱",
    "type": "inbound",
    "date_hint": "4.22",
    "items": [{ "itemName": "回毛", "quantity": 5132.0, "unitPrice": 5800.0, ... }],
    "fees": [{ "feeName": "铲车", "amount": 200.0 }]
  }]
}
```

- `unitPrice` 已是元/吨（手写单 5.8元/kg 自动 ×1000）
- `date_hint` 仅供参考，不用于 timestamp

## 文件改动清单

| 文件 | 改动 |
|---|---|
| `pubspec.yaml` | 新增 `http` 依赖 |
| `lib/services/settings_service.dart` | 新增 OCR 服务器 URL 存取 |
| `lib/services/ocr_service.dart` | **新建** — HTTP 上传 + 响应解析 |
| `lib/pages/settings_page.dart` | **新建** — OCR/MQTT 设置页 |
| `lib/pages/home_page.dart` | AppBar 新增设置按钮 |
| `lib/pages/add_order_page.dart` | 新增 OCR 拍照识别按钮 + 调用逻辑 |

## 实施步骤

### Step 1: 添加 HTTP 依赖
`pubspec.yaml` → 加 `http: ^1.2.2`

### Step 2: 扩展 SettingsService
`settings_service.dart` → 新增 `getOcrServerUrl()` / `setOcrServerUrl()`，默认值 `https://beelzebub.top`

### Step 3: 新建 OcrService
`lib/services/ocr_service.dart`:
- 模型类：`OcrResponse`, `OcrOrder`, `OcrItem`, `OcrFee`（fromJson）
- 静态方法 `OcrService.recognize(File image)`:
  1. 读取 OCR URL
  2. `http.MultipartRequest` POST `/api/ocr`
  3. 30s 超时
  4. 解析 JSON → `OcrResponse`
  5. 异常分类（SocketException → 网络、TimeoutException → 超时、FormatException → 格式）

### Step 4: 新建 SettingsPage
`lib/pages/settings_page.dart`:
- OCR 服务器地址输入框
- MQTT Broker / Port / Username / Password 输入框
- 保存按钮

### Step 5: HomePage 加设置入口
AppBar actions 加 `Icons.settings` 按钮 → 导航到 SettingsPage

### Step 6: AddOrderPage 集成 OCR
核心改动：

**6a. 新增状态变量：**
- `_ocrItems: List<OcrItem>?` — OCR 识别的货物
- `_ocrFees: List<OcrFee>?` — OCR 识别的费用
- `_isOcrLoading: bool` — 加载状态

**6b. UI：在客户名称卡片下方新增 OCR 卡片：**
- 默认：`[📷] OCR拍照识别` + `[拍照]` `[相册]` 按钮
- 加载中：spinner + "正在识别..."
- 成功：绿色勾 + "已识别 X 项货物" + "重新识别"

**6c. 拍照/选图：**
复用 `add_order_item_page.dart` 的 camera/image_picker 模式

**6d. `_performOcr(File image)`：**
1. 调 `OcrService.recognize(image)`
2. 弹确认对话框（显示客户、类型、货物列表、费用列表）
3. 用户确认 → 预填 `_partnerController` + 存 `_ocrItems/_ocrFees`

**6e. 修改 `_save()`：**
- 合并/新建分支中，将 `_ocrItems/_ocrFees` 转为 `OrderItem`/`OrderFee` 对象
- 传入 `AddOrderItemPage(existingItems: ocrItems, existingFees: ocrFees)`
- 用户可在 AddOrderItemPage 中增删改明细

## 数据流

```
AddOrderPage
  ├── 手动填写（仓库、日期、类型）
  ├── [OCR拍照识别]
  │     ├── 拍照/选图
  │     ├── OcrService.recognize()
  │     ├── 确认对话框
  │     └── 预填客户 + 存 items/fees
  └── [下一步]
        └── _save() → AddOrderItemPage(existingItems: ocrItems, existingFees: ocrFees)
              └── 用户审核修改 → 保存
```

## 错误处理

| 异常 | 用户提示 |
|---|---|
| 网络不通 | "网络连接失败，请检查网络设置" |
| 超时(30s) | "OCR 服务响应超时，请稍后重试" |
| 服务器错误 | "服务器错误，请稍后重试" |
| JSON 格式异常 | "OCR 返回数据异常" |
| 未识别到单据 | "未识别到单据信息，请重试或手动输入" |
| OCR URL 未配置 | "请先在设置中配置 OCR 服务器地址" |

所有错误不阻塞手动录入流程。

## 验证方式

1. 打开 App → 设置 → 确认 OCR URL 默认 `https://beelzebub.top`
2. 新建单据 → 点击 OCR拍照识别 → 拍照
3. 确认加载动画 → 确认对话框显示识别结果
4. 确认使用 → 客户名已填充 → 下一步 → 明细页已有货物+费用
5. 手动修改/增删明细 → 保存 → 详情页正确显示
6. 测试网络断开场景 → 友好错误提示
