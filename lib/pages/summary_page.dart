import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/summary_demo_data_service.dart';
import '../services/summary_service.dart';
import '../theme/cctt_colors.dart';

class SummaryPage extends StatefulWidget {
  const SummaryPage({super.key});

  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

enum _SummaryViewMode { dashboard, details }

class _SummaryPageState extends State<SummaryPage> {
  final _weightFormat = NumberFormat('#,##0.0#');
  final _amountFormat = NumberFormat('#,##0.00');
  late DateTime _startDate;
  late DateTime _endDate;
  SummaryReport? _report;
  bool _isGenerating = false;
  bool _isUpdatingDemoData = false;
  String? _errorMessage;
  _SummaryViewMode _viewMode = _SummaryViewMode.dashboard;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, 1, 1);
    _endDate = DateTime(now.year, 12, 31);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _generateReport();
    });
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
    await _generateReport();
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
        _startDate = DateTime(now.year, 1, 1);
        _endDate = DateTime(now.year, 12, 31);
      });
      await _generateReport();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已写入 $count 张测试单据，并重新生成本年度汇总')),
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
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
          children: [
            _buildDateRangeCard(),
            if (kDebugMode) ...[
              const SizedBox(height: 12),
              _buildDebugDataCard(),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_report == null && _isGenerating) ...[
              const SizedBox(height: 56),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_report != null) ...[
              const SizedBox(height: 12),
              _buildViewModeSelector(),
              const SizedBox(height: 12),
              _viewMode == _SummaryViewMode.dashboard
                  ? _buildDashboard(_report!)
                  : _buildReport(_report!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildViewModeSelector() {
    return Align(
      alignment: Alignment.center,
      child: SegmentedButton<_SummaryViewMode>(
        segments: const [
          ButtonSegment(
            value: _SummaryViewMode.dashboard,
            icon: Icon(Icons.space_dashboard_outlined, size: 18),
            label: Text('看板'),
          ),
          ButtonSegment(
            value: _SummaryViewMode.details,
            icon: Icon(Icons.view_list_outlined, size: 18),
            label: Text('明细'),
          ),
        ],
        selected: {_viewMode},
        showSelectedIcon: false,
        onSelectionChanged: (selection) {
          setState(() => _viewMode = selection.first);
        },
      ),
    );
  }

  Widget _buildDashboard(SummaryReport report) {
    final brand =
        Theme.of(context).extension<CcttBrandColors>() ?? CcttBrandColors.light;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _isFullYear(report)
              ? '${report.startDate.year} 年经营看板'
              : '${_dateText(report.startDate)} 至 ${_dateText(report.endDate)}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.insights_outlined, color: brand.brandDeep),
                    const SizedBox(width: 8),
                    Text(
                      '本期业务概览',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildDashboardMetric(
                        label: '出货',
                        totals: report.outbound,
                        color: brand.redDeep,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildDashboardMetric(
                        label: '入库',
                        totals: report.inbound,
                        color: brand.greenDeep,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildDashboardMetric(
                        label: '进货',
                        totals: report.supply,
                        color: brand.blueDeep,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _buildWeightComparison(report, brand),
        const SizedBox(height: 14),
        _buildCategoryRanking(report.inboundCategories, brand.greenDeep),
        const SizedBox(height: 14),
        _buildPartnerRanking(report.supplyPartners, brand.blueDeep),
      ],
    );
  }

  Widget _buildDashboardMetric({
    required String label,
    required SummaryTotals totals,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _weight(totals.totalWeight),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _amount(totals.totalAmount),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${totals.orderCount} 单',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  Widget _buildWeightComparison(
    SummaryReport report,
    CcttBrandColors brand,
  ) {
    final maximumWeight = [
      report.outbound.totalWeight,
      report.inbound.totalWeight,
      report.supply.totalWeight,
    ].fold<double>(0, (current, value) => value > current ? value : current);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('重量对比', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '以本期最高业务量为基准',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            _buildWeightBar(
              label: '出货',
              weight: report.outbound.totalWeight,
              maximumWeight: maximumWeight,
              color: brand.redDeep,
            ),
            const SizedBox(height: 14),
            _buildWeightBar(
              label: '入库',
              weight: report.inbound.totalWeight,
              maximumWeight: maximumWeight,
              color: brand.greenDeep,
            ),
            const SizedBox(height: 14),
            _buildWeightBar(
              label: '进货',
              weight: report.supply.totalWeight,
              maximumWeight: maximumWeight,
              color: brand.blueDeep,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeightBar({
    required String label,
    required double weight,
    required double maximumWeight,
    required Color color,
  }) {
    final progress = maximumWeight == 0 ? 0.0 : weight / maximumWeight;
    return Column(
      children: [
        Row(
          children: [
            SizedBox(
              width: 38,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 9,
                  backgroundColor: color.withValues(alpha: 0.10),
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 82,
              child: Text(
                _weight(weight),
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoryRanking(
    List<CategorySummary> categories,
    Color color,
  ) {
    final topCategories = categories.take(3).toList();
    return _buildRankingCard(
      title: '入库品类 Top 3',
      subtitle: '按重量排列',
      icon: Icons.category_outlined,
      color: color,
      emptyText: '本期暂无入库品类数据',
      children: [
        for (var index = 0; index < topCategories.length; index++)
          _buildRankingRow(
            rank: index + 1,
            label: topCategories[index].name,
            weight: topCategories[index].totalWeight,
            amount: topCategories[index].amount,
            color: color,
          ),
      ],
    );
  }

  Widget _buildPartnerRanking(
    List<PartnerSummary> partners,
    Color color,
  ) {
    final topPartners = [...partners]
      ..sort((a, b) => b.totals.totalWeight.compareTo(a.totals.totalWeight));
    return _buildRankingCard(
      title: '进货客户 Top 3',
      subtitle: '按重量排列',
      icon: Icons.groups_2_outlined,
      color: color,
      emptyText: '本期暂无进货客户数据',
      children: [
        for (var index = 0; index < topPartners.length && index < 3; index++)
          _buildRankingRow(
            rank: index + 1,
            label: topPartners[index].partnerName,
            weight: topPartners[index].totals.totalWeight,
            amount: topPartners[index].totals.totalAmount,
            color: color,
          ),
      ],
    );
  }

  Widget _buildRankingCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String emptyText,
    required List<Widget> children,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(title, subtitle, icon, color),
            const SizedBox(height: 10),
            if (children.isEmpty)
              Text(
                emptyText,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              )
            else
              ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildRankingRow({
    required int rank,
    required String label,
    required double weight,
    required double amount,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_weight(weight)),
              Text(
                _amount(amount),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
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
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        child: Row(
          children: [
            const Tooltip(
              message: '统计日期（作废单据不计入）',
              child: Icon(Icons.calendar_month_outlined, size: 20),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDateButton(
                label: '起',
                date: _startDate,
                onPressed: () => _pickDate(isStart: true),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('—', style: TextStyle(color: Colors.grey)),
            ),
            Expanded(
              child: _buildDateButton(
                label: '止',
                date: _endDate,
                onPressed: () => _pickDate(isStart: false),
              ),
            ),
            IconButton(
              tooltip: '刷新汇总',
              visualDensity: VisualDensity.compact,
              onPressed: _isGenerating ? null : _generateReport,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 21),
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
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
        minimumSize: const Size(0, 36),
        visualDensity: VisualDensity.compact,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$label ', style: Theme.of(context).textTheme.labelSmall),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _dateText(date),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReport(SummaryReport report) {
    final brand =
        Theme.of(context).extension<CcttBrandColors>() ?? CcttBrandColors.light;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _isFullYear(report)
              ? '${report.startDate.year} 年全部数据汇总'
              : '${_dateText(report.startDate)} 至 ${_dateText(report.endDate)}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 12),
        _buildSummarySection(
          title: '出货汇总',
          subtitle: '出库单据总计',
          icon: Icons.north_east,
          color: brand.redDeep,
          totals: report.outbound,
        ),
        const SizedBox(height: 14),
        _buildSummarySection(
          title: '入库汇总',
          subtitle: '入库总计及品类明细',
          icon: Icons.south_west,
          color: brand.greenDeep,
          totals: report.inbound,
          children: _buildCategoryList(report.inboundCategories),
        ),
        const SizedBox(height: 14),
        _buildSupplySection(report),
      ],
    );
  }

  bool _isFullYear(SummaryReport report) =>
      report.startDate.month == 1 &&
      report.startDate.day == 1 &&
      report.endDate.year == report.startDate.year &&
      report.endDate.month == 12 &&
      report.endDate.day == 31;

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
    final brand =
        Theme.of(context).extension<CcttBrandColors>() ?? CcttBrandColors.light;
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
              brand.blueDeep,
            ),
            const SizedBox(height: 14),
            _buildTotals(report.supply, brand.blueDeep),
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
