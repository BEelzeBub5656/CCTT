import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database_helper.dart';
import '../models/stock_movement.dart';
import '../models/warehouse.dart';
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
  bool _isSyncing = false;

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

  /// 手动同步
  Future<void> _syncRecords() async {
    setState(() => _isSyncing = true);
    final result = await SyncService().syncPendingRecords();
    setState(() => _isSyncing = false);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? Colors.green : Colors.red,
      ),
    );

    if (result.success) {
      await _loadData();
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

    controller.dispose();
  }

  /// 设置后端地址弹窗
  Future<void> _showSettingsDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('server_base_url') ?? '';
    final controller = TextEditingController(text: savedUrl);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('设置后端地址'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '后端地址',
              hintText: '例如：100.x.x.x:3000',
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
                final scaffold = ScaffoldMessenger.of(context);
                await prefs.setString('server_base_url', url);
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                if (mounted) {
                  scaffold.showSnackBar(
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

    controller.dispose();
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
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
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

  /// 单条记录卡片
  Widget _buildMovementCard(StockMovement record) {
    final isPending = record.syncStatus == SyncStatus.pending;
    final isInbound = record.type == MovementType.inbound;

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
          backgroundColor: isPending
              ? Colors.orange.shade100
              : Colors.green.shade100,
          child: Icon(
            isPending ? Icons.sync : Icons.check_circle,
            color: isPending
                ? Colors.orange.shade800
                : Colors.green.shade800,
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
                record.partnerName,
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
              '数量：${record.quantity.toStringAsFixed(2)}  ×  ¥${record.unitPrice.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
        trailing: Text(
          '¥${record.totalAmount.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: isPending ? Colors.orange : Colors.green,
          ),
        ),
      ),
    );
  }
}
