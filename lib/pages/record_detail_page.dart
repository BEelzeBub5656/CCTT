import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/stock_movement.dart';

/// 记录详情页
///
/// 以单据凭证风格展示一条 [StockMovement] 的全部信息。
class RecordDetailPage extends StatelessWidget {
  final StockMovement record;
  final String warehouseName;

  const RecordDetailPage({
    super.key,
    required this.record,
    required this.warehouseName,
  });

  String get _formattedTime {
    final date = DateTime.fromMillisecondsSinceEpoch(record.timestamp);
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(date);
  }

  bool get _isInbound => record.type == MovementType.inbound;

  /// 总金额 = (净重 kg / 1000) * 单价(元/吨)
  double get _totalAmount => (record.quantity / 1000) * record.unitPrice;

  /// 根据毛重和扣皮计算出的净重（用于校验）
  double get _calculatedNetWeight => record.grossWeight - record.tareWeight;

  /// 根据状态生成带颜色的文字标签（与主页保持绝对统一）
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
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('单据详情'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ───── 已作废标记 ─────
          if (record.isDeleted)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red, width: 2),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cancel, color: Colors.red, size: 22),
                  SizedBox(width: 8),
                  Text('此记录已作废', style: TextStyle(
                    color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
            ),

          // ───── 头部概览卡片 ─────
          _buildHeaderCard(),
          const SizedBox(height: 16),

          // ───── 留档照片 ─────
          if (record.imagePath != null && File(record.imagePath!).existsSync())
            _buildPhotoCard(context),
          const SizedBox(height: 16),

          // ───── 基本信息 ─────
          _buildSectionTitle('基本信息'),
          _buildInfoCard(children: [
            _buildInfoRow(label: '流水号', value: record.id),
            _buildInfoRow(label: '交易时间', value: _formattedTime),
            _buildInfoRow(label: '仓库', value: warehouseName),
            _buildInfoRow(
              label: '单据类型',
              value: _isInbound ? '入库单' : '出库单',
              valueColor: _isInbound ? Colors.green : Colors.red,
              isHighlight: true,
            ),
            _buildInfoRow(
              label: '同步状态',
              customValue: _buildSyncStatusBadge(record.syncStatus),
            ),
          ]),
          const SizedBox(height: 16),

          // ───── 交易信息 ─────
          _buildSectionTitle('交易信息'),
          _buildInfoCard(children: [
            _buildInfoRow(label: '交易对象', value: record.partnerName),
            _buildInfoRow(
              label: '颜色',
              value: record.color.isEmpty ? '—' : record.color,
              muted: record.color.isEmpty,
            ),
            _buildInfoRow(
              label: '品种',
              value: record.variety.isEmpty ? '—' : record.variety,
              muted: record.variety.isEmpty,
            ),
            _buildInfoRow(
              label: '送货人',
              value: record.deliveryPerson ?? '—',
              muted: record.deliveryPerson == null,
            ),
          ]),
          const SizedBox(height: 16),

          // ───── 重量明细 ─────
          _buildSectionTitle('重量明细'),
          _buildInfoCard(children: [
            _buildInfoRow(
              label: '总件数',
              value: record.totalPieces?.toString() ?? '—',
              muted: record.totalPieces == null,
            ),
            _buildInfoRow(
              label: '毛重',
              value: record.grossWeight > 0
                  ? '${record.grossWeight.toStringAsFixed(2)} kg'
                  : '—',
              muted: record.grossWeight <= 0,
            ),
            _buildInfoRow(
              label: '扣皮（去皮）',
              value: record.tareWeight > 0
                  ? '${record.tareWeight.toStringAsFixed(2)} kg'
                  : '—',
              muted: record.tareWeight <= 0,
            ),
            const Divider(height: 24),
            _buildInfoRow(
              label: '净重',
              value: '${record.quantity.toStringAsFixed(2)} kg',
              isHighlight: true,
            ),
            if (record.grossWeight > 0 && record.tareWeight > 0)
              _buildInfoRow(
                label: '（毛重 - 扣皮校验）',
                value: '${_calculatedNetWeight.toStringAsFixed(2)} kg',
                valueColor: (_calculatedNetWeight - record.quantity).abs() < 0.01
                    ? Colors.green
                    : Colors.orange,
                fontSize: 13,
              ),
          ]),
          const SizedBox(height: 16),

          // ───── 金额明细 ─────
          _buildSectionTitle('金额明细'),
          _buildInfoCard(children: [
            _buildInfoRow(
              label: '单价',
              value: '¥${record.unitPrice.toStringAsFixed(2)} / 吨',
            ),
            _buildInfoRow(
              label: '计算公式',
              value:
                  '(${record.quantity.toStringAsFixed(2)} kg ÷ 1000) × ${record.unitPrice.toStringAsFixed(2)}',
              valueColor: Colors.grey.shade600,
              fontSize: 13,
            ),
            const Divider(height: 24),
            _buildInfoRow(
              label: '总金额',
              value: '¥${_totalAmount.toStringAsFixed(2)}',
              isHighlight: true,
              valueColor: Colors.teal,
            ),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ───── 头部概览卡片 ─────
  Widget _buildHeaderCard() {
    return Card(
      elevation: 2,
      color: _isInbound ? Colors.green.shade50 : Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isInbound ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isInbound
                            ? Icons.arrow_downward
                            : Icons.arrow_upward,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isInbound ? '入库单' : '出库单',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                if (record.isDeleted) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cancel, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text('已作废', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '¥${_totalAmount.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: _isInbound ? Colors.green.shade800 : Colors.red.shade800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '总金额',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───── 留档照片卡片 ─────
  Widget _buildPhotoCard(BuildContext context) {
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(Icons.camera_alt_outlined,
                    size: 18, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  '留档照片',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => Dialog.fullscreen(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      InteractiveViewer(
                        child: Image.file(
                          File(record.imagePath!),
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image, size: 64),
                          ),
                        ),
                      ),
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 8,
                        right: 16,
                        child: CircleAvatar(
                          backgroundColor: Colors.black54,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            child: Image.file(
              File(record.imagePath!),
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (_, __, ___) => Container(
                height: 200,
                color: Colors.grey.shade100,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image,
                          size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text('照片无法加载',
                          style: TextStyle(color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              '点击照片可全屏查看',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }

  // ───── 分组标题 ─────
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade700,
        ),
      ),
    );
  }

  // ───── 信息卡片 ─────
  Widget _buildInfoCard({required List<Widget> children}) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
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
    double? fontSize,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: fontSize ?? 14,
                color: muted ? Colors.grey.shade500 : Colors.grey.shade700,
              ),
            ),
          ),
          if (customValue != null)
            customValue
          else
            Expanded(
              child: Text(
                value ?? '',
                style: TextStyle(
                  fontSize: fontSize ?? (isHighlight ? 17 : 15),
                  fontWeight: isHighlight ? FontWeight.w600 : FontWeight.normal,
                  color: muted
                      ? Colors.grey.shade500
                      : (valueColor ?? Colors.black87),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
