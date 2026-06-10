import 'dart:io';
import 'package:flutter/material.dart';
import '../data/database_helper.dart';
import '../models/order.dart';
import '../models/stock_movement.dart';
import 'add_order_item_page.dart';

/// 主单据详情页
class OrderDetailPage extends StatefulWidget {
  final String orderId;
  const OrderDetailPage({super.key, required this.orderId});

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  OrderDetail? _detail;
  String _warehouseName = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await DatabaseHelper.instance.getOrderDetail(widget.orderId);
    if (d.order == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final whs = await DatabaseHelper.instance.getAllWarehouses();
    final wh = whs.where((w) => w.id == d.order.warehouseId).firstOrNull;
    if (mounted) {
      setState(() {
        _detail = d;
        _warehouseName = wh?.name ?? '未知仓库';
        _loading = false;
      });
    }
  }

  String _fmt(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    final p = (int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${p(dt.month)}-${p(dt.day)} ${p(dt.hour)}:${p(dt.minute)}';
  }

  Widget _badge(String label, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: c, width: 1.5)),
    child: Text(label, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.bold)),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(title: const Text('单据详情')), body: const Center(child: CircularProgressIndicator()));
    if (_detail == null) return Scaffold(appBar: AppBar(title: const Text('单据详情')), body: const Center(child: Text('单据不存在')));

    final o = _detail!.order;
    final isInbound = o.type == MovementType.inbound;

    return Scaffold(
      appBar: AppBar(title: Text(o.partnerName), actions: [
        if (!o.isDeleted) ...[
          IconButton(icon: const Icon(Icons.add), tooltip: '编辑明细', onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AddOrderItemPage(order: o, existingItems: _detail!.items, existingFees: _detail!.fees),
            ));
            _load();
          }),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _voidOrder();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('作废', style: TextStyle(color: Colors.red))),
            ],
            icon: const Icon(Icons.edit_note, color: Colors.teal),
          ),
        ],
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // 已作废标记
        if (o.isDeleted)
          Container(margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red, width: 2)),
            child: Column(children: [
              const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.cancel, color: Colors.red, size: 22), SizedBox(width: 8), Text('此单据已作废', style: TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold))]),
              if (o.voidReason != null) Text('原因：${o.voidReason}', style: TextStyle(color: Colors.red.shade700, fontSize: 14)),
            ])),
        // 头部
        Card(
          color: isInbound ? Colors.green.shade50 : o.type == MovementType.outbound ? Colors.red.shade50 : Colors.orange.shade50,
          child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: isInbound ? Colors.green : o.type == MovementType.outbound ? Colors.red : Colors.orange, borderRadius: BorderRadius.circular(20)),
                child: Text(isInbound ? '入库单' : o.type == MovementType.outbound ? '出库单' : '进货单', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
              if (o.isDeleted) ...[const SizedBox(width: 12), Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(20)), child: const Text('已作废', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)))],
            ]),
            const SizedBox(height: 12),
            Text('¥${(_detail!.totalAmount).toStringAsFixed(2)}', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: isInbound ? Colors.green.shade800 : o.type == MovementType.outbound ? Colors.red.shade800 : Colors.orange.shade800)),
            const Text('总金额', style: TextStyle(fontSize: 14, color: Colors.grey)),
          ])),
        ),
        const SizedBox(height: 16),
        // 基本信息
        _section('基本信息'), _card([
          _row('流水号', o.id, mono: true), _row('日期', _fmt(o.timestamp)),
          _row('仓库', _warehouseName), _row('客户', o.partnerName, bold: true),
          if (o.remark != null) _row('备注', o.remark!),
          _row('同步', '', badge: _badge(o.syncStatus.name == 'synced' ? '已同步' : o.syncStatus.name == 'pending' ? '未同步' : o.syncStatus.name, o.syncStatus.name == 'synced' ? Colors.green : Colors.orange)),
        ]),
        const SizedBox(height: 12),
        // 货物明细
        _section('货物明细（${_detail!.items.length} 项）'),
        ..._detail!.items.asMap().entries.map((e) => Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: Colors.teal.shade100, child: Text('${e.key + 1}', style: TextStyle(color: Colors.teal.shade800))),
            title: Text(e.value.itemName, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('净${e.value.quantity.toStringAsFixed(1)}kg × ¥${e.value.unitPrice.toStringAsFixed(2)}/吨'),
              if (e.value.grossWeight > 0) Text('毛${e.value.grossWeight.toStringAsFixed(1)}kg 扣${e.value.tareWeight.toStringAsFixed(1)}kg', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              if (e.value.deliveryPerson != null) Text('送货：${e.value.deliveryPerson}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              if (e.value.imagePath != null && File(e.value.imagePath!).existsSync())
                GestureDetector(
                  onTap: () => showDialog(context: context, builder: (_) => Dialog.fullscreen(child: InteractiveViewer(child: Image.file(File(e.value.imagePath!))))),
                  child: const Text('📷 查看照片', style: TextStyle(fontSize: 11, color: Colors.teal)),
                ),
            ]),
            trailing: Text('¥${e.value.amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        )),
        if (_detail!.items.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4, bottom: 12), child: Text('货物合计：¥${_detail!.totalItemAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal))),
        const SizedBox(height: 12),
        // 额外费用
        if (_detail!.fees.isNotEmpty) ...[
          _section('额外费用（${_detail!.fees.length} 项）'),
          ..._detail!.fees.map((f) => Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              leading: const Icon(Icons.attach_money, color: Colors.orange),
              title: Text(f.feeName),
              subtitle: f.remark != null ? Text(f.remark!) : null,
              trailing: Text('¥${f.amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          )),
          Padding(padding: const EdgeInsets.only(top: 4, bottom: 12), child: Text('费用合计：¥${_detail!.totalFeeAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14, color: Colors.orange))),
          const SizedBox(height: 12),
        ],
        // 总计
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('单据总计', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text('¥${_detail!.totalAmount.toStringAsFixed(2)}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
          ])),
        const SizedBox(height: 40),
      ]),
    );
  }

  Widget _section(String t) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey)));
  Widget _card(List<Widget> children) => Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16), child: Column(children: children)));
  Widget _row(String label, String value, {bool bold = false, bool mono = false, Widget? badge}) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
      SizedBox(width: 70, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
      Expanded(child: Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w600 : null, fontSize: mono ? 11 : 14, fontFamily: mono ? 'monospace' : null))),
      if (badge != null) badge,
    ]));
  }

  Future<void> _voidOrder() async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('确认作废'), content: Text('确定要作废单据"${_detail!.order.partnerName}"吗？'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('确认作废'))],
    ));
    if (confirmed == true) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final ts = now > _detail!.order.timestamp ? now : _detail!.order.timestamp + 1;
      await DatabaseHelper.instance.updateOrder(_detail!.order.copyWith(
        timestamp: ts, isDeleted: true, syncStatus: SyncStatus.pending, voidReason: null,
      ));
      _load();
    }
  }
}
