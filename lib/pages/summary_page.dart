import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/summary_demo_data_service.dart';
import '../services/summary_service.dart';

class SummaryPage extends StatefulWidget {
  const SummaryPage({super.key});

  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
  final _weightFormat = NumberFormat('#,##0.0#');
  final _amountFormat = NumberFormat('#,##0.00');
  late DateTime _startDate;
  late DateTime _endDate;
  SummaryReport? _report;
  bool _isGenerating = false;
  bool _isUpdatingDemoData = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month);
    _endDate = DateTime(now.year, now.month, now.day);
  }

  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('zh', 'CN'),
    );
    if (picked == null || !mounted) return;

    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
      _report = null;
      _errorMessage = null;
    });
  }

  Future<void> _generateReport() async {
    if (_startDate.isAfter(_endDate)) {
      setState(() => _errorMessage = '开始日期不能晚于结束日期');
      return;
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });
    try {
      final report = await SummaryService.generate(
        startDate: _startDate,
        endDate: _endDate,
      );
      if (!mounted) return;
      setState(() => _report = report);
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = '汇总生成失败：$error');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _seedDemoData() async {
    setState(() => _isUpdatingDemoData = true);
    try {
      final count = await SummaryDemoDataService.seed();
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _startDate = DateTime(now.year, now.month);
        _endDate = DateTime(now.year, now.month, now.day);
      });
      await _generateReport();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已写入 $count 张测试单据，并重新生成本月汇总')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = '测试数据写入失败：$error');
    } finally {
      if (mounted) setState(() => _isUpdatingDemoData = false);
    }
  }

  Future<void> _clearDemoData() async {
    setState(() => _isUpdatingDemoData = true);
    try {
      await SummaryDemoDataService.clear();
      if (!mounted) return;
      await _generateReport();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('汇总测试数据已清除')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = '测试数据清除失败：$error');
    } finally {
      if (mounted) setState(() => _isUpdatingDemoData = false);
    }
  }

  String _dateText(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
  String _weight(double value) => '${_weightFormat.format(value)} kg';
  String _amount(double value) => '¥${_amountFormat.format(value)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('汇总表')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _buildDateRangeCard(),
            if (kDebugMode) ...[
              const SizedBox(height: 12),
              _buildDebugDataCard(),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isGenerating ? null : _generateReport,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.summarize_outlined),
              label: Text(_isGenerating ? '正在生成...' : '生成汇总表'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_report == null && !_isGenerating && _errorMessage == null) ...[
              const SizedBox(height: 48),
              const Icon(Icons.date_range_outlined,
                  size: 56, color: Colors.grey),
              const SizedBox(height: 12),
              const Text(
                '选择起止日期后生成汇总表\n作废单据不会计入统计',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, height: 1.6),
              ),
            ],
            if (_report != null) ...[
              const SizedBox(height: 20),
              _buildReport(_report!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDebugDataCard() {
    return Card(
      margin: EdgeInsets.zero,
      color: Colors.amber.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.science_outlined, color: Colors.amber),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Debug 测试数据',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('固定 ID，可重复生成；不会进入待同步队列'),
                ],
              ),
            ),
            PopupMenuButton<String>(
              enabled: !_isUpdatingDemoData,
              tooltip: '测试数据操作',
              onSelected: (value) {
                if (value == 'seed') {
                  _seedDemoData();
                } else if (value == 'clear') {
                  _clearDemoData();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'seed', child: Text('生成/更新')),
                PopupMenuItem(value: 'clear', child: Text('清除')),
              ],
              child: _isUpdatingDemoData
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.more_vert),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRangeCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.calendar_month_outlined, size: 20),
                SizedBox(width: 8),
                Text('统计日期', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildDateButton(
                    label: '开始日期',
                    date: _startDate,
                    onPressed: () => _pickDate(isStart: true),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, size: 18),
                ),
                Expanded(
                  child: _buildDateButton(
                    label: '结束日期',
                    date: _endDate,
                    onPressed: () => _pickDate(isStart: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '起止日期均计入统计',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateButton({
    required String label,
    required DateTime date,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        alignment: Alignment.centerLeft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 3),
          Text(
            _dateText(date),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildReport(SummaryReport report) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${_dateText(report.startDate)} 至 ${_dateText(report.endDate)}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        _buildSummarySection(
          title: '出货汇总',
          subtitle: '出库单据总计',
          icon: Icons.north_east,
          color: Colors.deepOrange,
          totals: report.outbound,
        ),
        const SizedBox(height: 14),
        _buildSummarySection(
          title: '入库汇总',
          subtitle: '入库总计及品类明细',
          icon: Icons.south_west,
          color: Colors.green,
          totals: report.inbound,
          children: _buildCategoryList(report.inboundCategories),
        ),
        const SizedBox(height: 14),
        _buildSupplySection(report),
      ],
    );
  }

  Widget _buildSummarySection({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required SummaryTotals totals,
    List<Widget> children = const [],
  }) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(title, subtitle, icon, color),
            const SizedBox(height: 14),
            _buildTotals(totals, color),
            if (totals.feeAmount != 0) ...[
              const SizedBox(height: 8),
              Text(
                '总金额含额外费用 ${_amount(totals.feeAmount)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (children.isNotEmpty) ...[
              const Divider(height: 28),
              ...children,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          foregroundColor: color,
          child: Icon(icon),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTotals(SummaryTotals totals, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child:
                  _buildMetricTile('总重量', _weight(totals.totalWeight), color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child:
                  _buildMetricTile('总金额', _amount(totals.totalAmount), color),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          totals.isEmpty
              ? '该日期范围暂无数据'
              : '${totals.orderCount} 张单据 · ${totals.itemCount} 条明细',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildMetricTile(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCategoryList(List<CategorySummary> categories) {
    if (categories.isEmpty) return const [];
    return [
      Text('品类明细', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 6),
      ...categories.map(_buildCategoryRow),
    ];
  }

  Widget _buildCategoryRow(CategorySummary category) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(category.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  '${category.itemCount} 条明细',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_weight(category.totalWeight)),
              Text(
                _amount(category.amount),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSupplySection(SummaryReport report) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              '进货汇总',
              '按客户及品类展开',
              Icons.local_shipping_outlined,
              Colors.blue,
            ),
            const SizedBox(height: 14),
            _buildTotals(report.supply, Colors.blue),
            if (report.supply.feeAmount != 0) ...[
              const SizedBox(height: 8),
              Text(
                '总金额含额外费用 ${_amount(report.supply.feeAmount)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (report.supplyPartners.isNotEmpty) ...[
              const Divider(height: 28),
              Text('客户明细', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              ...report.supplyPartners.map(_buildPartnerTile),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPartnerTile(PartnerSummary partner) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 12, bottom: 8),
      title: Text(
        partner.partnerName,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${_weight(partner.totals.totalWeight)} · ${_amount(partner.totals.totalAmount)}',
      ),
      children: [
        if (partner.totals.feeAmount != 0)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '额外费用 ${_amount(partner.totals.feeAmount)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ...partner.categories.map(_buildCategoryRow),
      ],
    );
  }
}
