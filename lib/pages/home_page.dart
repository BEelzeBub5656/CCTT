import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/database_helper.dart';
import '../models/stock_movement.dart';
import '../models/warehouse.dart';
import '../services/settings_service.dart';
import '../services/sync_service.dart';
import 'add_record_page.dart';
import 'record_detail_page.dart';

/// 主页面
///
/// 以 ListView 展示本地库存移动记录，支持按仓库筛选，并用不同颜色图标区分同步状态。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<StockMovement> _movements = [];
  List<Warehouse> _warehouses = [];
  bool _isLoading = true;

  /// null 表示「所有仓库」
  String? _selectedWarehouseId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// 加载所有数据
  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);
    final movements = await DatabaseHelper.instance.getAllMovements();
    final warehouses = await DatabaseHelper.instance.getAllWarehouses();
    if (mounted) {
      setState(() {
        _movements = movements;
        _warehouses = warehouses;
        _isLoading = false;
      });
    }
  }

  /// 根据当前选择筛选记录
  List<StockMovement> get _filteredMovements {
    if (_selectedWarehouseId == null) return _movements;
    return _movements
        .where((m) => m.warehouseId == _selectedWarehouseId)
        .toList();
  }

  /// 下拉刷新
  Future<void> _onRefresh() async {
    await _loadData();
  }

  /// 手动同步（先变蓝、再变绿的视觉反馈）
  Future<void> _syncRecords() async {
    if (!mounted) return;

    // 1. 找出所有 != synced 的记录，标记为 syncing
    final allRecords = await DatabaseHelper.instance.getAllMovements();
    final unsynced = allRecords
        .where((r) => r.syncStatus != SyncStatus.synced)
        .toList();
    if (unsynced.isNotEmpty) {
      final ids = unsynced.map((r) => r.id).toList();
      await DatabaseHelper.instance.updateSyncStatus(ids, SyncStatus.syncing);
    }

    // 2. 立刻刷新界面 → 蓝色"正在同步"
    await _loadData();

    // 3. 发起网络请求
    final result = await SyncService.syncPendingRecords();

    // 4. 最后再刷新界面 → 绿色（成功）或红色（失败）
    await _loadData();

    // 5. 弹窗提示结果
    if (mounted) {
      final isSuccess = result.contains('成功');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result),
          backgroundColor: isSuccess ? Colors.green : Colors.red,
        ),
      );
    }
  }

  /// 跳转到新建页面
  Future<void> _navigateToAdd() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddRecordPage()),
    );
    if (result == true) {
      await _loadData();
    }
  }

  /// 添加仓库弹窗
  Future<void> _showAddWarehouseDialog() async {
    final controller = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('添加仓库'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '仓库名称',
              hintText: '如：主仓库、北区仓',
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => Navigator.of(dialogContext).pop(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                final scaffold = ScaffoldMessenger.of(context);
                await DatabaseHelper.instance.insertWarehouse(
                  Warehouse(name: name),
                );
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                await _loadData();
                if (mounted) {
                  scaffold.showSnackBar(
                    SnackBar(content: Text('仓库 "$name" 已添加')),
                  );
                }
              },
              child: const Text('确认'),
            ),
          ],
        );
      },
    );

    // 延迟到 dialog 完全关闭后再 dispose controller
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
  }

  /// 设置 PC 接收端地址弹窗
  Future<void> _showSettingsDialog() async {
    final savedUrl = await SettingsService.getServerBaseUrl() ?? '';
    final controller = TextEditingController(text: savedUrl);

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('设置 PC 接收端地址'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '后端地址',
              hintText: '例如：http://100.x.x.x:3000',
              prefixIcon: Icon(Icons.link),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => Navigator.of(dialogContext).pop(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final url = controller.text.trim();
                if (url.isEmpty) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('地址不能为空')),
                    );
                  }
                  return;
                }
                if (!url.startsWith('http://') && !url.startsWith('https://')) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text('地址必须以 http:// 或 https:// 开头'),
                      ),
                    );
                  }
                  return;
                }
                await SettingsService.setServerBaseUrl(url);
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('后端地址已保存')),
                  );
                }
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    // 延迟到 dialog 完全关闭后再 dispose controller
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
  }

  /// 创建默认仓库（空状态快捷入口）
  Future<void> _createDefaultWarehouse() async {
    final scaffold = ScaffoldMessenger.of(context);
    await DatabaseHelper.instance.insertWarehouse(
      Warehouse(name: '默认仓库'),
    );
    if (mounted) {
      await _loadData();
      scaffold.showSnackBar(
        const SnackBar(content: Text('已创建默认仓库')),
      );
    }
  }

  /// 格式化时间戳
  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('yyyy-MM-dd HH:mm').format(date);
  }

  /// 根据仓库 ID 获取名称
  String _warehouseName(String warehouseId) {
    final w = _warehouses.firstWhere(
      (w) => w.id == warehouseId,
      orElse: () => Warehouse(name: '未知仓库'),
    );
    return w.name;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredMovements;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CCTT 库存管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            tooltip: '同步到 PC',
            onPressed: _syncRecords,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新列表',
            onPressed: _onRefresh,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // ───────────── 仓库筛选栏 ─────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.filter_list, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      key: ValueKey(_warehouses.hashCode),
                      isExpanded: true,
                      value: _selectedWarehouseId,
                      hint: const Text('所有仓库'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('所有仓库'),
                        ),
                        ..._warehouses.map((w) {
                          return DropdownMenuItem<String?>(
                            value: w.id,
                            child: Text(w.name),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        if (mounted) {
                          setState(() => _selectedWarehouseId = value);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add_business),
                  tooltip: '添加仓库',
                  onPressed: _showAddWarehouseDialog,
                ),
              ],
            ),
          ),

          // ───────────── 列表区域 ─────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _onRefresh,
                    child: filtered.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              return _buildMovementCard(filtered[index]);
                            },
                          ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToAdd,
        icon: const Icon(Icons.add),
        label: const Text('新建'),
      ),
    );
  }

  /// 空状态提示
  Widget _buildEmptyState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.inbox, size: 64, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(
                    _selectedWarehouseId == null
                        ? '暂无库存移动记录'
                        : '该仓库暂无记录',
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '点击右下角按钮添加第一条记录',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  if (_warehouses.isEmpty)
                    ElevatedButton.icon(
                      onPressed: _createDefaultWarehouse,
                      icon: const Icon(Icons.add_business),
                      label: const Text('创建默认仓库'),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 根据状态生成带颜色的文字标签
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

  /// 单条记录卡片
  Widget _buildMovementCard(StockMovement record) {
    final isInbound = record.type == MovementType.inbound;

    // 主标题：颜色 + 品种
    final displayTitle = record.color.isNotEmpty || record.variety.isNotEmpty
        ? '${record.color}${record.color.isNotEmpty && record.variety.isNotEmpty ? ' / ' : ''}${record.variety}'
        : record.partnerName;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => RecordDetailPage(
                record: record,
                warehouseName: _warehouseName(record.warehouseId),
              ),
            ),
          );
        },
        leading: CircleAvatar(
          backgroundColor: record.syncStatus == SyncStatus.synced
              ? Colors.green.shade100
              : Colors.orange.shade100,
          child: Icon(
            record.syncStatus == SyncStatus.synced
                ? Icons.check_circle
                : Icons.sync,
            color: record.syncStatus == SyncStatus.synced
                ? Colors.green.shade800
                : Colors.orange.shade800,
          ),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isInbound
                    ? Colors.green.shade50
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isInbound ? Colors.green : Colors.red,
                ),
              ),
              child: Text(
                isInbound ? '入库' : '出库',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isInbound
                      ? Colors.green.shade800
                      : Colors.red.shade800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                displayTitle,
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '${_warehouseName(record.warehouseId)}  •  ${_formatTimestamp(record.timestamp)}',
            ),
            Text(
              '净重 ${record.quantity.toStringAsFixed(2)} kg  |  单价 ¥${record.unitPrice.toStringAsFixed(2)}/吨',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
        trailing: _buildSyncStatusBadge(record.syncStatus),
      ),
    );
  }
}
