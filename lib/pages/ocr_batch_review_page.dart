import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../models/order.dart';
import '../models/stock_movement.dart';
import '../services/ocr_service.dart';
import 'add_order_item_page.dart';

/// 一张手写账识别出多笔单据时的逐笔审核页。
class OcrBatchReviewPage extends StatefulWidget {
  final List<OcrOrder> orders;
  final String warehouseId;
  final List<String> globalWarnings;

  const OcrBatchReviewPage({
    super.key,
    required this.orders,
    required this.warehouseId,
    this.globalWarnings = const [],
  });

  @override
  State<OcrBatchReviewPage> createState() => _OcrBatchReviewPageState();
}

class _OcrBatchReviewPageState extends State<OcrBatchReviewPage> {
  late final List<bool> _done;

  @override
  void initState() {
    super.initState();
    _done = List<bool>.filled(widget.orders.length, false);
  }

  MovementType _movementType(String value) => switch (value) {
        'outbound' => MovementType.outbound,
        'supply' => MovementType.supply,
        _ => MovementType.inbound,
      };

  String _typeLabel(MovementType type) => switch (type) {
        MovementType.inbound => '入库',
        MovementType.outbound => '出库',
        MovementType.supply => '进货',
      };

  List<String> _missingFields(OcrOrder order) {
    final missing = <String>[];
    if (order.parsedDate() == null) missing.add('日期');
    if (order.partnerName.trim().isEmpty) missing.add('交易对象');
    if (order.items.isEmpty) missing.add('货物明细');
    if (order.items.any((item) => item.itemName.trim().isEmpty)) {
      missing.add('品名');
    }
    if (order.items.any((item) => item.quantity <= 0)) missing.add('重量');
    if (order.items.any((item) => item.unitPrice <= 0)) missing.add('单价');
    if (order.fees
        .any((fee) => fee.feeName.trim().isEmpty || fee.amount <= 0)) {
      missing.add('费用');
    }
    return missing.toSet().toList();
  }

  String? _orderRemark(OcrOrder order) {
    final parts = <String>{
      if (order.remark?.trim().isNotEmpty == true) order.remark!.trim(),
      ...widget.globalWarnings,
      ...order.warnings,
    }.where((text) => text.trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join('；');
  }

  Future<void> _edit(int index) async {
    final ocr = widget.orders[index];
    final partnerController =
        TextEditingController(text: ocr.partnerName.trim());
    DateTime? selectedDate = ocr.parsedDate();
    var selectedType = _movementType(ocr.type);
    String? validationMessage;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('核对第 ${index + 1} 笔基本信息'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: partnerController,
                  decoration: const InputDecoration(
                    labelText: '交易对象 *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<MovementType>(
                  initialValue: selectedType,
                  decoration: const InputDecoration(
                    labelText: '单据类型',
                    border: OutlineInputBorder(),
                  ),
                  items: MovementType.values
                      .map((type) => DropdownMenuItem(
                            value: type,
                            child: Text(_typeLabel(type)),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) selectedType = value;
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(
                    selectedDate == null
                        ? '请选择日期 *'
                        : '${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}',
                  ),
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: selectedDate ?? now,
                      firstDate: DateTime(2020),
                      lastDate: now,
                    );
                    if (picked != null && dialogContext.mounted) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
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
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (partnerController.text.trim().isEmpty) {
                  setDialogState(() => validationMessage = '请填写交易对象');
                  return;
                }
                if (selectedDate == null) {
                  setDialogState(() => validationMessage = '请选择单据日期');
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('下一步核对明细'),
            ),
          ],
        ),
      ),
    );

    final partnerName = partnerController.text.trim();
    partnerController.dispose();
    if (confirmed != true || selectedDate == null || !mounted) return;

    final date = selectedDate!;
    final order = Order(
      partnerName: partnerName,
      warehouseId: widget.warehouseId,
      type: selectedType,
      timestamp:
          DateTime(date.year, date.month, date.day).millisecondsSinceEpoch,
      remark: _orderRemark(ocr),
    );
    await DatabaseHelper.instance.insertOrder(order);
    if (!mounted) return;

    final normalizedItems = ocr.normalizedItems(isFormal: false);
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddOrderItemPage(
          order: order,
          existingItems: normalizedItems.asMap().entries.map((entry) {
            final item = entry.value;
            return OrderItem(
              orderId: order.id,
              itemName: item.itemName,
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              grossWeight: item.grossWeight,
              tareWeight: item.tareWeight,
              totalPieces: item.totalPieces,
              deliveryPerson: item.deliveryPerson,
              sortOrder: entry.key,
              itemNumber: entry.key + 1,
              pieceNumber: item.pieceNumber,
              itemRemark: item.itemRemark,
            );
          }).toList(),
          existingFees: ocr.fees.asMap().entries.map((entry) {
            final fee = entry.value;
            return OrderFee(
              orderId: order.id,
              feeName: fee.feeName,
              amount: fee.amount,
              sortOrder: entry.key,
            );
          }).toList(),
          returnToPrevious: true,
        ),
      ),
    );

    if (saved != true) {
      await DatabaseHelper.instance.deleteOrder(order.id);
      return;
    }
    if (mounted) setState(() => _done[index] = true);
  }

  @override
  Widget build(BuildContext context) {
    final completed = _done.where((value) => value).length;
    return Scaffold(
      appBar: AppBar(title: Text('OCR 批量审核（${widget.orders.length} 笔）')),
      body: Column(
        children: [
          if (widget.globalWarnings.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Text(
                widget.globalWarnings.join('；'),
                style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: widget.orders.length,
              itemBuilder: (context, index) {
                final order = widget.orders[index];
                final missing = _missingFields(order);
                final warnings = order.warnings;
                final details = StringBuffer(
                    '${order.items.length} 项货物，${order.fees.length} 项费用');
                if (missing.isNotEmpty) {
                  details.write('\n待填写：${missing.join('、')}');
                }
                if (warnings.isNotEmpty) {
                  details.write('\n⚠ ${warnings.join('；')}');
                }
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(
                      '${order.dateHint ?? '日期待填写'}  '
                      '${order.partnerName.trim().isEmpty ? '交易对象待填写' : order.partnerName}',
                    ),
                    subtitle: Text(details.toString()),
                    isThreeLine: missing.isNotEmpty || warnings.isNotEmpty,
                    trailing: _done[index]
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : const Icon(Icons.chevron_right),
                    onTap: _done[index] ? null : () => _edit(index),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: completed == widget.orders.length
                    ? () => Navigator.pop(context, true)
                    : null,
                icon: const Icon(Icons.done_all),
                label: Text('完成（$completed/${widget.orders.length}）'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
