import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../data/database_helper.dart';
import '../models/order.dart';
import '../models/stock_movement.dart';
import '../models/warehouse.dart';
import '../services/ocr_service.dart';
import 'add_order_item_page.dart';

/// 新建主单据页（仓库/日期/类型/客户 + OCR 拍照识别）
class AddOrderPage extends StatefulWidget {
  const AddOrderPage({super.key});

  @override
  State<AddOrderPage> createState() => _AddOrderPageState();
}

class _AddOrderPageState extends State<AddOrderPage> {
  final _partnerController = TextEditingController();
  final _remarkController = TextEditingController();
  List<Warehouse> _warehouses = [];
  String? _selectedWarehouseId;
  MovementType _selectedType = MovementType.inbound;
  DateTime _selectedDate = DateTime.now();
  bool _isSettled = false;
  bool _isSaving = false;

  // OCR
  List<OcrItem>? _ocrItems;
  List<OcrFee>? _ocrFees;
  bool _isOcrLoading = false;
  int _ocrResultCount = 0;

  @override
  void initState() {
    super.initState();
    _loadWarehouses();
  }

  Future<void> _loadWarehouses() async {
    final warehouses = await DatabaseHelper.instance.getAllWarehouses();
    if (mounted) setState(() => _warehouses = warehouses);
  }

  Color _typeColor(MovementType t) {
    switch (t) {
      case MovementType.inbound: return Colors.green;
      case MovementType.outbound: return Colors.red;
      case MovementType.supply: return Colors.orange;
    }
  }

  String _typeLabel(MovementType t) {
    switch (t) {
      case MovementType.inbound: return '入库';
      case MovementType.outbound: return '出库';
      case MovementType.supply: return '进货';
    }
  }

  // ═══════════════════ OCR 拍照/选图 ═══════════════════

