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
import '../services/sync_service.dart';
import 'order_detail_page.dart';

/// 添加明细/费用页面（在 Order 创建后编辑）
class AddOrderItemPage extends StatefulWidget {
  final Order order;
  final List<OrderItem>? existingItems;
  final List<OrderFee>? existingFees;

  const AddOrderItemPage(
      {super.key, required this.order, this.existingItems, this.existingFees});

  @override
  State<AddOrderItemPage> createState() => _AddOrderItemPageState();
}

class _AddOrderItemPageState extends State<AddOrderItemPage> {
  final _itemNameController = TextEditingController();
  final _quantityController = TextEditingController();
  final _unitPriceController = TextEditingController();
  final _grossWeightController = TextEditingController();
  final _tareWeightController = TextEditingController(text: '0');
  final _totalPiecesController = TextEditingController();
  final _deliveryPersonController = TextEditingController();
  final _pieceNumberController = TextEditingController();
  final _itemRemarkController = TextEditingController();
  final _feeNameController = TextEditingController();
  final _feeAmountController = TextEditingController();
  final _feeRemarkController = TextEditingController();

  List<OrderItem> _items = [];
  List<OrderFee> _fees = [];
  String? _capturedImagePath;
  bool _isSaving = false;
  bool _showGrossWeight = false;
  bool _itemsExpanded = false;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.existingItems ?? []);
    _fees = List.from(widget.existingFees ?? []);
  }

  double get _netWeight {
    final gross = double.tryParse(_grossWeightController.text) ?? 0;
    final tare = double.tryParse(_tareWeightController.text) ?? 0;
    return gross - tare;
  }

  double get _itemAmount {
    final qty = double.tryParse(_quantityController.text) ?? 0;
    final price = double.tryParse(_unitPriceController.text) ?? 0;
    return (qty / 1000) * price;
  }

  double get _totalItemAmount => _items.fold(0.0, (s, i) => s + i.amount);
  double get _totalFeeAmount => _fees.fold(0.0, (s, f) => s + f.amount);
  double get _totalGrossWeight => _items.fold(
      0.0,
      (sum, item) =>
          sum + (item.grossWeight > 0 ? item.grossWeight : item.quantity));
  double get _totalTareWeight =>
      _items.fold(0.0, (sum, item) => sum + item.tareWeight);
  double get _totalNetWeight =>
      _items.fold(0.0, (sum, item) => sum + item.quantity);

  Future<void> _addItem() async {
    final name = _itemNameController.text.trim();
    if (name.isEmpty) {
      _showMsg('请输入货物名称');
      return;
    }
    final qty = double.tryParse(_quantityController.text);
    if (qty == null || qty <= 0) {
      _showMsg('净重必须大于 0');
      return;
    }
    final price = double.tryParse(_unitPriceController.text);
    if (price == null || price <= 0) {
      _showMsg('请输入有效单价');
      return;
    }

    final item = OrderItem(
      orderId: widget.order.id,
      itemName: name,
      quantity: _grossWeightController.text.isNotEmpty ? _netWeight : qty,
      unitPrice: price,
      grossWeight: double.tryParse(_grossWeightController.text) ?? 0,
      tareWeight: double.tryParse(_tareWeightController.text) ?? 0,
      totalPieces: int.tryParse(_totalPiecesController.text),
      deliveryPerson: _deliveryPersonController.text.trim().isEmpty
          ? null
          : _deliveryPersonController.text.trim(),
      imagePath: _capturedImagePath,
      sortOrder: _items.length,
      itemNumber: _items.length + 1,
      pieceNumber: _pieceNumberController.text.trim().isEmpty
          ? null
          : _pieceNumberController.text.trim(),
      itemRemark: _itemRemarkController.text.trim().isEmpty
          ? null
          : _itemRemarkController.text.trim(),
    );

    setState(() {
      _items.add(item);
      _itemNameController.clear();
      _quantityController.clear();
      _unitPriceController.clear();
      _grossWeightController.clear();
      _tareWeightController.text = '0';
      _totalPiecesController.clear();
      _deliveryPersonController.clear();
      _pieceNumberController.clear();
      _itemRemarkController.clear();
      _capturedImagePath = null;
      _showGrossWeight = false;
    });
  }

  Future<void> _addFee() async {
    final name = _feeNameController.text.trim();
    if (name.isEmpty) {
      _showMsg('请输入费用名称');
      return;
    }
    final amount = double.tryParse(_feeAmountController.text);
    if (amount == null || amount <= 0) {
      _showMsg('请输入有效金额');
      return;
    }

    setState(() {
      _fees.add(OrderFee(
        orderId: widget.order.id,
        feeName: name,
        amount: amount,
        remark: _feeRemarkController.text.trim().isEmpty
            ? null
            : _feeRemarkController.text.trim(),
        sortOrder: _fees.length,
      ));
      _feeNameController.clear();
      _feeAmountController.clear();
      _feeRemarkController.clear();
    });
  }

  void _deleteItem(int i) => setState(() => _items.removeAt(i));
  void _deleteFee(int i) => setState(() => _fees.removeAt(i));

  Future<void> _editItem(int index) async {
    final item = _items[index];
    final nameController = TextEditingController(text: item.itemName);
    final quantityController =
        TextEditingController(text: _formatNumber(item.quantity));
    final priceController =
        TextEditingController(text: _formatNumber(item.unitPrice));
    final grossController = item.grossWeight > 0
        ? TextEditingController(text: _formatNumber(item.grossWeight))
        : TextEditingController();
    final tareController =
        TextEditingController(text: _formatNumber(item.tareWeight));
    final pieceController = TextEditingController(text: item.pieceNumber ?? '');
    final remarkController = TextEditingController(text: item.itemRemark ?? '');
    final usesGrossWeight = item.grossWeight > 0;
    String? validationMessage;

    final updatedItem = await showDialog<OrderItem>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final gross = double.tryParse(grossController.text) ?? 0;
          final tare = double.tryParse(tareController.text) ?? 0;
          return AlertDialog(
            title: Text('修改第 ${index + 1} 项'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: '货物名称'),
                  ),
                  const SizedBox(height: 8),
                  if (usesGrossWeight) ...[
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: grossController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration:
                              const InputDecoration(labelText: '毛重 (kg)'),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: tareController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration:
                              const InputDecoration(labelText: '扣皮 (kg)'),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '净重：${_formatNumber(gross - tare)} kg',
                        style: const TextStyle(
                            color: Colors.teal, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ] else
                    TextField(
                      controller: quantityController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: '净重 (kg)'),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: priceController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: '单价 (元/吨)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: pieceController,
                    decoration: const InputDecoration(labelText: '件号（可选）'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: remarkController,
                    decoration: const InputDecoration(labelText: '明细备注（可选）'),
                  ),
                  if (validationMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      validationMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  final price = double.tryParse(priceController.text);
                  final parsedGross = double.tryParse(grossController.text);
                  final parsedTare = double.tryParse(tareController.text) ?? 0;
                  final parsedQuantity =
                      double.tryParse(quantityController.text);
                  if (name.isEmpty) {
                    setDialogState(() => validationMessage = '货物名称不能为空');
                    return;
                  }
                  if (price == null || price <= 0) {
                    setDialogState(() => validationMessage = '请输入有效单价');
                    return;
                  }
                  if (usesGrossWeight &&
                      (parsedGross == null ||
                          parsedGross <= 0 ||
                          parsedTare < 0 ||
                          parsedTare >= parsedGross)) {
                    setDialogState(() => validationMessage = '毛重需大于 0，扣皮需小于毛重');
                    return;
                  }
                  if (!usesGrossWeight &&
                      (parsedQuantity == null || parsedQuantity <= 0)) {
                    setDialogState(() => validationMessage = '净重必须大于 0');
                    return;
                  }

                  final quantity = usesGrossWeight
                      ? parsedGross! - parsedTare
                      : parsedQuantity!;
                  Navigator.pop(
                    dialogContext,
                    OrderItem(
                      id: item.id,
                      orderId: item.orderId,
                      itemName: name,
                      quantity: quantity,
                      unitPrice: price,
                      grossWeight: usesGrossWeight ? parsedGross! : 0.0,
                      tareWeight: usesGrossWeight ? parsedTare : 0.0,
                      totalPieces: item.totalPieces,
                      deliveryPerson: item.deliveryPerson,
                      imagePath: item.imagePath,
                      sortOrder: item.sortOrder,
                      itemNumber: item.itemNumber,
                      pieceNumber: pieceController.text.trim().isEmpty
                          ? null
                          : pieceController.text.trim(),
                      itemRemark: remarkController.text.trim().isEmpty
                          ? null
                          : remarkController.text.trim(),
                    ),
                  );
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );

    nameController.dispose();
    quantityController.dispose();
    priceController.dispose();
    grossController.dispose();
    tareController.dispose();
    pieceController.dispose();
    remarkController.dispose();
    if (updatedItem != null && mounted) {
      setState(() => _items[index] = updatedItem);
    }
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  Future<void> _saveOrder() async {
    setState(() => _isSaving = true);
    try {
      // 删除旧明细/费用，重新写入
      final oldItems =
          await DatabaseHelper.instance.getOrderItems(widget.order.id);
      final oldFees =
          await DatabaseHelper.instance.getOrderFees(widget.order.id);
      for (final item in oldItems) {
        await DatabaseHelper.instance.deleteOrderItem(item.id);
      }
      for (final fee in oldFees) {
        await DatabaseHelper.instance.deleteOrderFee(fee.id);
      }

      for (final item in _items) {
        await DatabaseHelper.instance.insertOrderItem(item);
      }
      for (final fee in _fees) {
        await DatabaseHelper.instance.insertOrderFee(fee);
      }

      // 更新 Order 状态（保持用户选择的日期，+1ms 确保单调递增）
      final ts = widget.order.timestamp + 1;
      await DatabaseHelper.instance.updateOrder(widget.order.copyWith(
        timestamp: ts,
        syncStatus: SyncStatus.pending,
      ));

      if (mounted) {
        _autoSync();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
              builder: (_) => OrderDetailPage(orderId: widget.order.id)),
          (route) => route.isFirst,
        );
      }
    } catch (e) {
      _showMsg('保存失败: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _autoSync() async {
    try {
      await SyncService.syncPendingRecords();
      await Future.delayed(const Duration(milliseconds: 2000));
      await SyncService.pullSnapshot();
    } catch (_) {}
  }

  void _showMsg(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _takePhoto() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) return;
    try {
      final cameras = await availableCameras();
      final controller = CameraController(
          cameras.first, ResolutionPreset.medium,
          enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      final image = await showDialog<XFile>(
        context: context,
        builder: (_) => _CameraDialog(controller: controller),
      );
      controller.dispose();
      if (image != null) await _savePhoto(image);
    } catch (_) {}
  }

  Future<void> _pickFromGallery() async {
    final status = await Permission.photos.request();
    if (!status.isGranted) return;
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
          source: ImageSource.gallery, maxWidth: 1920, maxHeight: 1920);
      if (image != null) await _savePhoto(image);
    } catch (_) {}
  }

  Future<void> _savePhoto(XFile image) async {
    final dir = await getApplicationDocumentsDirectory();
    final photoDir = Directory('${dir.path}/invoice_photos');
    if (!photoDir.existsSync()) photoDir.createSync(recursive: true);
    final tempPath = '${photoDir.path}/temp_${const Uuid().v4()}.jpg';
    await File(image.path).copy(tempPath);
    setState(() => _capturedImagePath = tempPath);
  }

  @override
  void dispose() {
    _itemNameController.dispose();
    _quantityController.dispose();
    _unitPriceController.dispose();
    _grossWeightController.dispose();
    _tareWeightController.dispose();
    _totalPiecesController.dispose();
    _deliveryPersonController.dispose();
    _pieceNumberController.dispose();
    _itemRemarkController.dispose();
    _feeNameController.dispose();
    _feeAmountController.dispose();
    _feeRemarkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('编辑明细 — ${widget.order.partnerName}'),
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(28),
            child: Container(
              padding: const EdgeInsets.only(bottom: 8),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: widget.order.type == MovementType.inbound
                        ? Colors.green.shade50
                        : widget.order.type == MovementType.outbound
                            ? Colors.red.shade50
                            : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: widget.order.type == MovementType.inbound
                            ? Colors.green
                            : widget.order.type == MovementType.outbound
                                ? Colors.red
                                : Colors.orange),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                        widget.order.type == MovementType.inbound
                            ? Icons.arrow_downward
                            : widget.order.type == MovementType.outbound
                                ? Icons.arrow_upward
                                : Icons.inventory,
                        size: 14,
                        color: widget.order.type == MovementType.inbound
                            ? Colors.green.shade800
                            : widget.order.type == MovementType.outbound
                                ? Colors.red.shade800
                                : Colors.orange.shade800),
                    const SizedBox(width: 4),
                    Text(
                        widget.order.type == MovementType.inbound
                            ? '入库单'
                            : widget.order.type == MovementType.outbound
                                ? '出库单'
                                : '进货单',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: widget.order.type == MovementType.inbound
                                ? Colors.green.shade800
                                : widget.order.type == MovementType.outbound
                                    ? Colors.red.shade800
                                    : Colors.orange.shade800)),
                  ]),
                ),
              ]),
            )),
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        // 已添加的明细列表
        if (_items.isNotEmpty) ...[
          Row(children: [
            const Expanded(
              child: Text('货物明细',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            if (_items.length > 8)
              TextButton.icon(
                onPressed: () =>
                    setState(() => _itemsExpanded = !_itemsExpanded),
                icon: Icon(
                    _itemsExpanded ? Icons.expand_less : Icons.expand_more),
                label: Text(_itemsExpanded ? '收起' : '展开 ${_items.length} 项'),
              ),
          ]),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.teal.shade100),
            ),
            child: Text(
              '${_items.length} 件　毛重 ${_formatNumber(_totalGrossWeight)} kg　'
              '扣皮 ${_formatNumber(_totalTareWeight)} kg\n'
              '净重 ${_formatNumber(_totalNetWeight)} kg　'
              '金额 ¥${_totalItemAmount.toStringAsFixed(2)}',
              style: TextStyle(
                height: 1.6,
                color: Colors.teal.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_items.length > 8 && !_itemsExpanded)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '明细已折叠，展开后可逐项修改识别结果。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          if (_items.length <= 8 || _itemsExpanded) ...[
            const SizedBox(height: 8),
            ..._items.asMap().entries.map((e) {
              final item = e.value;
              final weightText = item.grossWeight > 0
                  ? '毛${_formatNumber(item.grossWeight)} - '
                      '皮${_formatNumber(item.tareWeight)} = '
                      '净${_formatNumber(item.quantity)}kg'
                  : '净${_formatNumber(item.quantity)}kg';
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                      child: Text('${item.itemNumber ?? e.key + 1}')),
                  title: Text(
                      '${item.itemName}${item.pieceNumber != null ? ' [${item.pieceNumber}]' : ''}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '$weightText × ¥${_formatNumber(item.unitPrice)}/吨 = ¥${item.amount.toStringAsFixed(2)}'),
                      if (item.itemRemark != null)
                        Text('备注: ${item.itemRemark}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  trailing: SizedBox(
                    width: 80,
                    child: Row(children: [
                      IconButton(
                        tooltip: '修改',
                        icon:
                            const Icon(Icons.edit_outlined, color: Colors.teal),
                        onPressed: () => _editItem(e.key),
                      ),
                      IconButton(
                        tooltip: '删除',
                        icon:
                            const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _deleteItem(e.key),
                      ),
                    ]),
                  ),
                ),
              );
            }),
          ],
          const SizedBox(height: 16),
        ],
        // 添加新明细
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('添加货物',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                        controller: _itemNameController,
                        decoration: const InputDecoration(
                            labelText: '货物名称 *',
                            border: OutlineInputBorder(),
                            isDense: true)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                          child: TextField(
                              controller: _quantityController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: '净重(kg) *',
                                  border: OutlineInputBorder(),
                                  isDense: true),
                              onChanged: (_) => setState(() {}))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: TextField(
                              controller: _unitPriceController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: '单价(元/吨) *',
                                  border: OutlineInputBorder(),
                                  isDense: true),
                              onChanged: (_) => setState(() {}))),
                    ]),
                    if (_showGrossWeight) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: TextField(
                                controller: _grossWeightController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: '毛重(kg)',
                                    border: OutlineInputBorder(),
                                    isDense: true),
                                onChanged: (_) => setState(() {}))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextField(
                                controller: _tareWeightController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: '扣皮(kg)',
                                    border: OutlineInputBorder(),
                                    isDense: true),
                                onChanged: (_) => setState(() {}))),
                      ]),
                      Text('净重：${_netWeight.toStringAsFixed(1)} kg',
                          style: const TextStyle(
                              color: Colors.blue, fontWeight: FontWeight.w600)),
                    ],
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                          child: TextField(
                              controller: _deliveryPersonController,
                              decoration: const InputDecoration(
                                  labelText: '送货人',
                                  border: OutlineInputBorder(),
                                  isDense: true))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: TextField(
                              controller: _totalPiecesController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: '件数',
                                  border: OutlineInputBorder(),
                                  isDense: true))),
                    ]),
                    const SizedBox(height: 8),
                    TextField(
                        controller: _pieceNumberController,
                        decoration: const InputDecoration(
                            labelText: '件号',
                            border: OutlineInputBorder(),
                            isDense: true)),
                    const SizedBox(height: 8),
                    TextField(
                        controller: _itemRemarkController,
                        decoration: const InputDecoration(
                            labelText: '明细备注',
                            border: OutlineInputBorder(),
                            isDense: true)),
                    const SizedBox(height: 8),
                    TextButton(
                        onPressed: () => setState(
                            () => _showGrossWeight = !_showGrossWeight),
                        child: Text(_showGrossWeight ? '隐藏毛重/扣皮' : '展开毛重/扣皮')),
                    if (_capturedImagePath != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                              '已拍照：${_capturedImagePath!.split('/').last}',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey))),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                          child: OutlinedButton.icon(
                              onPressed: _takePhoto,
                              icon: const Icon(Icons.camera, size: 16),
                              label: const Text('拍照',
                                  style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 32)))),
                      const SizedBox(width: 6),
                      Expanded(
                          child: OutlinedButton.icon(
                              onPressed: _pickFromGallery,
                              icon: const Icon(Icons.photo_library, size: 16),
                              label: const Text('相册',
                                  style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 32)))),
                    ]),
                    if (_itemNameController.text.isNotEmpty &&
                        _quantityController.text.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                              '金额：¥${_itemAmount.toStringAsFixed(2)} (${_quantityController.text}÷1000×${_unitPriceController.text})',
                              style: const TextStyle(
                                  color: Colors.teal,
                                  fontWeight: FontWeight.w600))),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                        onPressed: _addItem,
                        icon: const Icon(Icons.add),
                        label: const Text('添加此货物')),
                  ])),
        ),
        // 额外费用
        ..._fees.asMap().entries.map((e) => Card(
              child: ListTile(
                leading: const Icon(Icons.attach_money, color: Colors.orange),
                title: Text(
                    '${e.value.feeName}：¥${e.value.amount.toStringAsFixed(2)}'),
                subtitle: e.value.remark != null ? Text(e.value.remark!) : null,
                trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteFee(e.key)),
              ),
            )),
        if (_fees.isNotEmpty)
          Text('费用合计：¥${_totalFeeAmount.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 14, color: Colors.orange)),
        const SizedBox(height: 8),
        Card(
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('添加费用',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                          flex: 2,
                          child: TextField(
                              controller: _feeNameController,
                              decoration: const InputDecoration(
                                  labelText: '费用名称',
                                  border: OutlineInputBorder(),
                                  isDense: true))),
                      const SizedBox(width: 8),
                      Expanded(
                          flex: 1,
                          child: TextField(
                              controller: _feeAmountController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: '金额',
                                  border: OutlineInputBorder(),
                                  isDense: true))),
                    ]),
                    const SizedBox(height: 6),
                    TextField(
                        controller: _feeRemarkController,
                        decoration: const InputDecoration(
                            labelText: '备注(可选)',
                            border: OutlineInputBorder(),
                            isDense: true)),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                        onPressed: _addFee,
                        icon: const Icon(Icons.add),
                        label: const Text('添加费用')),
                  ])),
        ),
        const SizedBox(height: 8),
        // 总计
        Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(12)),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('单据总计',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(
                      '¥${(_totalItemAmount + _totalFeeAmount).toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal)),
                ])),
        const SizedBox(height: 12),
        SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: (_isSaving || _items.isEmpty) ? null : _saveOrder,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(_items.isEmpty ? '请至少添加一条货物明细' : '完成并保存单据'),
            )),
        const SizedBox(height: 40),
      ]),
    );
  }
}

// 相机拍照弹窗（复用）
class _CameraDialog extends StatelessWidget {
  final CameraController controller;
  const _CameraDialog({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Stack(fit: StackFit.expand, children: [
        CameraPreview(controller),
        Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingActionButton(
                heroTag: 'capture_item',
                onPressed: () async {
                  try {
                    final image = await controller.takePicture();
                    if (context.mounted) Navigator.of(context).pop(image);
                  } catch (_) {
                    if (context.mounted) Navigator.of(context).pop();
                  }
                },
                child: const Icon(Icons.camera),
              ),
            )),
        Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 32),
              onPressed: () => Navigator.of(context).pop(),
            )),
      ]),
    );
  }
}
