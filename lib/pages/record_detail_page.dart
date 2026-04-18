import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/stock_movement.dart';

/// 记录详情页
///
/// 展示一条 [StockMovement] 的全部信息，以卡片分组形式排版。
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

  bool get _isPending => record.syncStatus == SyncStatus.pending;

  /// 总金额 = (净重 kg / 1000) * 单价(元/吨)
  double get _totalAmount => (record.quantity / 1000) * record.unitPrice;

  /// 皮重后的净重校验显示（如果有毛重和扣皮）
  double? get _calculatedNetWeight {
    if (record.grossWeight != null && record.tareWeight != null) {
      return record.grossWeight! - record.tareWeight!;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('单据详情'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ───── 头部概览卡片 ─────
          _buildHeaderCard(colorScheme),
          const SizedBox(height: 16),

                  // ───── 基本信息 ─────
          _buildSectionTitle('基本信息'),
          _buildInfoCard(
            children: [
              _buildInfoRow(label: '流水号', value: record.id),
              _buildInfoRow(label: '时间', value: _formattedTime),
              _buildInfoRow(label: '仓库', value: warehouseName),
              _buildInfoRow(
                label: '同步状态',
                value: _isPending ? '待同步' : '已同步',
                valueColor: _isPending ? Colors.orange : Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ───── 交易信息 ─────
          _buildSectionTitle('交易信息'),
          _buildInfoCard(
            children: [
              _buildInfoRow(label: '交易对象', value: record.partnerName),
              _buildInfoRow(
                label: '品名',
                value: record.productName ?? '—',
                muted: record.productName == null,
              ),
              _buildInfoRow(
                label: '送货人',
                value: record.deliveryPerson ?? '—',
                muted: record.deliveryPerson == null,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ───── 重量明细 ─────
          _buildSectionTitle('重量明细'),
          _buildInfoCard(
            children: [
              _buildInfoRow(
                label: '总件数',
                value: record.totalPieces?.toString() ?? '—',
                muted: record.totalPieces == null,
              ),
              _buildInfoRow(
                label: '毛重',
                value: record.grossWeight != null
                    ? '${record.grossWeight!.toStringAsFixed(2)} kg'
                    : '—',
                muted: record.grossWeight == null,
              ),
              _buildInfoRow(
                label: '扣皮（去皮）',
                value: record.tareWeight != null
                    ? '${record.tareWeight!.toStringAsFixed(2)} kg'
                    : '—',
                muted: record.tareWeight == null,
              ),
              const Divider(height: 24),
              _buildInfoRow(
                label: '净重',
                value: '${record.quantity.toStringAsFixed(2)} kg',
                isHighlight: true,
              ),
              if (_calculatedNetWeight != null)
                _buildInfoRow(
                  label: '（毛重 - 扣皮）',
                  value: '${_calculatedNetWeight!.toStringAsFixed(2)} kg',
                  valueColor: Colors.grey.shade600,
                  fontSize: 13,
                ),
            ],
          ),
          const SizedBox(height: 16),

          // ───── 金额明细 ─────
          _buildSectionTitle('金额明细'),
          _buildInfoCard(
            children: [
              _buildInfoRow(
                label: '单价',
                value: '¥${record.unitPrice.toStringAsFixed(2)} / 吨',
              ),
              _buildInfoRow(
                label: '计算公式',
                value: '(${record.quantity.toStringAsFixed(2)} kg ÷ 1000) × ${record.unitPrice.toStringAsFixed(2)}',
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
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ───── 头部概览卡片 ─────
  Widget _buildHeaderCard(ColorScheme colorScheme) {
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
    required String value,
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
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: fontSize ?? 14,
                color: muted ? Colors.grey.shade500 : Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
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
