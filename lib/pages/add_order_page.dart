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
import '../theme/app_theme.dart';
import '../widgets/cctt_components.dart';
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            CCTTTheme.space4,
            CCTTTheme.space4,
            CCTTTheme.space4,
            CCTTTheme.space8,
          ),
          children: [
            // OCR 排在第一位：这是最省力的录入方式，理应是默认路径。
            OCRHeroCard(
              onTakePhoto: _takePhotoForOcr,
              onPickGallery: _pickFromGalleryForOcr,
              isProcessing: _isOcrLoading,
              recognizedCount: _ocrResultCount > 0 ? _ocrResultCount : null,
            ),

            const CCTTSectionLabel(label: '或者手动填写'),

            if (!hasWarehouse)
              Container(
                margin: const EdgeInsets.only(bottom: CCTTTheme.space3),
                padding: const EdgeInsets.all(CCTTTheme.space3),
                decoration: BoxDecoration(
                  color: CCTTTheme.statusPending.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(CCTTTheme.radiusMedium),
                  border: Border.all(
                    color: CCTTTheme.statusPending.withValues(alpha: 0.4),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: CCTTTheme.statusPending,
                    ),
                    SizedBox(width: CCTTTheme.space2),
                    Expanded(
                      child: Text(
                        '还没有仓库，先回上一页建一个仓库才能保存单据',
                        style: TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),

            // 类型：三个并列的大按钮，比 ChoiceChip 更好点，也更好扫
            _fieldLabel('单据类型'),
            Row(
              children: MovementType.values.map((t) {
                final selected = _selectedType == t;
                final color = CCTTTheme.typeColor(t);
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: t == MovementType.values.last
                          ? 0
                          : CCTTTheme.space2,
                    ),
                    child: InkWell(
                      onTap: () => setState(() => _selectedType = t),
                      borderRadius:
                          BorderRadius.circular(CCTTTheme.radiusMedium),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          vertical: CCTTTheme.space3,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? color.withValues(alpha: 0.1)
                              : Colors.white,
                          borderRadius:
                              BorderRadius.circular(CCTTTheme.radiusMedium),
                          border: Border.all(
                            color: selected ? color : CCTTTheme.neutral300,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              CCTTTheme.typeIcon(t),
                              size: 22,
                              color: selected ? color : CCTTTheme.neutral500,
                            ),
                            const SizedBox(height: CCTTTheme.space1 + 2),
                            Text(
                              CCTTTheme.typeLabel(t),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color:
                                    selected ? color : CCTTTheme.neutral700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: CCTTTheme.space4),
            _fieldLabel('目标仓库'),
            DropdownButtonFormField<String>(
              initialValue: _selectedWarehouseId,
              isExpanded: true,
              decoration: const InputDecoration(
                hintText: '选择仓库',
                prefixIcon: Icon(Icons.warehouse_outlined, size: 20),
              ),
              items: _warehouses
                  .map((w) => DropdownMenuItem(
                        value: w.id,
                        child: Text(w.name, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedWarehouseId = v),
            ),

            const SizedBox(height: CCTTTheme.space4),
            _fieldLabel('日期'),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  builder: (context, child) => Localizations.override(
                    context: context,
                    locale: const Locale('zh'),
                    child: child!,
                  ),
                );
                if (picked != null) setState(() => _selectedDate = picked);
              },
              borderRadius: BorderRadius.circular(CCTTTheme.radiusMedium),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: CCTTTheme.space3,
                  vertical: CCTTTheme.space3 + 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(CCTTTheme.radiusMedium),
                  border: Border.all(color: CCTTTheme.neutral300),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.event_outlined,
                      size: 20,
                      color: CCTTTheme.neutral700,
                    ),
                    const SizedBox(width: CCTTTheme.space3),
                    Text(
                      '${_selectedDate.year}-'
                      '${_selectedDate.month.toString().padLeft(2, '0')}-'
                      '${_selectedDate.day.toString().padLeft(2, '0')}',
                      style: CCTTTheme.numeric(size: 15),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: CCTTTheme.neutral500,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: CCTTTheme.space4),
            _fieldLabel('客户名称'),
            TextFormField(
              controller: _partnerController,
              decoration: const InputDecoration(
                hintText: '客户 / 供应商名称',
                prefixIcon: Icon(Icons.person_outline, size: 20),
              ),
            ),

            const SizedBox(height: CCTTTheme.space4),
            _fieldLabel('备注', optional: true),
            TextFormField(
              controller: _remarkController,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: '需要记一笔的其他信息',
              ),
            ),

            const CCTTSectionLabel(label: '结清状态'),
            Row(
              children: [
                Expanded(
                  child: _settleOption(
                    label: '未结清',
                    color: CCTTTheme.statusPending,
                    selected: !_isSettled,
                    onTap: () => setState(() => _isSettled = false),
                  ),
                ),
                const SizedBox(width: CCTTTheme.space2),
                Expanded(
                  child: _settleOption(
                    label: '已结清',
                    color: CCTTTheme.statusSynced,
                    selected: _isSettled,
                    onTap: _confirmSettled,
                  ),
                ),
              ],
            ),
            if (_isSettled)
              const Padding(
                padding: EdgeInsets.only(top: CCTTTheme.space2),
                child: Text(
                  '结清之后不能改回未结清',
                  style: TextStyle(fontSize: 12, color: CCTTTheme.neutral700),
                ),
              ),

            const SizedBox(height: CCTTTheme.space8),
            CCTTPrimaryButton(
              label: '下一步：添加货物明细',
              icon: Icons.arrow_forward,
              isLoading: _isSaving,
              onPressed: hasWarehouse ? _save : null,
            ),
          ],
        ),
      ),
    );
  }

  /// 表单标签放在输入框外面而不是用 floatingLabel：
  /// 填到一半时标签还在原位，不会因为聚焦而缩到边框上。
  Widget _fieldLabel(String text, {bool optional = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CCTTTheme.space2),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: CCTTTheme.neutral700,
            ),
          ),
          if (optional) ...[
            const SizedBox(width: CCTTTheme.space1 + 2),
            const Text(
              '选填',
              style: TextStyle(fontSize: 12, color: CCTTTheme.neutral500),
            ),
          ],
        ],
      ),
    );
  }

  Widget _settleOption({
    required String label,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CCTTTheme.radiusMedium),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: CCTTTheme.space3),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(CCTTTheme.radiusMedium),
          border: Border.all(
            color: selected ? color : CCTTTheme.neutral300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? color : CCTTTheme.neutral700,
            ),
          ),
        ),
      ),
    );
  }

  /// 结清不可逆，所以要一次确认。文案直接说清后果，而不是问「确认吗」。
  Future<void> _confirmSettled() async {
    if (_isSettled) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('标记为已结清？'),
        content: const Text('结清之后这张单据不能再改回未结清。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认结清'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) setState(() => _isSettled = true);
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
