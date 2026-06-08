import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../data/database_helper.dart';
import '../models/stock_movement.dart';
import '../models/warehouse.dart';

/// 新建/修改库存移动记录页面（毛纺厂专用版）
///
/// 核心计重逻辑：
///   净重 = 毛重(grossWeight) - 扣皮(tareWeight)
///   总金额 = (净重 kg / 1000) × 单价(元/吨)
///
class AddRecordPage extends StatefulWidget {
  const AddRecordPage({super.key});

  @override
  State<AddRecordPage> createState() => _AddRecordPageState();
}

class _AddRecordPageState extends State<AddRecordPage> {
  final _formKey = GlobalKey<FormState>();
  final _partnerController = TextEditingController();
  final _colorController = TextEditingController();
  final _varietyController = TextEditingController();
  final _deliveryPersonController = TextEditingController();
  final _grossWeightController = TextEditingController();
  final _tareWeightController = TextEditingController();
  final _totalPiecesController = TextEditingController();
  final _unitPriceController = TextEditingController();

  List<Warehouse> _warehouses = [];
  String? _selectedWarehouseId;
  MovementType _selectedType = MovementType.inbound;
  DateTime _selectedDate = DateTime.now();

  bool _isSaving = false;
  bool _isScanning = false;
  bool _isSettled = false;
  final _remarkController = TextEditingController();
  String? _capturedImagePath; // 拍照/选图后保存的本地照片路径

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
    _colorController.dispose();
    _varietyController.dispose();
    _deliveryPersonController.dispose();
    _grossWeightController.dispose();
    _tareWeightController.dispose();
    _totalPiecesController.dispose();
    _unitPriceController.dispose();
    super.dispose();
  }

  // ───── 净重联动计算 ─────

  /// 从当前毛重和扣皮控制器实时计算净重
  double get _currentNetWeight {
    final gross = double.tryParse(_grossWeightController.text.trim()) ?? 0;
    final tare = double.tryParse(_tareWeightController.text.trim()) ?? 0;
    return gross - tare;
  }

  /// 当前总金额（实时）
  double get _currentTotalAmount {
    final price = double.tryParse(_unitPriceController.text.trim()) ?? 0;
    return (_currentNetWeight / 1000) * price;
  }

  // ───── 保存记录 ─────

  Future<void> _saveRecord() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedWarehouseId == null) {
      _showSnackBar('请至少创建一个仓库');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final grossWeight = double.parse(_grossWeightController.text.trim());
      final tareWeight = double.tryParse(_tareWeightController.text.trim()) ?? 0;
      final netWeight = grossWeight - tareWeight;

      if (netWeight <= 0) {
        _showSnackBar('净重必须大于 0，请检查毛重和扣皮');
        setState(() => _isSaving = false);
        return;
      }

      final priceValue = double.tryParse(_unitPriceController.text.trim());
      if (priceValue == null || priceValue < 0) {
        _showSnackBar('单价无效，请检查输入');
        setState(() => _isSaving = false);
        return;
      }

      final totalPieces = _totalPiecesController.text.trim().isEmpty
          ? null
          : int.tryParse(_totalPiecesController.text.trim());

      final recordId = const Uuid().v4();

      // 如有留档照片，用 record ID 重命名，避免临时文件名冲突
      String? finalImagePath;
      if (_capturedImagePath != null) {
        try {
          final dir = await getApplicationDocumentsDirectory();
          final photoDir = Directory('${dir.path}/invoice_photos');
          final destFile = File('${photoDir.path}/$recordId.jpg');
          await File(_capturedImagePath!).rename(destFile.path);
          finalImagePath = destFile.path;
        } catch (e) {
          debugPrint('照片重命名失败，保留原路径: $e');
          finalImagePath = _capturedImagePath; // 兜底：保留临时路径
        }
      }

      final record = StockMovement(
        id: recordId,
        timestamp: DateTime(
          _selectedDate.year, _selectedDate.month, _selectedDate.day,
          DateTime.now().hour, DateTime.now().minute, DateTime.now().second,
        ).millisecondsSinceEpoch,
        partnerName: _partnerController.text.trim(),
        warehouseId: _selectedWarehouseId!,
        type: _selectedType,
        quantity: netWeight,
        unitPrice: priceValue,
        syncStatus: SyncStatus.pending,
        color: _colorController.text.trim(),
        variety: _varietyController.text.trim(),
        grossWeight: grossWeight,
        tareWeight: tareWeight,
        totalPieces: totalPieces,
        deliveryPerson: _deliveryPersonController.text.trim().isEmpty
            ? null
            : _deliveryPersonController.text.trim(),
        imagePath: finalImagePath,
        isSettled: _isSettled,
        remark: _remarkController.text.trim().isEmpty ? null : _remarkController.text.trim(),
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

  // ───── 极速连录 ─────

  /// 弹出极速连录 BottomSheet，连续录入多个毛重
  Future<void> _showRapidEntrySheet() async {
    final result = await showModalBottomSheet<_RapidEntryResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _RapidEntryBottomSheet(),
    );

    if (result != null && mounted) {
      _grossWeightController.text = result.totalWeight.toStringAsFixed(2);
      _totalPiecesController.text = result.count.toString();
      setState(() {}); // 刷新净重和总金额
    }
  }

  // ───── 拍照存档 ─────

  /// 从相机拍照留档
  Future<void> _scanInvoiceFromCamera() async {
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        _showSnackBar('请在系统设置中授予相机权限');
        return;
      }

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
      await _savePhotoToStorage(imageFile.path, source: '相机');
    } catch (e, stackTrace) {
      debugPrint('拍照异常: $e');
      debugPrint('StackTrace: $stackTrace');
      if (mounted) {
        _showSnackBar('拍照异常：$e');
      }
    }
  }

  /// 从相册选择照片留档
  Future<void> _scanInvoiceFromGallery() async {
    try {
      final status = await Permission.photos.request();
      if (!status.isGranted) {
        _showSnackBar('请在系统设置中授予相册权限');
        return;
      }

      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 90,
      );

      if (picked == null || !mounted) return;
      await _savePhotoToStorage(picked.path, source: '相册');
    } catch (e, stackTrace) {
      debugPrint('相册选择异常: $e');
      debugPrint('StackTrace: $stackTrace');
      if (mounted) {
        _showSnackBar('相册选择异常：$e');
      }
    }
  }

  /// 将照片拷贝到 app 私有存储目录，留档备用
  Future<void> _savePhotoToStorage(String sourcePath,
      {required String source}) async {
    setState(() => _isScanning = true);

    try {
      final dir = await getApplicationDocumentsDirectory();
      final photoDir = Directory('${dir.path}/invoice_photos');
      if (!await photoDir.exists()) {
        await photoDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final destPath = '${photoDir.path}/temp_$timestamp.jpg';
      await File(sourcePath).copy(destPath);

      if (mounted) {
        setState(() {
          _isScanning = false;
          _capturedImagePath = destPath;
        });
        _showSnackBar('$source 照片已保存，请继续填写信息');
      }
    } catch (e) {
      debugPrint('保存照片失败: $e');
      if (mounted) {
        setState(() => _isScanning = false);
        _showSnackBar('保存照片失败：$e');
      }
    }
  }

  // ───── UI ─────

  @override
  Widget build(BuildContext context) {
    final hasWarehouse = _warehouses.isNotEmpty && _selectedWarehouseId != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('新建出库单'),
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
                  _buildWarehouseCard(hasWarehouse),
                  const SizedBox(height: 16),

                  // ───── 日期选择 ─────
                  _buildDateCard(),
                  const SizedBox(height: 16),

                  // ───── 入库/出库/进货切换 ─────
                  _buildTypeCard(),
                  const SizedBox(height: 16),

                  // ───── 识别方式 ─────
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (_isScanning || _isSaving || !hasWarehouse)
                              ? null
                              : _scanInvoiceFromCamera,
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('拍照留档'),
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
                          label: const Text('相册选择'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ───── 交易对象 ─────
                  TextFormField(
                    controller: _partnerController,
                    decoration: const InputDecoration(
                      labelText: '交易对象',
                      hintText: '如：某某工厂、客户 A',
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

                  // ───── 颜色 + 品种 ─────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _colorController,
                          decoration: const InputDecoration(
                            labelText: '颜色',
                            hintText: '如：白、黑、灰',
                            prefixIcon: Icon(Icons.color_lens_outlined),
                            border: OutlineInputBorder(),
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _varietyController,
                          decoration: const InputDecoration(
                            labelText: '品种',
                            hintText: '如：涤纶、羊毛、棉',
                            prefixIcon: Icon(Icons.grass_outlined),
                            border: OutlineInputBorder(),
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ───── 送货人 ─────
                  TextFormField(
                    controller: _deliveryPersonController,
                    decoration: const InputDecoration(
                      labelText: '送货人',
                      hintText: '如：张三',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),

                  // ───── 毛重 + 扣皮 ─────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 毛重（带极速连录按钮）
                      Expanded(
                        flex: 5,
                        child: TextFormField(
                          controller: _grossWeightController,
                          decoration: InputDecoration(
                            labelText: '毛重(kg)',
                            hintText: '地磅读数',
                            prefixIcon:
                                const Icon(Icons.fitness_center_outlined),
                            border: const OutlineInputBorder(),
                            suffixIcon: TextButton.icon(
                              onPressed: _showRapidEntrySheet,
                              icon: const Icon(Icons.speed, size: 18),
                              label: const Text('极速连录'),
                              style: TextButton.styleFrom(
                                foregroundColor:
                                    Theme.of(context).colorScheme.primary,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8),
                              ),
                            ),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          textInputAction: TextInputAction.next,
                          onChanged: (_) => setState(() {}),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请输入毛重';
                            }
                            if (double.tryParse(value.trim()) == null) {
                              return '请输入数字';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 扣皮
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _tareWeightController,
                          decoration: const InputDecoration(
                            labelText: '扣皮(kg)',
                            hintText: '去皮',
                            prefixIcon:
                                Icon(Icons.remove_circle_outline),
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          textInputAction: TextInputAction.next,
                          onChanged: (_) => setState(() {}),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return null; // 可选，默认 0
                            }
                            if (double.tryParse(value.trim()) == null) {
                              return '请输入数字';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ───── 总件数 + 单价 ─────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _totalPiecesController,
                          decoration: const InputDecoration(
                            labelText: '总件数',
                            hintText: '如：5',
                            prefixIcon:
                                Icon(Icons.inventory_2_outlined),
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return null;
                            }
                            if (int.tryParse(value.trim()) == null) {
                              return '请输入整数';
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
                            labelText: '单价 (元/吨)',
                            hintText: '如：4500',
                            prefixIcon: Icon(Icons.attach_money),
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          textInputAction: TextInputAction.done,
                          onChanged: (_) => setState(() {}),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请输入单价';
                            }
                            if (double.tryParse(value.trim()) == null) {
                              return '请输入数字';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ───── 净重展示（大字，只读） ─────
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.scale,
                                color: Colors.blue.shade800, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              '净重（毛重 - 扣皮）',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.blue.shade800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        AnimatedBuilder(
                          animation: Listenable.merge([
                            _grossWeightController,
                            _tareWeightController,
                          ]),
                          builder: (_, __) {
                            return Text(
                              '${_currentNetWeight.toStringAsFixed(2)} kg',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ───── 总金额展示 ─────
                  AnimatedBuilder(
                    animation: Listenable.merge([
                      _grossWeightController,
                      _tareWeightController,
                      _unitPriceController,
                    ]),
                    builder: (_, __) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.teal.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '总金额',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.teal,
                              ),
                            ),
                            Text(
                              '¥${_currentTotalAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // ───── 备注 ─────
                  TextField(
                    controller: _remarkController,
                    decoration: const InputDecoration(
                      labelText: '备注',
                      hintText: '选填，可记录结算信息等',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.notes),
                    ),
                    maxLines: 2,
                    textInputAction: TextInputAction.newline,
                  ),
                  const SizedBox(height: 16),

                  // ───── 是否结清 ─────
                  Row(children: [
                    const Icon(Icons.account_balance_wallet, color: Colors.teal, size: 20),
                    const SizedBox(width: 8),
                    const Text('是否结清', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    ChoiceChip(
                      label: Text('未结清', style: TextStyle(
                        color: _isSettled ? null : Colors.orange.shade800,
                        fontWeight: _isSettled ? FontWeight.normal : FontWeight.bold,
                      )),
                      selected: !_isSettled,
                      selectedColor: Colors.orange.shade100,
                      onSelected: (_) => setState(() => _isSettled = false),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('已结清', style: TextStyle(
                        color: _isSettled ? Colors.green.shade800 : null,
                        fontWeight: _isSettled ? FontWeight.bold : FontWeight.normal,
                      )),
                      selected: _isSettled,
                      selectedColor: Colors.green.shade100,
                      onSelected: (_) async {
                        // 二次确认
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('确认结清'),
                            content: const Text('确认该笔款项已结清？\n此信息将同步到云端。'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认')),
                            ],
                          ),
                        );
                        if (ok == true && mounted) setState(() => _isSettled = true);
                      },
                    ),
                  ]),
                  const SizedBox(height: 24),

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
                    label: Text(_isSaving ? '保存中…' : '保存单据'),
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

  // ───── 仓库选择卡片 ─────
  Widget _buildWarehouseCard(bool hasWarehouse) {
    return Card(
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
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
    );
  }

  // ───── 操作类型卡片 ─────
  Widget _buildDateCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          const Icon(Icons.calendar_today, color: Colors.teal),
          const SizedBox(width: 8),
          const Text('单据日期', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal)),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.edit_calendar, size: 18),
            label: Text(
              '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
                builder: (context, child) => Localizations.override(
                  context: context,
                  locale: const Locale('zh'),
                  child: child!,
                ),
              );
              if (picked != null) setState(() => _selectedDate = picked);
            },
          ),
        ]),
      ),
    );
  }

  Widget _buildTypeCard() {
    Color typeColor(MovementType t) {
      switch (t) {
        case MovementType.inbound:  return Colors.green;
        case MovementType.outbound: return Colors.red;
        case MovementType.supply:   return Colors.orange;
      }
    }
    String typeLabel(MovementType t) {
      switch (t) {
        case MovementType.inbound:  return '入库';
        case MovementType.outbound: return '出库';
        case MovementType.supply:   return '进货';
      }
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          Icon(Icons.swap_horiz, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          const Text('操作类型', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const Spacer(),
          ...MovementType.values.map((t) => Padding(
            padding: const EdgeInsets.only(left: 4),
            child: ChoiceChip(
              label: Text(typeLabel(t), style: TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
              selected: _selectedType == t,
              selectedColor: typeColor(t),
              onSelected: (_) => setState(() => _selectedType = t),
            ),
          )),
        ]),
      ),
    );
  }
}

// ───────────────────────────────────────────────
// 相机预览弹窗
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
        ResolutionPreset.medium,
        enableAudio: false,
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
      if (mounted) Navigator.of(context).pop(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_error != null)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline,
                      color: Colors.red, size: 48),
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

          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.close,
                  color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),

          if (_isReady)
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: FloatingActionButton.large(
                  backgroundColor: Colors.white,
                  onPressed: _takePicture,
                  child: const Icon(Icons.camera,
                      color: Colors.black, size: 36),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────
// 极速连录 BottomSheet（用于连续录入多个毛重）
// ───────────────────────────────────────────────

/// 极速连录结果
class _RapidEntryResult {
  final double totalWeight;
  final int count;

  const _RapidEntryResult({required this.totalWeight, required this.count});
}

/// 自定义数字键盘 BottomSheet
class _RapidEntryBottomSheet extends StatefulWidget {
  const _RapidEntryBottomSheet();

  @override
  State<_RapidEntryBottomSheet> createState() =>
      _RapidEntryBottomSheetState();
}

class _RapidEntryBottomSheetState extends State<_RapidEntryBottomSheet> {
  final List<double> _weights = [];
  String _input = '';

  double get _totalWeight =>
      _weights.fold(0.0, (sum, w) => sum + w);

  void _onKeyPressed(String key) {
    setState(() {
      if (key == '.') {
        if (!_input.contains('.')) {
          _input = _input.isEmpty ? '0.' : '$_input.';
        }
      } else {
        _input += key;
      }
    });
  }

  void _onBackspace() {
    setState(() {
      if (_input.isNotEmpty) {
        _input = _input.substring(0, _input.length - 1);
      }
    });
  }

  void _onNext() {
    final value = double.tryParse(_input);
    if (value == null || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效的正数重量')),
      );
      return;
    }
    setState(() {
      _weights.add(value);
      _input = '';
    });
  }

  void _onDone() {
    if (_input.isNotEmpty) {
      final value = double.tryParse(_input);
      if (value != null && value > 0) {
        _weights.add(value);
      }
    }
    if (_weights.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(
      _RapidEntryResult(
        totalWeight: _totalWeight,
        count: _weights.length,
      ),
    );
  }

  void _onDeleteItem(int index) {
    setState(() {
      _weights.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    return Container(
      height: media.size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.speed, color: Colors.teal),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '极速连录 — 毛重',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                    label: const Text('取消'),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '共计',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.teal.shade800,
                    ),
                  ),
                  Text(
                    '${_totalWeight.toStringAsFixed(2)} kg（共 ${_weights.length} 件）',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 2,
              child: _weights.isEmpty
                  ? Center(
                      child: Text(
                        '点击下方数字键盘录入毛重',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    )
                  : Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            _weights.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final weight = entry.value;
                          return Chip(
                            avatar: CircleAvatar(
                              backgroundColor: Colors.teal.shade100,
                              child: Text(
                                '${idx + 1}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.teal.shade800,
                                ),
                              ),
                            ),
                            label: Text(
                              '${weight.toStringAsFixed(2)} kg',
                              style: const TextStyle(fontSize: 14),
                            ),
                            deleteIcon:
                                const Icon(Icons.close, size: 18),
                            onDeleted: () => _onDeleteItem(idx),
                            backgroundColor: Colors.grey.shade100,
                          );
                        }).toList(),
                      ),
                    ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '当前输入',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  Text(
                    _input.isEmpty ? '—' : '$_input kg',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: GridView.count(
                        crossAxisCount: 3,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.6,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          ...['7', '8', '9', '4', '5', '6', '1', '2', '3']
                              .map((k) => _buildKeyButton(k)),
                          _buildKeyButton('.'),
                          _buildKeyButton('0'),
                          _buildKeyButton('⌫', onPressed: _onBackspace),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: Column(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _onNext,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                minimumSize:
                                    const Size.fromHeight(0),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(12),
                                ),
                              ),
                              child: const Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add, size: 28),
                                  SizedBox(height: 4),
                                  Text('下一笔',
                                      style: TextStyle(fontSize: 14)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: _onDone,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.teal,
                                minimumSize:
                                    const Size.fromHeight(0),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(12),
                                ),
                              ),
                              child: const Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check, size: 28),
                                  SizedBox(height: 4),
                                  Text('完成',
                                      style: TextStyle(fontSize: 14)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyButton(String label, {VoidCallback? onPressed}) {
    return Material(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed ?? () => _onKeyPressed(label),
        borderRadius: BorderRadius.circular(12),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: label == '⌫' ? 22 : 26,
              fontWeight: FontWeight.w500,
              color: label == '⌫'
                  ? Colors.red.shade700
                  : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}
