import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/database_helper.dart';
import '../models/stock_movement.dart';
import '../models/warehouse.dart';

/// 新建库存移动记录页面
///
/// 支持手动录入、相机 OCR 识别发票自动填充、以及从相册选择照片识别。
class AddRecordPage extends StatefulWidget {
  const AddRecordPage({super.key});

  @override
  State<AddRecordPage> createState() => _AddRecordPageState();
}

class _AddRecordPageState extends State<AddRecordPage> {
  final _formKey = GlobalKey<FormState>();
  final _partnerController = TextEditingController();
  final _quantityController = TextEditingController();
  final _unitPriceController = TextEditingController();

  List<Warehouse> _warehouses = [];
  String? _selectedWarehouseId;
  MovementType _selectedType = MovementType.inbound;

  bool _isSaving = false;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _loadWarehouses();
  }

  Future<void> _loadWarehouses() async {
    final list = await DatabaseHelper.instance.getAllWarehouses();
    if (mounted) {
      setState(() {
        _warehouses = list;
        if (list.isNotEmpty) {
          _selectedWarehouseId = list.first.id;
        }
      });
    }
  }

  @override
  void dispose() {
    _partnerController.dispose();
    _quantityController.dispose();
    _unitPriceController.dispose();
    super.dispose();
  }

  // ------------------- 表达式计算 -------------------

  /// 解析并计算简单算术表达式（如 "146+92+131"）
  /// 支持 +、-、*、/，从左到右计算，不支持优先级。
  double? _evaluateExpression(String input) {
    final expr = input.replaceAll(' ', '');
    if (expr.isEmpty) return null;

    // 直接是数字
    final direct = double.tryParse(expr);
    if (direct != null) return direct;

    // 提取数字和运算符
    final regex = RegExp(r'(\d+\.?\d*)|([+\-*/])');
    final matches = regex.allMatches(expr).toList();
    if (matches.isEmpty) return null;

    final numbers = <double>[];
    final operators = <String>[];

    for (final match in matches) {
      final token = match.group(0)!;
      if (RegExp(r'[+\-*/]').hasMatch(token)) {
        operators.add(token);
      } else {
        numbers.add(double.parse(token));
      }
    }

    if (numbers.isEmpty) return null;

    double result = numbers.first;
    for (int i = 0; i < operators.length; i++) {
      if (i + 1 >= numbers.length) break;
      final op = operators[i];
      final num2 = numbers[i + 1];
      switch (op) {
        case '+':
          result += num2;
          break;
        case '-':
          result -= num2;
          break;
        case '*':
          result *= num2;
          break;
        case '/':
          if (num2 == 0) return null;
          result /= num2;
          break;
      }
    }
    return result;
  }

  /// 当数量输入框提交时，自动计算表达式并回填
  void _onQuantitySubmitted(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    final result = _evaluateExpression(trimmed);
    if (result != null) {
      _quantityController.text = _formatNumber(result);
      setState(() {}); // 刷新总金额
    }
  }

  String _formatNumber(double value) {
    var text = value.toStringAsFixed(2);
    // 移除末尾的 .00
    if (text.endsWith('.00')) {
      text = text.substring(0, text.length - 3);
    }
    return text;
  }

  // ------------------- 保存记录 -------------------

  Future<void> _saveRecord() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedWarehouseId == null) {
      _showSnackBar('请至少创建一个仓库');
      return;
    }

    setState(() => _isSaving = true);

    try {
      // 安全解析数量（支持表达式）
      final quantityValue = _evaluateExpression(_quantityController.text.trim());
      if (quantityValue == null || quantityValue <= 0) {
        _showSnackBar('数量无效，请检查输入');
        setState(() => _isSaving = false);
        return;
      }

      final priceValue = double.tryParse(_unitPriceController.text.trim());
      if (priceValue == null || priceValue < 0) {
        _showSnackBar('单价无效，请检查输入');
        setState(() => _isSaving = false);
        return;
      }

      final record = StockMovement(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        partnerName: _partnerController.text.trim(),
        warehouseId: _selectedWarehouseId!,
        type: _selectedType,
        quantity: quantityValue,
        unitPrice: priceValue,
        syncStatus: SyncStatus.pending,
      );

      await DatabaseHelper.instance.insertMovement(record);

      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint('保存记录出错: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        _showSnackBar('保存失败：$e');
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ------------------- OCR 扫描 -------------------

  /// 从相机拍照识别
  Future<void> _scanInvoiceFromCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      _showSnackBar('需要相机权限才能扫描发票');
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _showSnackBar('未检测到可用摄像头');
        return;
      }

      if (!mounted) return;
      final imageFile = await showDialog<XFile>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return _CameraPreviewDialog(cameras: cameras);
        },
      );

      if (imageFile == null || !mounted) return;
      await _processOcrImage(imageFile.path, source: '相机');
    } catch (e) {
      debugPrint('相机扫描出错: $e');
      if (mounted) {
        _showSnackBar('相机扫描出错：$e');
      }
    }
  }

  /// 从相册选择照片识别
  Future<void> _scanInvoiceFromGallery() async {
    // image_picker 会自己处理权限，直接调用即可
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 90,
      );

      if (picked == null || !mounted) return;
      await _processOcrImage(picked.path, source: '相册');
    } catch (e) {
      debugPrint('相册选择出错: $e');
      if (mounted) {
        _showSnackBar('相册选择出错：$e');
      }
    }
  }

  /// 处理 OCR 识别（相机或相册共用）
  Future<void> _processOcrImage(String imagePath, {required String source}) async {
    setState(() => _isScanning = true);

    try {
      final result = await _recognizeInvoice(imagePath);

      if (mounted) {
        setState(() => _isScanning = false);
        if (result != null) {
          _partnerController.text = result.partnerName ?? '';
          if (result.quantity != null) {
            _quantityController.text = result.quantity!;
            _onQuantitySubmitted(result.quantity!);
          }
          if (result.unitPrice != null) {
            _unitPriceController.text = result.unitPrice!;
          }
          _showSnackBar('$source 识别成功，已自动填充部分字段');
        } else {
          _showSnackBar('$source 未能识别到有效信息，请手动输入');
        }
      }
    } catch (e) {
      debugPrint('OCR 识别出错: $e');
      if (mounted) {
        setState(() => _isScanning = false);
        _showSnackBar('识别失败：$e');
      }
    }
  }

  /// OCR 识别 + 正则提取
  ///
  /// 从发票文本中提取：
  /// - 交易对象（收款方 / 交易对象 / 对方）
  /// - 数量（数量 / Qty / Quantity）
  /// - 单价（单价 / Unit Price / Price）
  Future<_OcrResult?> _recognizeInvoice(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.chinese);

    try {
      final recognizedText = await textRecognizer.processImage(inputImage);
      final fullText = recognizedText.text;

      debugPrint('===== OCR 原始文本 =====');
      debugPrint(fullText);
      debugPrint('========================');

      // 提取交易对象
      final partnerPattern = RegExp(
        r'(?:收款方|交易对象|对方)[：:\s]+([^\n]+)',
        caseSensitive: false,
      );
      final partnerMatch = partnerPattern.firstMatch(fullText);
      final partner = partnerMatch?.group(1)?.trim().replaceAll(RegExp(r'[\s\u00A0]+$'), '');

      // 提取数量
      final quantityPattern = RegExp(
        r'(?:数量|Qty|Quantity)[：:\s]+([\d,]+\.?\d*)',
        caseSensitive: false,
      );
      final quantityMatch = quantityPattern.firstMatch(fullText);
      final quantity = quantityMatch?.group(1)?.replaceAll(',', '');

      // 提取单价
      final unitPricePattern = RegExp(
        r'(?:单价|Unit Price|Price)[：:\s]+[¥￥]?\s*([\d,]+\.?\d*)',
        caseSensitive: false,
      );
      final unitPriceMatch = unitPricePattern.firstMatch(fullText);
      final unitPrice = unitPriceMatch?.group(1)?.replaceAll(',', '');

      return _OcrResult(
        partnerName: partner,
        quantity: quantity,
        unitPrice: unitPrice,
      );
    } on Exception catch (e) {
      debugPrint('ML Kit 识别异常: $e');
      // 将异常转换为可理解的错误信息
      if (e.toString().contains('TextRecognizer')) {
        throw Exception('OCR 引擎初始化失败，请确保设备已下载中文语言包且内存充足');
      }
      rethrow;
    } finally {
      await textRecognizer.close();
    }
  }

  // ------------------- UI -------------------

  @override
  Widget build(BuildContext context) {
    final hasWarehouse = _warehouses.isNotEmpty && _selectedWarehouseId != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('新建库存移动记录'),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ───── 目标仓库确认 ─────
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.warehouse,
                                  color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                '目标仓库',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (!hasWarehouse)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.orange.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded,
                                      color: Colors.orange.shade800),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      '当前没有可用仓库，请先在主页添加仓库后再录入记录。',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            DropdownButtonFormField<String>(
                              initialValue: _selectedWarehouseId,
                              decoration: const InputDecoration(
                                labelText: '选择仓库',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 14),
                              ),
                              items: _warehouses.map((w) {
                                return DropdownMenuItem(
                                  value: w.id,
                                  child: Text(w.name),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() => _selectedWarehouseId = value);
                              },
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return '请选择目标仓库';
                                }
                                return null;
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ───── 入库/出库切换开关 ─────
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.swap_horiz,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            '操作类型',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const Spacer(),
                          SegmentedButton<MovementType>(
                            segments: const [
                              ButtonSegment(
                                value: MovementType.inbound,
                                label: Text('入库'),
                                icon: Icon(Icons.arrow_downward, size: 18),
                              ),
                              ButtonSegment(
                                value: MovementType.outbound,
                                label: Text('出库'),
                                icon: Icon(Icons.arrow_upward, size: 18),
                              ),
                            ],
                            selected: {_selectedType},
                            onSelectionChanged: (set) {
                              setState(() => _selectedType = set.first);
                            },
                            style: SegmentedButton.styleFrom(
                              selectedBackgroundColor:
                                  _selectedType == MovementType.inbound
                                      ? Colors.green.shade100
                                      : Colors.red.shade100,
                              selectedForegroundColor:
                                  _selectedType == MovementType.inbound
                                      ? Colors.green.shade900
                                      : Colors.red.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ───── 识别方式选择 ─────
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (_isScanning || _isSaving || !hasWarehouse)
                              ? null
                              : _scanInvoiceFromCamera,
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('拍照识别'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: (_isScanning || _isSaving || !hasWarehouse)
                              ? null
                              : _scanInvoiceFromGallery,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('相册识别'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ───── 表单字段 ─────
                  TextFormField(
                    controller: _partnerController,
                    decoration: const InputDecoration(
                      labelText: '交易对象',
                      hintText: '如：某某超市、供应商 A',
                      prefixIcon: Icon(Icons.business),
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '请输入交易对象';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _quantityController,
                          decoration: const InputDecoration(
                            labelText: '数量(kg)',
                            hintText: '支持 146+92+131',
                            prefixIcon: Icon(Icons.format_list_numbered),
                            border: OutlineInputBorder(),
                          ),
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: _onQuantitySubmitted,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请输入数量';
                            }
                            final parsed = _evaluateExpression(value.trim());
                            if (parsed == null || parsed <= 0) {
                              return '请输入正数';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _unitPriceController,
                          decoration: const InputDecoration(
                            labelText: '单价（元）',
                            hintText: '如：12.50',
                            prefixIcon: Icon(Icons.attach_money),
                            border: OutlineInputBorder(),
                          ),
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          textInputAction: TextInputAction.done,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请输入单价';
                            }
                            final number = double.tryParse(value.trim());
                            if (number == null || number < 0) {
                              return '请输入有效金额';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 动态总金额
                  ValueListenableBuilder(
                    valueListenable: _quantityController,
                    builder: (_, __, ___) => ValueListenableBuilder(
                      valueListenable: _unitPriceController,
                      builder: (_, __, ___) {
                        final qty =
                            double.tryParse(_quantityController.text.trim()) ?? 0;
                        final price =
                            double.tryParse(_unitPriceController.text.trim()) ?? 0;
                        final total = qty * price;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.teal.shade200),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '总金额',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.teal,
                                ),
                              ),
                              Text(
                                '¥${total.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ───── 保存按钮 ─────
                  ElevatedButton.icon(
                    onPressed: (_isSaving || _isScanning || !hasWarehouse)
                        ? null
                        : _saveRecord,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(_isSaving ? '保存中…' : '保存记录'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 识别中遮罩
          if (_isScanning)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      '正在识别发票…',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────
// 相机预览弹窗（独立 StatefulWidget，正确管理生命周期）
// ───────────────────────────────────────────────

class _CameraPreviewDialog extends StatefulWidget {
  final List<CameraDescription> cameras;

  const _CameraPreviewDialog({required this.cameras});

  @override
  State<_CameraPreviewDialog> createState() => _CameraPreviewDialogState();
}

class _CameraPreviewDialogState extends State<_CameraPreviewDialog> {
  CameraController? _controller;
  bool _isReady = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final controller = CameraController(
        widget.cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => widget.cameras.first,
        ),
        // 使用 medium 分辨率以减少内存占用，避免低端设备闪退
        ResolutionPreset.medium,
        enableAudio: false, // 不启用音频，避免申请麦克风权限
      );

      _controller = controller;
      await controller.initialize();

      if (mounted) {
        setState(() => _isReady = true);
      }
    } catch (e) {
      debugPrint('相机初始化失败: $e');
      if (mounted) {
        setState(() => _error = e.toString());
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final image = await _controller!.takePicture();
      if (mounted) {
        Navigator.of(context).pop(image);
      }
    } catch (e) {
      debugPrint('拍照失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 相机预览或加载/错误状态
          if (_error != null)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    '相机初始化失败\n$_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            )
          else if (_isReady && _controller != null)
            CameraPreview(_controller!)
          else
            const Center(child: CircularProgressIndicator()),

          // 顶部关闭按钮
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),

          // 底部拍照按钮
          if (_isReady)
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: FloatingActionButton.large(
                  backgroundColor: Colors.white,
                  onPressed: _takePicture,
                  child: const Icon(Icons.camera, color: Colors.black, size: 36),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// OCR 识别结果临时封装
class _OcrResult {
  final String? partnerName;
  final String? quantity;
  final String? unitPrice;

  _OcrResult({this.partnerName, this.quantity, this.unitPrice});
}
