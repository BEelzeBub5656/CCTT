import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/database_helper.dart';
import '../models/order.dart';
import '../models/stock_movement.dart';
import '../services/sync_service.dart';
import 'add_order_item_page.dart';

/// 主单据详情页（凭证风格，与旧版 RecordDetailPage 统一）
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
    late final OrderDetail d;
    try {
      d = await DatabaseHelper.instance.getOrderDetail(widget.orderId);
    } catch (_) {
      if (mounted) {
        setState(() {
          _detail = null;
          _loading = false;
        });
      }
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

  String get _formattedTime {
    final date = DateTime.fromMillisecondsSinceEpoch(_detail!.order.timestamp);
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(date);
  }

  MaterialColor get _typeColor {
    switch (_detail!.order.type) {
      case MovementType.inbound:
        return Colors.green;
      case MovementType.outbound:
        return Colors.red;
      case MovementType.supply:
        return Colors.orange;
    }
  }

  String get _typeLabel {
    switch (_detail!.order.type) {
      case MovementType.inbound:
        return '入库单';
      case MovementType.outbound:
        return '出库单';
      case MovementType.supply:
        return '进货单';
    }
  }

  IconData get _typeIcon {
    switch (_detail!.order.type) {
      case MovementType.inbound:
        return Icons.arrow_downward;
      case MovementType.outbound:
        return Icons.arrow_upward;
      case MovementType.supply:
        return Icons.inventory;
    }
  }

  // ───── 同步状态标签 ─────
  Widget _buildSyncStatusBadge(SyncStatus status) {
    Color color;
    String text;
    switch (status) {
      case SyncStatus.synced:
        color = Colors.green;
        text = '已同步';
        break;
      case SyncStatus.syncing:
        color = Colors.blue;
        text = '正在同步';
        break;
      case SyncStatus.failed:
        color = Colors.red;
        text = '同步失败';
        break;
      case SyncStatus.pending:
        color = Colors.orange;
        text = '未同步';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
          appBar: AppBar(title: const Text('单据详情')),
          body: const Center(child: CircularProgressIndicator()));
    }
    if (_detail == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('单据详情')),
          body: const Center(child: Text('单据不存在')));
    }

    final o = _detail!.order;

    return Scaffold(
      appBar: AppBar(
        title: const Text('单据详情'),
        actions: [
          if (!o.isDeleted) ...[
            IconButton(
                icon: const Icon(Icons.add),
                tooltip: '编辑明细',
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AddOrderItemPage(
                        order: o,
                        existingItems: _detail!.items,
                        existingFees: _detail!.fees),
                  ));
                  _load();
                }),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'delete') _voidOrder();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'delete',
                    child: Text('作废', style: TextStyle(color: Colors.red))),
              ],
              icon: const Icon(Icons.edit_note, color: Colors.teal),
            ),
          ],
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // ───── 已作废标记 ─────
        if (o.isDeleted)
          Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red, width: 2)),
              child: Column(children: [
                const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cancel, color: Colors.red, size: 22),
                      SizedBox(width: 8),
                      Text('此单据已作废',
                          style: TextStyle(
                              color: Colors.red,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                    ]),
                if (o.voidReason != null && o.voidReason!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('原因：${o.voidReason}',
                      style:
                          TextStyle(color: Colors.red.shade700, fontSize: 14)),
                ],
              ])),

        // ───── 头部概览卡片 ─────
        _buildHeaderCard(),
        const SizedBox(height: 16),

        // ───── 留档照片 ─────
        ..._detail!.items
            .where((it) =>
                it.imagePath != null && File(it.imagePath!).existsSync())
            .expand((it) => [
                  _buildPhotoCard(context, it),
                  const SizedBox(height: 16),
                ]),

        // ───── 基本信息 ─────
        _buildSectionTitle('基本信息'),
        _buildInfoCard(children: [
          _buildInfoRow(label: '流水号', value: o.id, mono: true),
          _buildInfoRow(label: '交易时间', value: _formattedTime),
          _buildInfoRow(label: '仓库', value: _warehouseName),
          _buildInfoRow(
              label: '单据类型',
              value: _typeLabel,
              valueColor: _typeColor,
              isHighlight: true),
          _buildInfoRow(label: '交易对象', value: o.partnerName),
          if (o.remark != null && o.remark!.isNotEmpty)
            _buildInfoRow(label: '备注', value: o.remark!, muted: false),
          _buildInfoRow(
              label: '同步状态', customValue: _buildSyncStatusBadge(o.syncStatus)),
          _buildInfoRow(
              label: '结清状态',
              customValue: GestureDetector(
                onTap: () => _toggleSettled(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: o.isSettled
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: o.isSettled ? Colors.green : Colors.orange,
                        width: 1.5),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(o.isSettled ? Icons.check_circle : Icons.pending,
                        size: 16,
                        color: o.isSettled ? Colors.green : Colors.orange),
                    const SizedBox(width: 6),
                    Text(o.isSettled ? '已结清' : '未结清',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: o.isSettled
                                ? Colors.green.shade800
                                : Colors.orange.shade800)),
                  ]),
                ),
              )),
        ]),
        const SizedBox(height: 16),

        // ───── 货物明细 ─────
        _buildSectionTitle('货物明细（${_detail!.items.length} 项）'),
        _buildInfoCard(children: [
          ..._detail!.items.asMap().entries.map((e) {
            final it = e.value;
            return GestureDetector(
              onTap: () => _showItemDetail(it),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: Colors.teal.shade100,
                          borderRadius: BorderRadius.circular(14)),
                      child: Text('${e.key + 1}',
                          style: TextStyle(
                              color: Colors.teal.shade800,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(it.itemName,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(
                                '净${it.quantity.toStringAsFixed(1)}kg × ¥${it.unitPrice.toStringAsFixed(2)}/吨',
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey.shade700)),
                            if (it.grossWeight > 0)
                              Text(
                                  '毛${it.grossWeight.toStringAsFixed(1)}kg / 扣${it.tareWeight.toStringAsFixed(1)}kg',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                            if (it.deliveryPerson != null)
                              Text('送货人：${it.deliveryPerson}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                          ]),
                    ),
                    Text('¥${it.amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            );
          }),
          if (_detail!.items.isNotEmpty) ...[
            const Divider(height: 24),
            _buildInfoRow(
                label: '货物合计',
                value: '¥${_detail!.totalItemAmount.toStringAsFixed(2)}',
                isHighlight: true,
                valueColor: Colors.teal),
          ],
        ]),
        const SizedBox(height: 16),

        // ───── 额外费用 ─────
        if (_detail!.fees.isNotEmpty) ...[
          _buildSectionTitle('额外费用（${_detail!.fees.length} 项）'),
          _buildInfoCard(children: [
            ..._detail!.fees.map((f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    const Icon(Icons.attach_money,
                        size: 20, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(f.feeName, style: const TextStyle(fontSize: 14)),
                          if (f.remark != null)
                            Text(f.remark!,
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade600)),
                        ])),
                    Text('¥${f.amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ]),
                )),
            const Divider(height: 24),
            _buildInfoRow(
                label: '费用合计',
                value: '¥${_detail!.totalFeeAmount.toStringAsFixed(2)}',
                isHighlight: true,
                valueColor: Colors.orange),
          ]),
          const SizedBox(height: 16),
        ],

        // ───── 金额明细 ─────
        _buildSectionTitle('金额明细'),
        _buildInfoCard(children: [
          _buildInfoRow(
              label: '货物金额',
              value: '¥${_detail!.totalItemAmount.toStringAsFixed(2)}'),
          if (_detail!.fees.isNotEmpty)
            _buildInfoRow(
                label: '额外费用',
                value: '¥${_detail!.totalFeeAmount.toStringAsFixed(2)}'),
          const Divider(height: 24),
          _buildInfoRow(
              label: '单据总计',
              value: '¥${_detail!.totalAmount.toStringAsFixed(2)}',
              isHighlight: true,
              valueColor: Colors.teal),
        ]),
        const SizedBox(height: 32),
      ]),
    );
  }

  // ───── 头部概览卡片 ─────
  Widget _buildHeaderCard() {
    final o = _detail!.order;
    return Card(
      elevation: 2,
      color: _typeColor.shade50,
      child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                    color: _typeColor, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_typeIcon, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Text(_typeLabel,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ]),
              ),
              if (o.isDeleted) ...[
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(20)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.cancel, color: Colors.white, size: 18),
                    SizedBox(width: 6),
                    Text('已作废',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ]),
                ),
              ],
            ]),
            const SizedBox(height: 16),
            Text('¥${_detail!.totalAmount.toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: _typeColor.shade800)),
            const SizedBox(height: 4),
            Text('总金额',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
          ])),
    );
  }

  // ───── 留档照片卡片 ─────
  Widget _buildPhotoCard(BuildContext context, OrderItem item) {
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(children: [
            Icon(Icons.camera_alt_outlined,
                size: 18, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text('留档照片 — ${item.itemName}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700)),
          ]),
        ),
        GestureDetector(
          onTap: () => showDialog(
              context: context,
              builder: (_) => Dialog.fullscreen(
                    child: Stack(fit: StackFit.expand, children: [
                      InteractiveViewer(
                          child: Image.file(File(item.imagePath!),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Center(
                                  child: Icon(Icons.broken_image, size: 64)))),
                      Positioned(
                          top: MediaQuery.of(context).padding.top + 8,
                          right: 16,
                          child: CircleAvatar(
                              backgroundColor: Colors.black54,
                              child: IconButton(
                                  icon: const Icon(Icons.close,
                                      color: Colors.white),
                                  onPressed: () =>
                                      Navigator.of(context).pop()))),
                    ]),
                  )),
          child: Image.file(File(item.imagePath!),
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (_, __, ___) => Container(
                  height: 200,
                  color: Colors.grey.shade100,
                  child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.broken_image,
                        size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text('照片无法加载',
                        style: TextStyle(color: Colors.grey.shade500)),
                  ])))),
        ),
        Padding(
            padding: const EdgeInsets.all(8),
            child: Text('点击照片可全屏查看',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500))),
      ]),
    );
  }

  // ───── 分组标题 ─────
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(title,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700)),
    );
  }

  // ───── 信息卡片 ─────
  Widget _buildInfoCard({required List<Widget> children}) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }

  // ───── 单行信息 ─────
  Widget _buildInfoRow({
    required String label,
    String? value,
    Widget? customValue,
    Color? valueColor,
    bool isHighlight = false,
    bool muted = false,
    bool mono = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(
                  fontSize: 14,
                  color: muted ? Colors.grey.shade500 : Colors.grey.shade700,
                )),
          ),
          if (customValue != null)
            customValue
          else
            Expanded(
              child: Text(value ?? '',
                  style: TextStyle(
                    fontSize: isHighlight ? 17 : 15,
                    fontWeight:
                        isHighlight ? FontWeight.w600 : FontWeight.normal,
                    fontFamily: mono ? 'monospace' : null,
                    color: muted
                        ? Colors.grey.shade500
                        : (valueColor ?? Colors.black87),
                  )),
            ),
        ],
      ),
    );
  }

  // ───── 货物明细弹窗 ─────
  void _showItemDetail(OrderItem item) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(item.itemName,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _dialogRow('净重', '${item.quantity.toStringAsFixed(1)} kg'),
                    _dialogRow(
                        '单价', '¥${item.unitPrice.toStringAsFixed(2)} / 吨'),
                    _dialogRow('金额', '¥${item.amount.toStringAsFixed(2)}'),
                    if (item.grossWeight > 0) ...[
                      const Divider(),
                      _dialogRow(
                          '毛重', '${item.grossWeight.toStringAsFixed(1)} kg'),
                      _dialogRow(
                          '扣皮', '${item.tareWeight.toStringAsFixed(1)} kg'),
                      _dialogRow('计算净重',
                          '${item.calculatedNetWeight.toStringAsFixed(1)} kg'),
                    ],
                    if (item.totalPieces != null)
                      _dialogRow('件数', '${item.totalPieces} 件'),
                    if (item.deliveryPerson != null)
                      _dialogRow('送货人', item.deliveryPerson!),
                  ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('关闭'))
              ],
            ));
  }

  Widget _dialogRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(
              width: 70,
              child: Text(label,
                  style: const TextStyle(color: Colors.grey, fontSize: 13))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ]),
      );

  // ───── 结清切换 ─────
  Future<void> _toggleSettled() async {
    final o = _detail!.order;
    if (o.isDeleted || o.isSettled) return;
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('确认结清'),
              content: const Text('确认该笔款项已结清？\n结清后不可撤销。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: TextButton.styleFrom(foregroundColor: Colors.green),
                    child: const Text('确认已结清')),
              ],
            ));
    if (ok != true) return;
    final ts = o.timestamp + 1;
    await DatabaseHelper.instance.updateOrder(o.copyWith(
      timestamp: ts,
      isSettled: true,
      syncStatus: SyncStatus.pending,
    ));
    _autoSync();
    _load();
  }

  // ───── 作废 ─────
  Future<void> _voidOrder() async {
    final controller = TextEditingController();
    String? errorText;
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('确认作废'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('确定要作废单据"${_detail!.order.partnerName}"吗？'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: '作废原因',
                  hintText: '请输入作废原因',
                  border: const OutlineInputBorder(),
                  errorText: errorText,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) {
                  setDialogState(() => errorText = '作废原因不能为空');
                  return;
                }
                Navigator.pop(ctx, value);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('确认作废'),
            ),
          ],
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (reason == null || reason.isEmpty) return;

    final ts = _detail!.order.timestamp + 1;
    await DatabaseHelper.instance.updateOrder(_detail!.order.copyWith(
      timestamp: ts,
      isDeleted: true,
      syncStatus: SyncStatus.pending,
      voidReason: reason,
    ));
    _autoSync();
    _load();
  }

  Future<void> _autoSync() async {
    try {
      await SyncService.syncPendingRecords();
      await Future.delayed(const Duration(milliseconds: 2000));
      await SyncService.pullSnapshot();
    } catch (_) {}
  }
}