  Future<void> _takePhotoForOcr() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) _showMsg('需要相机权限');
      return;
    }
    setState(() => _isOcrLoading = true);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _showMsg('未检测到相机');
        return;
      }
      final controller = CameraController(cameras.first, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      if (!mounted) return;
      final image = await showDialog<XFile>(
        context: context,
        builder: (_) => _CameraDialog(controller: controller),
      );
      controller.dispose();
      if (image != null) await _processOcrImage(image);
    } catch (e) {
      _showMsg('拍照失败');
    } finally {
      if (mounted) setState(() => _isOcrLoading = false);
    }
  }

  Future<void> _pickFromGalleryForOcr() async {
    final status = await Permission.photos.request();
    if (!status.isGranted) {
      if (mounted) _showMsg('需要相册权限');
      return;
    }
    setState(() => _isOcrLoading = true);
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1920, maxHeight: 1920);
      if (image != null) await _processOcrImage(image);
    } catch (e) {
      _showMsg('选图失败');
    } finally {
      if (mounted) setState(() => _isOcrLoading = false);
    }
  }

  Future<void> _processOcrImage(XFile image) async {
    // 拷贝到临时目录
    final dir = await getApplicationDocumentsDirectory();
    final photoDir = Directory('${dir.path}/ocr_temp');
    if (!photoDir.existsSync()) photoDir.createSync(recursive: true);
    final tempPath = '${photoDir.path}/ocr_${const Uuid().v4()}.jpg';
    await File(image.path).copy(tempPath);
    final file = File(tempPath);

    try {
      final result = await OcrService.recognize(file);
      if (!mounted) return;

      if (!result.success || result.orders.isEmpty) {
        _showMsg('未识别到单据信息，请重试或手动输入');
        return;
      }

      final ocrOrder = result.orders.first;
      final confirmed = await _showOcrConfirmDialog(ocrOrder);
      if (confirmed == true && mounted) {
        setState(() {
          _partnerController.text = ocrOrder.partnerName;
          _ocrItems = ocrOrder.items;
          _ocrFees = ocrOrder.fees;
          _ocrResultCount = ocrOrder.items.length;
        });
      }
    } on OcrException catch (e) {
      if (mounted) _showMsg(e.message);
    } catch (e) {
      if (mounted) _showMsg('OCR 识别失败: $e');
    } finally {
      // 清理临时文件
      try { file.deleteSync(); } catch (_) {}
    }
  }

  Future<bool?> _showOcrConfirmDialog(OcrOrder ocrOrder) {
    final typeLabel = ocrOrder.type == 'outbound' ? '出库' : ocrOrder.type == 'supply' ? '进货' : '入库';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.document_scanner, color: Colors.teal), SizedBox(width: 8),
          Expanded(child: Text('OCR 识别结果', style: TextStyle(fontSize: 16))),
        ]),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 基本信息
            _infoRow('交易对象', ocrOrder.partnerName, bold: true),
            _infoRow('单据类型', typeLabel),
            if (ocrOrder.dateHint != null) _infoRow('日期提示', ocrOrder.dateHint!),
            // 货物
            if (ocrOrder.items.isNotEmpty) ...[
              const Divider(),
              Text('货物明细（${ocrOrder.items.length} 项）', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ...ocrOrder.items.map((it) => Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: Text('• ${it.itemName}  ${it.quantity.toStringAsFixed(1)}kg × ¥${it.unitPrice.toStringAsFixed(2)}/吨',
                    style: const TextStyle(fontSize: 13)),
              )),
            ],
            // 费用
            if (ocrOrder.fees.isNotEmpty) ...[
              const Divider(),
              Text('额外费用（${ocrOrder.fees.length} 项）', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ...ocrOrder.fees.map((f) => Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Text('• ${f.feeName}: ¥${f.amount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13)),
              )),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('重新拍照')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: Colors.teal), child: const Text('确认使用')),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
      Expanded(child: Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, fontSize: 14))),
    ]),
  );

  void _showMsg(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ═══════════════════ 保存 ═══════════════════

  Future<void> _save() async {
    if (_selectedWarehouseId == null) {
      _showMsg('请选择仓库');
      return;
    }
    final partner = _partnerController.text.trim();
    if (partner.isEmpty) {
      _showMsg('请输入客户名称');
      return;
    }

    setState(() => _isSaving = true);

    final ts = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day,
        DateTime.now().hour, DateTime.now().minute, DateTime.now().second)
        .millisecondsSinceEpoch;

    // 自动合并检测
    final existing = await DatabaseHelper.instance.getAllOrders();
    Order? mergedOrder;
    for (final o in existing) {
      if (o.partnerName == partner &&
          o.type == _selectedType &&
          o.warehouseId == _selectedWarehouseId &&
          _sameDay(o.timestamp, ts) &&
          !o.isDeleted) {
        mergedOrder = o;
        break;
      }
    }

    final order = mergedOrder ??
        Order(
          partnerName: partner,
          warehouseId: _selectedWarehouseId!,
          type: _selectedType,
          timestamp: ts,
          isSettled: _isSettled,
          remark: _remarkController.text.trim().isEmpty ? null : _remarkController.text.trim(),
        );

    if (mergedOrder != null) {
      final mo = mergedOrder;
      await DatabaseHelper.instance.updateOrder(mo.copyWith(
        remark: order.remark ?? mo.remark,
        syncStatus: SyncStatus.pending,
      ));

      if (mounted) {
        setState(() => _isSaving = false);
        final existingItems = await DatabaseHelper.instance.getOrderItems(mo.id);
        final existingFees = await DatabaseHelper.instance.getOrderFees(mo.id);
        // 合并 OCR 结果
        final allItems = [...existingItems, ..._ocrItemsToOrderItems(mo.id)];
        final allFees = [...existingFees, ..._ocrFeesToOrderFees(mo.id)];

        if (!mounted) return;
        await showDialog(context: context, builder: (ctx) => AlertDialog(
          title: const Text('自动合并'),
          content: Text('新建记录已自动合并到"$partner"的现有单据中。\n\n该单据目前有 ${allItems.length} 项货物。'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('确定'))],
        ));
        if (mounted) {
          Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => AddOrderItemPage(order: mo, existingItems: allItems, existingFees: allFees),
          ));
        }
      }
    } else {
      await DatabaseHelper.instance.insertOrder(order);
      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => AddOrderItemPage(
            order: order,
            existingItems: _ocrItemsToOrderItems(order.id),
            existingFees: _ocrFeesToOrderFees(order.id),
          ),
        ));
      }
    }
  }

  List<OrderItem> _ocrItemsToOrderItems(String orderId) {
    if (_ocrItems == null || _ocrItems!.isEmpty) return [];
    return _ocrItems!.map((o) => OrderItem(
      orderId: orderId,
      itemName: o.itemName,
      quantity: o.quantity,
      unitPrice: o.unitPrice,
      grossWeight: o.grossWeight,
      tareWeight: o.tareWeight,
      totalPieces: o.totalPieces,
      deliveryPerson: o.deliveryPerson,
      sortOrder: _ocrItems!.indexOf(o),
    )).toList();
  }

  List<OrderFee> _ocrFeesToOrderFees(String orderId) {
    if (_ocrFees == null || _ocrFees!.isEmpty) return [];
    return _ocrFees!.map((f) => OrderFee(
      orderId: orderId,
      feeName: f.feeName,
      amount: f.amount,
      sortOrder: _ocrFees!.indexOf(f),
    )).toList();
  }

  bool _sameDay(int a, int b) {
    final da = DateTime.fromMillisecondsSinceEpoch(a);
    final db = DateTime.fromMillisecondsSinceEpoch(b);
    return da.year == db.year && da.month == db.month && da.day == db.day;
  }

  @override
  void dispose() {
    _partnerController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  // ═══════════════════ UI ═══════════════════

  @override
  Widget build(BuildContext context) {
    final hasWarehouse = _warehouses.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('新建单据')),
      body: Form(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          // 仓库
          Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
            const Text('目标仓库', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const Spacer(),
            SizedBox(width: 180, child: DropdownButtonFormField<String>(
              value: _selectedWarehouseId,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
              hint: const Text('选择仓库'),
              items: _warehouses.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() => _selectedWarehouseId = v),
            )),
          ]))),
          const SizedBox(height: 12),
          // 日期
          Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
            const Text('日期', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.edit_calendar, size: 18),
              label: Text('${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context, initialDate: _selectedDate, firstDate: DateTime(2020), lastDate: DateTime.now(),
                  builder: (context, child) => Localizations.override(context: context, locale: const Locale('zh'), child: child!),
                );
                if (picked != null) setState(() => _selectedDate = picked);
              },
            ),
          ]))),
          const SizedBox(height: 12),
          // 类型
          Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
            const Text('类型', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const Spacer(),
            ...MovementType.values.map((t) => Padding(
              padding: const EdgeInsets.only(left: 4),
              child: ChoiceChip(
                label: Text(_typeLabel(t), style: TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                selected: _selectedType == t,
                selectedColor: _typeColor(t),
                onSelected: (_) => setState(() => _selectedType = t),
              ),
            )),
          ]))),
          const SizedBox(height: 12),
          // 客户
          Card(child: Padding(padding: const EdgeInsets.all(12), child: TextFormField(
            controller: _partnerController,
            decoration: const InputDecoration(labelText: '客户名称', hintText: '客户/供应商名称', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
          ))),
          const SizedBox(height: 12),
          // ══════ OCR 拍照识别 ══════
          Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.document_scanner, color: Colors.teal),
              const SizedBox(width: 8),
              const Text('OCR 拍照识别', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_ocrResultCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.green)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.check, size: 14, color: Colors.green), const SizedBox(width: 4),
                    Text('已识别 $_ocrResultCount 项', style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
                  ]),
                ),
            ]),
            const SizedBox(height: 4),
            Text('拍照上传手写单据，自动识别客户和货物明细', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 10),
            if (_isOcrLoading)
              const Center(child: Padding(padding: EdgeInsets.all(12), child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Text('正在识别...', style: TextStyle(color: Colors.grey)),
              ])))
            else
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _takePhotoForOcr,
                    icon: const Icon(Icons.camera_alt, size: 16),
                    label: const Text('拍照', style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickFromGalleryForOcr,
                    icon: const Icon(Icons.photo_library, size: 16),
                    label: const Text('相册', style: TextStyle(fontSize: 13)),
                  ),
                ),
              ]),
          ]))),
          const SizedBox(height: 12),
          // 备注 + 结清
          Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
            TextFormField(controller: _remarkController, decoration: const InputDecoration(labelText: '备注', hintText: '可选', border: OutlineInputBorder(), prefixIcon: Icon(Icons.notes)), maxLines: 2),
            const SizedBox(height: 8),
            Row(children: [
              const Text('结清', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const Spacer(),
              ChoiceChip(label: Text('未结清', style: TextStyle(color: _isSettled ? null : Colors.orange.shade800, fontWeight: _isSettled ? FontWeight.normal : FontWeight.bold)), selected: !_isSettled, selectedColor: Colors.orange.shade100, onSelected: (_) => setState(() => _isSettled = false)),
              const SizedBox(width: 6),
              ChoiceChip(label: Text('已结清', style: TextStyle(color: _isSettled ? Colors.green.shade800 : null, fontWeight: _isSettled ? FontWeight.bold : FontWeight.normal)), selected: _isSettled, selectedColor: Colors.green.shade100, onSelected: (_) async {
                final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('确认结清'), content: const Text('确认已结清？'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认'))]));
                if (ok == true && mounted) setState(() => _isSettled = true);
              }),
            ]),
          ]))),
          const SizedBox(height: 20),
          // 保存
          SizedBox(height: 48, child: ElevatedButton.icon(
            onPressed: (_isSaving || !hasWarehouse) ? null : _save,
            icon: _isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.arrow_forward),
            label: const Text('下一步：添加货物明细'),
          )),
        ]),
      ),
    );
  }
}

// ───── OCR 相机弹窗 ─────
class _CameraDialog extends StatelessWidget {
  final CameraController controller;
  const _CameraDialog({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Stack(fit: StackFit.expand, children: [
        CameraPreview(controller),
        Positioned(bottom: 40, left: 0, right: 0, child: Center(
          child: FloatingActionButton(
            heroTag: 'capture_ocr',
            onPressed: () async {
              try {
                final image = await controller.takePicture();
                if (context.mounted) Navigator.of(context).pop(image);
              } catch (_) { Navigator.of(context).pop(); }
            },
            child: const Icon(Icons.camera),
          ),
        )),
        Positioned(top: 40, right: 20, child: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 32),
          onPressed: () => Navigator.of(context).pop(),
        )),
      ]),
    );
  }
}
