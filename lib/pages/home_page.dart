import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/database_helper.dart';
import '../models/order.dart';
import '../models/stock_movement.dart';
import '../models/warehouse.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cctt_components.dart';
import '../widgets/update_dialog.dart';
import 'add_order_page.dart';
import 'order_detail_page.dart';
import 'settings_page.dart';
import 'summary_page.dart';

/// 主页面
///
/// 以 ListView 展示本地主单据，支持按仓库筛选，并用不同颜色图标区分同步状态。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _amountFormat = NumberFormat('#,##0.00');
  List<OrderDetail> _orders = [];
  List<Warehouse> _warehouses = [];
  bool _isLoading = true;
  int _unpushedCount = 0;
  int _cloudNewCount = 0;
  bool _cloudChecked = false;
  String _searchKeyword = '';
  Timer? _autoSyncTimer;
  bool _isAutoSyncRunning = false;

  /// null 表示「所有仓库」
  String? _selectedWarehouseId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkUpdateOnStartup(context);
    });
    _loadData().then((_) {
      _checkUnpushedRecords();
      _autoPullFromCloud();
      _startAutoSyncTimer();
    }).catchError((e) {
      debugPrint('HomePage init 加载失败: $e');
    });
  }

  /// 加载所有数据
  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final movements = await DatabaseHelper.instance.getAllMovements();
      final warehouses = await DatabaseHelper.instance.getAllWarehouses();
      final allOrders = await DatabaseHelper.instance.getAllOrders();
      final orderDetails = <OrderDetail>[];
      for (final o in allOrders) {
        final items = await DatabaseHelper.instance.getOrderItems(o.id);
        final fees = await DatabaseHelper.instance.getOrderFees(o.id);
        orderDetails.add(OrderDetail(order: o, items: items, fees: fees));
      }
      if (mounted) {
        if (movements.isNotEmpty) {
          await DatabaseHelper.instance.deleteMovements(
            movements.map((m) => m.id).toList(),
          );
        }
        final unsynced = orderDetails
            .where((d) => d.order.syncStatus != SyncStatus.synced)
            .length;
        setState(() {
          _orders = orderDetails;
          _warehouses = warehouses;
          _unpushedCount = unsynced;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('_loadData 失败: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 启动后检测未推送到云端的单据
  void _checkUnpushedRecords() {
    if (!mounted || _unpushedCount == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('有 $_unpushedCount 张单据尚未同步到云端'),
          action: SnackBarAction(
            label: '立即同步',
            onPressed: _syncRecords,
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    });
  }

  /// 启动后静默拉取云端快照，Master 快照强制覆盖本地
  Future<void> _autoPullFromCloud() async {
    if (!mounted) return;
    final result = await SyncService.pullSnapshot();
    if (!mounted) return;

    setState(() {
      _cloudNewCount = result.addedCount;
      _cloudChecked = true;
    });

    if (result.success) {
      // 总是刷新列表（数据可能被 Master 快照覆盖更新）
      await _loadData();
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor:
                result.addedCount > 0 ? Colors.teal : Colors.grey.shade700,
            duration: Duration(seconds: result.addedCount > 0 ? 5 : 2),
          ),
        );
      });
    }
    // 超时等错误静默忽略，用户可手动下拉
  }

  List<OrderDetail> get _filteredOrders {
    var list = _orders.where((o) => !o.order.isDeleted).toList();
    if (_selectedWarehouseId != null) {
      list = list
          .where((o) => o.order.warehouseId == _selectedWarehouseId)
          .toList();
    }
    if (_searchKeyword.isNotEmpty) {
      final kw = _searchKeyword.toLowerCase();
      list = list.where((o) {
        final time = DateTime.fromMillisecondsSinceEpoch(o.order.timestamp);
        final monthStr = '${time.year}年${time.month}月 ${time.month}月';
        final itemNames = o.items.map((i) => i.itemName).join(' ');
        final searchText = [
          o.order.partnerName,
          itemNames,
          o.order.remark ?? '',
          _warehouseName(o.order.warehouseId),
          monthStr,
        ].join(' ').toLowerCase();
        return searchText.contains(kw);
      }).toList();
    }
    return list;
  }

  /// 下拉刷新
  Future<void> _onRefresh() async {
    await _loadData();
  }

  /// 从云端拉取 retain 全量快照（带全屏 Loading，手动触发）
  Future<void> _pullSnapshot() async {
    if (!mounted) return;

    // 显示全屏 Loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );

    PullResult result;
    try {
      result = await SyncService.pullSnapshot();
    } finally {
      // 无论成功还是失败，必须关闭 Loading，防止界面锁死
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    // 更新云端状态
    if (mounted) {
      setState(() {
        _cloudNewCount = result.addedCount;
        _cloudChecked = true;
      });
    }

    // 刷新页面
    await _loadData();

    if (!mounted) return;

    // 出错场景弹窗提示
    if (!result.success) {
      final isDnsError = result.message.contains('SocketException') ||
          result.message.contains('host lookup') ||
          result.message.contains('No address');
      final brokerName = 'kf33d077.ala.cn-hangzhou.emqxsl.cn';
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('连接云端失败'),
          content: Text(
            isDnsError
                ? '无法解析 MQTT 服务器地址。\n\n'
                    'Broker: $brokerName\n\n'
                    '可能原因：\n'
                    '1. 手机网络未连接\n'
                    '2. EMQX 服务已停止\n'
                    '3. DNS 解析失败，稍后重试'
                : result.message,
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                // 重试
                if (mounted) _pullSnapshot();
              },
              child: const Text('重试'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// 手动同步（上传 + 下拉合一，先上后下）
  Future<void> _syncRecords() async {
    if (!mounted) return;

    // 1. 推本地变更到 Master
    final pushResult = await SyncService.syncPendingRecords();

    // 2. 下拉 Master 最新快照
    final pullResult = await SyncService.pullSnapshot();
    setState(() {
      _cloudNewCount = pullResult.addedCount;
      _cloudChecked = true;
    });
    await _loadData();

    // 3. 提示结果
    if (mounted) {
      final isSuccess = !pushResult.startsWith('同步失败') && pullResult.success;
      if (isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(pullResult.message),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // 失败弹窗，提供重试
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('同步失败'),
            content: Text(pushResult),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _syncRecords(); // 重试
                },
                child: const Text('重试'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
      }
    }
  }

  /// 跳转到新建 Order 页面
  Future<void> _navigateToAddOrder() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddOrderPage()),
    );
    await _loadData();
    _autoSync();
  }

  /// 静默自动同步（不弹窗，上传→等 Master 处理→下拉）
  void _autoSync() {
    if (_isAutoSyncRunning) return;
    _isAutoSyncRunning = true;
    SyncService.syncPendingRecords()
        .then((_) async {
          // 等 Web 处理完并发快照（去抖 800ms + 网络延迟）
          await Future.delayed(const Duration(milliseconds: 2000));
          final r = await SyncService.pullSnapshot();
          if (mounted) {
            setState(() {
              _cloudNewCount = r.addedCount;
              _cloudChecked = true;
            });
            await _loadData();
          }
        })
        .catchError((_) {})
        .whenComplete(() {
          _isAutoSyncRunning = false;
        });
  }

  void _startAutoSyncTimer() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (!mounted) return;
      _autoSync();
    });
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

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    super.dispose();
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
    final filtered = _filteredOrders;
    // 上传待推送 + 云端有新数据，合并成一个同步入口：
    // 用户心里只有「同不同步」一件事，不该在标题栏里区分推和拉。
    final syncBadgeCount = _unpushedCount + _cloudNewCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CCTT 库存'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.search,
              color: _searchKeyword.isNotEmpty
                  ? CCTTTheme.accentOrange
                  : Colors.white,
            ),
            tooltip: '查询单据',
            onPressed: _showSearchDialog,
          ),
          IconButton(
            icon: syncBadgeCount > 0
                ? Badge(
                    label: Text('$syncBadgeCount'),
                    backgroundColor: CCTTTheme.accentOrange,
                    textColor: Colors.white,
                    child: const Icon(Icons.sync),
                  )
                : Icon(
                    _cloudChecked ? Icons.cloud_done_outlined : Icons.sync,
                    color: _cloudChecked
                        ? CCTTTheme.statusSynced
                        : Colors.white,
                  ),
            tooltip: syncBadgeCount > 0
                ? '同步（$_unpushedCount 张待推送 · $_cloudNewCount 张待拉取）'
                : _cloudChecked
                    ? '已是最新'
                    : '与云端同步',
            onPressed: _showSyncSheet,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: '更多',
            position: PopupMenuPosition.under,
            onSelected: (value) {
              switch (value) {
                case 'summary':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SummaryPage()),
                  );
                case 'voided':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _DeletedOrdersPage(
                        orders:
                            _orders.where((o) => o.order.isDeleted).toList(),
                        warehouseName: _warehouseName,
                      ),
                    ),
                  );
                case 'warehouse':
                  _showAddWarehouseDialog();
                case 'refresh':
                  _onRefresh();
                case 'settings':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'summary',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.analytics_outlined),
                  title: Text('汇总表'),
                ),
              ),
              PopupMenuItem(
                value: 'voided',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_sweep_outlined),
                  title: Text('已作废单据'),
                ),
              ),
              PopupMenuItem(
                value: 'warehouse',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.add_business_outlined),
                  title: Text('添加仓库'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'refresh',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.refresh),
                  title: Text('刷新列表'),
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.settings_outlined),
                  title: Text('设置'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildWarehouseFilterBar(),
          if (_searchKeyword.isNotEmpty) _buildSearchBanner(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _onRefresh,
                    color: CCTTTheme.accentOrange,
                    child: filtered.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(
                              CCTTTheme.space3,
                              CCTTTheme.space3,
                              CCTTTheme.space3,
                              CCTTTheme.space4,
                            ),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final d = filtered[index];
                              return OrderCard(
                                detail: d,
                                warehouseName:
                                    _warehouseName(d.order.warehouseId),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        OrderDetailPage(orderId: d.order.id),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
      // 两个同等重量的 FAB 会让人犹豫先点哪个。
      // 新建是主动作，用实心主按钮；查询已经收到标题栏，这里只留新建。
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: CCTTTheme.neutral300)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CCTTTheme.space4,
              vertical: CCTTTheme.space2 + 2,
            ),
            child: Row(
              children: [
                Expanded(child: _buildTotalSummary(filtered)),
                const SizedBox(width: CCTTTheme.space4),
                SizedBox(
                  width: 148,
                  child: CCTTPrimaryButton(
                    label: '新建单据',
                    icon: Icons.add,
                    onPressed: _navigateToAddOrder,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 底部合计：既然底栏已经有位置，就把「当前筛选下一共多少钱」摆出来，
  /// 省掉一次进汇总表的跳转。
  Widget _buildTotalSummary(List<OrderDetail> filtered) {
    final active = filtered.where((o) => !o.order.isDeleted).toList();
    final total = active.fold<double>(0, (s, o) => s + o.totalAmount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '${active.length} 张单据',
          style: const TextStyle(fontSize: 11, color: CCTTTheme.neutral500),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            '¥${_amountFormat.format(total)}',
            style: CCTTTheme.numeric(size: 19),
          ),
        ),
      ],
    );
  }

  /// 仓库筛选：横向 chip 条。
  /// 原来是一个 PopupMenuButton —— 当前选中的仓库要点开才知道，
  /// 而仓库通常只有两三个，直接平铺出来一眼可见、一下可切。
  Widget _buildWarehouseFilterBar() {
    final totalActive = _orders.where((o) => !o.order.isDeleted).length;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: CCTTTheme.neutral300)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: CCTTTheme.space3,
          vertical: CCTTTheme.space2,
        ),
        child: Row(
          children: [
            _filterChip(
              label: '全部',
              count: totalActive,
              selected: _selectedWarehouseId == null,
              onTap: () => setState(() => _selectedWarehouseId = null),
            ),
            ..._warehouses.map((w) {
              final count = _orders
                  .where((o) => !o.order.isDeleted && o.order.warehouseId == w.id)
                  .length;
              return Padding(
                padding: const EdgeInsets.only(left: CCTTTheme.space2),
                child: _filterChip(
                  label: w.name,
                  count: count,
                  selected: _selectedWarehouseId == w.id,
                  onTap: () => setState(() => _selectedWarehouseId = w.id),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? CCTTTheme.primaryDark : CCTTTheme.neutral100,
      borderRadius: BorderRadius.circular(CCTTTheme.radiusFullish),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CCTTTheme.radiusFullish),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: CCTTTheme.space3,
            vertical: CCTTTheme.space2,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CCTTTheme.radiusFullish),
            border: Border.all(
              color: selected ? CCTTTheme.primaryDark : CCTTTheme.neutral300,
            ),
          ),
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : CCTTTheme.neutral700,
                ),
              ),
              const SizedBox(width: CCTTTheme.space1 + 2),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: CCTTTheme.monoFont,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? CCTTTheme.accentAmber
                      : CCTTTheme.neutral500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 搜索中的状态条：让「现在看到的是搜索结果」这件事一直可见，
  /// 并且清除只需一次点击。
  Widget _buildSearchBanner() {
    return Container(
      width: double.infinity,
      color: CCTTTheme.accentOrange.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(
        horizontal: CCTTTheme.space4,
        vertical: CCTTTheme.space2,
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 15, color: CCTTTheme.accentOrange),
          const SizedBox(width: CCTTTheme.space2),
          Expanded(
            child: Text(
              '搜索「$_searchKeyword」',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: CCTTTheme.neutral900,
              ),
            ),
          ),
          InkWell(
            onTap: () => setState(() => _searchKeyword = ''),
            borderRadius: BorderRadius.circular(CCTTTheme.radiusSmall),
            child: const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: CCTTTheme.space2,
                vertical: 2,
              ),
              child: Text(
                '清除',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: CCTTTheme.accentOrange,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 同步面板：把原来两个图标按钮合并成一处，
  /// 推送和拉取各自的待处理数量在这里说清楚，而不是靠 tooltip。
  Future<void> _showSyncSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CCTTTheme.space3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CCTTTheme.space4,
                  CCTTTheme.space2,
                  CCTTTheme.space4,
                  CCTTTheme.space3,
                ),
                child: Row(
                  children: [
                    const Text(
                      '云端同步',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (_cloudChecked && _unpushedCount == 0 && _cloudNewCount == 0)
                      const StatusChip(
                        label: '已是最新',
                        color: CCTTTheme.statusSynced,
                        icon: Icons.check,
                      ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.cloud_upload_outlined),
                title: const Text('推送到云端'),
                subtitle: Text(
                  _unpushedCount > 0 ? '$_unpushedCount 张单据还没上传' : '本地没有待上传的改动',
                ),
                trailing: _unpushedCount > 0
                    ? StatusChip(
                        label: '$_unpushedCount',
                        color: CCTTTheme.statusPending,
                        filled: true,
                      )
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _syncRecords();
                },
              ),
              ListTile(
                leading: const Icon(Icons.cloud_download_outlined),
                title: const Text('从云端拉取'),
                subtitle: Text(
                  _cloudNewCount > 0
                      ? '云端有 $_cloudNewCount 张新单据'
                      : _cloudChecked
                          ? '云端没有新数据'
                          : '还没检查过云端',
                ),
                trailing: _cloudNewCount > 0
                    ? StatusChip(
                        label: '$_cloudNewCount',
                        color: CCTTTheme.statusSyncing,
                        filled: true,
                      )
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _pullSnapshot();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 关键词搜索弹窗
  Future<void> _showSearchDialog() async {
    final controller = TextEditingController(text: _searchKeyword);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.search, size: 20),
          const SizedBox(width: 8),
          const Text('查询单据'),
          const Spacer(),
          if (_searchKeyword.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(ctx, '__CLEAR__'),
              child: const Text('清除', style: TextStyle(fontSize: 12)),
            ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '交易对象、货物、备注、X月…',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.edit_note),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: ['6月', '白色', '黑色', '绵羊毛', '山羊绒']
                  .map((tag) => ActionChip(
                        label: Text(tag, style: const TextStyle(fontSize: 12)),
                        onPressed: () => Navigator.pop(ctx, tag),
                      ))
                  .toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('搜索'),
          ),
        ],
      ),
    );

    if (result == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
      return;
    }
    if (result == '__CLEAR__') {
      setState(() => _searchKeyword = '');
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
      return;
    }
    setState(() => _searchKeyword = result);
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }

  /// 空状态提示
  Widget _buildEmptyState() {
    final String title;
    final String message;
    if (_searchKeyword.isNotEmpty) {
      title = '没有匹配的单据';
      message = '换个关键词试试，或者清除搜索看全部单据';
    } else if (_warehouses.isEmpty) {
      title = '先建一个仓库';
      message = '单据要挂在仓库下面，建好仓库就能开始记账了';
    } else if (_selectedWarehouseId == null) {
      title = '还没有单据';
      message = '拍一张单据照片，剩下的交给识别';
    } else {
      title = '这个仓库还没有单据';
      message = '切到「全部」看看其他仓库，或者在这里新建一张';
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: CCTTEmptyState(
              icon: _searchKeyword.isNotEmpty
                  ? Icons.search_off
                  : _warehouses.isEmpty
                      ? Icons.warehouse_outlined
                      : Icons.receipt_long_outlined,
              title: title,
              message: message,
              action: _warehouses.isEmpty
                  ? SizedBox(
                      width: 200,
                      child: CCTTPrimaryButton(
                        label: '创建默认仓库',
                        icon: Icons.add_business,
                        onPressed: _createDefaultWarehouse,
                      ),
                    )
                  : null,
            ),
          ),
        );
      },
    );
  }
}

// ── 已作废单据列表页 ──
class _DeletedOrdersPage extends StatelessWidget {
  final List<OrderDetail> orders;
  final String Function(String) warehouseName;

  const _DeletedOrdersPage({
    required this.orders,
    required this.warehouseName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('已作废单据（${orders.length}）')),
      body: orders.isEmpty
          ? const CCTTEmptyState(
              icon: Icons.delete_sweep_outlined,
              title: '没有作废的单据',
              message: '作废的单据会留在这里，方便日后核对',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(CCTTTheme.space3),
              itemCount: orders.length,
              itemBuilder: (context, index) {
                final d = orders[index];
                return OrderCard(
                  detail: d,
                  warehouseName: warehouseName(d.order.warehouseId),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OrderDetailPage(orderId: d.order.id),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
