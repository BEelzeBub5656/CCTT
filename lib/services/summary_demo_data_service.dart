import '../data/database_helper.dart';
import '../models/order.dart';
import '../models/stock_movement.dart';
import '../models/warehouse.dart';

/// 仅供 Debug 包检查汇总页面使用的本地演示数据。
class SummaryDemoDataService {
  const SummaryDemoDataService._();

  static const warehouseId = 'summary-demo-warehouse';
  static const _orderIds = [
    'summary-demo-outbound',
    'summary-demo-inbound-a',
    'summary-demo-inbound-b',
    'summary-demo-supply-a',
    'summary-demo-supply-b',
    'summary-demo-supply-c',
    'summary-demo-deleted',
  ];

  /// 写入固定 ID 的测试数据。重复执行时会覆盖原测试数据，不会累积副本。
  static Future<int> seed() async {
    final db = DatabaseHelper.instance;
    await clear();
    await db.insertWarehouse(
      Warehouse(id: warehouseId, name: '汇总测试仓库'),
    );

    final now = DateTime.now();
    final orders = <_DemoOrder>[
      _DemoOrder(
        order: _order(
          id: _orderIds[0],
          partnerName: '上海出货客户',
          type: MovementType.outbound,
          timestamp: _dayInCurrentMonth(now, 2),
        ),
        items: [
          _item('outbound-wool', _orderIds[0], '白羊毛', 1000, 6800, 0),
          _item('outbound-grey', _orderIds[0], '灰羊毛', 650, 6200, 1),
        ],
        fees: [
          _fee('outbound-freight', _orderIds[0], '运费', 300),
        ],
      ),
      _DemoOrder(
        order: _order(
          id: _orderIds[1],
          partnerName: '一号仓库转入',
          type: MovementType.inbound,
          timestamp: _dayInCurrentMonth(now, 6),
        ),
        items: [
          _item('inbound-a-recycled', _orderIds[1], '回毛', 1400, 4200, 0),
          _item('inbound-a-silk', _orderIds[1], '回丝', 800, 4800, 1),
        ],
        fees: [
          _fee('inbound-a-handling', _orderIds[1], '搬运费', 100),
        ],
      ),
      _DemoOrder(
        order: _order(
          id: _orderIds[2],
          partnerName: '二号仓库转入',
          type: MovementType.inbound,
          timestamp: _dayInCurrentMonth(now, 10),
        ),
        items: [
          _item('inbound-b-recycled', _orderIds[2], '回毛', 600, 4300, 0),
          _item('inbound-b-polyester', _orderIds[2], '涤纶', 1000, 3900, 1),
        ],
      ),
      _DemoOrder(
        order: _order(
          id: _orderIds[3],
          partnerName: '老朱',
          type: MovementType.supply,
          timestamp: _dayInCurrentMonth(now, 14),
        ),
        items: [
          _item('supply-a-recycled', _orderIds[3], '回毛', 1200, 5200, 0),
          _item('supply-a-silk', _orderIds[3], '回丝', 700, 4600, 1),
        ],
        fees: [
          _fee('supply-a-forklift', _orderIds[3], '铲车费', 200),
        ],
      ),
      _DemoOrder(
        order: _order(
          id: _orderIds[4],
          partnerName: '老朱',
          type: MovementType.supply,
          timestamp: _dayInCurrentMonth(now, 18),
        ),
        items: [
          _item('supply-b-recycled', _orderIds[4], '回毛', 300, 5300, 0),
        ],
      ),
      _DemoOrder(
        order: _order(
          id: _orderIds[5],
          partnerName: '宿迁供应商',
          type: MovementType.supply,
          timestamp: _dayInCurrentMonth(now, 20),
        ),
        items: [
          _item('supply-c-polyester', _orderIds[5], '涤纶', 2300, 3900, 0),
          _item('supply-c-recycled', _orderIds[5], '回毛', 600, 5100, 1),
        ],
        fees: [
          _fee('supply-c-freight', _orderIds[5], '运费', 350),
        ],
      ),
      _DemoOrder(
        order: _order(
          id: _orderIds[6],
          partnerName: '作废测试客户',
          type: MovementType.supply,
          timestamp: _dayInCurrentMonth(now, 21),
          isDeleted: true,
          voidReason: '用于验证汇总排除作废单据',
        ),
        items: [
          _item('deleted-item', _orderIds[6], '不应计入汇总', 99999, 99999, 0),
        ],
      ),
    ];

    for (final demo in orders) {
      await db.insertOrder(demo.order);
      for (final item in demo.items) {
        await db.insertOrderItem(item);
      }
      for (final fee in demo.fees) {
        await db.insertOrderFee(fee);
      }
    }
    return orders.length;
  }

  static Future<void> clear() async {
    final db = DatabaseHelper.instance;
    for (final orderId in _orderIds) {
      await db.deleteOrder(orderId);
    }
    try {
      await db.deleteWarehouse(warehouseId);
    } catch (_) {
      // 仓库仍被非测试单据引用时保留，避免影响用户数据。
    }
  }

  static Order _order({
    required String id,
    required String partnerName,
    required MovementType type,
    required int timestamp,
    bool isDeleted = false,
    String? voidReason,
  }) {
    return Order(
      id: id,
      partnerName: partnerName,
      warehouseId: warehouseId,
      type: type,
      timestamp: timestamp,
      syncStatus: SyncStatus.synced,
      isDeleted: isDeleted,
      isSettled: true,
      remark: '汇总页面 Debug 测试数据',
      voidReason: voidReason,
    );
  }

  static OrderItem _item(
    String id,
    String orderId,
    String itemName,
    double quantity,
    double unitPrice,
    int sortOrder,
  ) {
    return OrderItem(
      id: 'summary-demo-$id',
      orderId: orderId,
      itemName: itemName,
      quantity: quantity,
      unitPrice: unitPrice,
      sortOrder: sortOrder,
    );
  }

  static OrderFee _fee(
    String id,
    String orderId,
    String feeName,
    double amount,
  ) {
    return OrderFee(
      id: 'summary-demo-$id',
      orderId: orderId,
      feeName: feeName,
      amount: amount,
    );
  }

  static int _dayInCurrentMonth(DateTime now, int preferredDay) {
    final day = preferredDay > now.day ? now.day : preferredDay;
    return DateTime(now.year, now.month, day, 12).millisecondsSinceEpoch;
  }
}

class _DemoOrder {
  final Order order;
  final List<OrderItem> items;
  final List<OrderFee> fees;

  const _DemoOrder({
    required this.order,
    required this.items,
    this.fees = const [],
  });
}
