import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../models/order.dart';
import '../models/stock_movement.dart';
import '../models/warehouse.dart';
import 'add_order_item_page.dart';
import 'order_detail_page.dart';

/// 新建主单据页（仅录入客户/仓库/类型/日期，明细在下一页添加）
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

  Future<void> _save() async {
    if (_selectedWarehouseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请选择仓库')));
      return;
    }
    final partner = _partnerController.text.trim();
    if (partner.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入客户名称')));
      return;
    }

    setState(() => _isSaving = true);

    final now = DateTime.now().millisecondsSinceEpoch;
    final ts = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day,
        DateTime.now().hour, DateTime.now().minute, DateTime.now().second).millisecondsSinceEpoch;

    // 自动合并：同一客户+同一日期+同一仓库 → 已有 order 则复用
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

    final order = mergedOrder ?? Order(
      partnerName: partner,
      warehouseId: _selectedWarehouseId!,
      type: _selectedType,
      timestamp: now > ts ? now : ts, // timestamp 单调递增
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
        final items = await DatabaseHelper.instance.getOrderItems(mo.id);
        final fees = await DatabaseHelper.instance.getOrderFees(mo.id);
        await showDialog(context: context, builder: (ctx) => AlertDialog(
          title: const Text('自动合并'),
          content: Text('新建记录已自动合并到"$partner"的现有单据中。\n\n该单据目前有 ${items.length} 项货物。'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('确定'))],
        ));
        if (mounted) {
          Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => AddOrderItemPage(order: mo, existingItems: items, existingFees: fees),
          ));
        }
      }
    } else {
      await DatabaseHelper.instance.insertOrder(order);
      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => AddOrderItemPage(order: order),
        ));
      }
    }
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
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                value: _selectedWarehouseId,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
                hint: const Text('选择仓库'),
                items: _warehouses.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => setState(() => _selectedWarehouseId = v),
              ),
            ),
          ]))),
          const SizedBox(height: 12),
          // 日期
          Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
            const Text('日期', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.edit_calendar, size: 18),
              label: Text('${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2,'0')}-${_selectedDate.day.toString().padLeft(2,'0')}',
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
