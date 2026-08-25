import 'package:cctt/models/order.dart';
import 'package:cctt/models/stock_movement.dart';
import 'package:cctt/services/summary_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('按类型、客户和品类汇总并排除作废及日期外单据', () {
    final details = [
      _detail(
        id: 'outbound',
        date: DateTime(2026, 8, 5),
        type: MovementType.outbound,
        partnerName: '出货客户',
        items: [
          _item('outbound', '羊毛', 1000, 2000),
        ],
        fees: [_fee('outbound', 100)],
      ),
      _detail(
        id: 'inbound',
        date: DateTime(2026, 8, 10),
        type: MovementType.inbound,
        partnerName: '仓库来源',
        items: [
          _item('inbound', '回毛', 500, 3000),
          _item('inbound', '回毛', 250, 3000),
          _item('inbound', '回丝', 100, 4000),
        ],
      ),
      _detail(
        id: 'supply-a',
        date: DateTime(2026, 8, 15, 23, 59),
        type: MovementType.supply,
        partnerName: '张三',
        items: [
          _item('supply-a', '回毛', 800, 2500),
          _item('supply-a', '回丝', 200, 3500),
        ],
        fees: [_fee('supply-a', 50)],
      ),
      _detail(
        id: 'deleted',
        date: DateTime(2026, 8, 12),
        type: MovementType.supply,
        partnerName: '张三',
        isDeleted: true,
        items: [_item('deleted', '不应统计', 9999, 9999)],
      ),
      _detail(
        id: 'outside',
        date: DateTime(2026, 7, 31, 23, 59),
        type: MovementType.outbound,
        partnerName: '日期外',
        items: [_item('outside', '不应统计', 9999, 9999)],
      ),
    ];

    final report = SummaryService.buildReport(
      orderDetails: details,
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 15),
    );

    expect(report.outbound.orderCount, 1);
    expect(report.outbound.totalWeight, 1000);
    expect(report.outbound.itemAmount, 2000);
    expect(report.outbound.feeAmount, 100);
    expect(report.outbound.totalAmount, 2100);

    expect(report.inbound.orderCount, 1);
    expect(report.inbound.totalWeight, 850);
    expect(report.inboundCategories.map((c) => c.name), ['回毛', '回丝']);
    expect(report.inboundCategories.first.totalWeight, 750);
    expect(report.inboundCategories.first.amount, 2250);

    expect(report.supply.orderCount, 1);
    expect(report.supply.totalWeight, 1000);
    expect(report.supply.totalAmount, 2750);
    expect(report.supplyPartners, hasLength(1));
    expect(report.supplyPartners.single.partnerName, '张三');
    expect(report.supplyPartners.single.categories.map((c) => c.name),
        ['回毛', '回丝']);
  });

  test('拒绝开始日期晚于结束日期', () {
    expect(
      () => SummaryService.buildReport(
        orderDetails: const [],
        startDate: DateTime(2026, 8, 2),
        endDate: DateTime(2026, 8, 1),
      ),
      throwsArgumentError,
    );
  });
}

OrderDetail _detail({
  required String id,
  required DateTime date,
  required MovementType type,
  required String partnerName,
  List<OrderItem> items = const [],
  List<OrderFee> fees = const [],
  bool isDeleted = false,
}) {
  return OrderDetail(
    order: Order(
      id: id,
      partnerName: partnerName,
      warehouseId: 'warehouse',
      type: type,
      timestamp: date.millisecondsSinceEpoch,
      isDeleted: isDeleted,
    ),
    items: items,
    fees: fees,
  );
}

OrderItem _item(
  String orderId,
  String itemName,
  double quantity,
  double unitPrice,
) {
  return OrderItem(
    orderId: orderId,
    itemName: itemName,
    quantity: quantity,
    unitPrice: unitPrice,
  );
}

OrderFee _fee(String orderId, double amount) {
  return OrderFee(orderId: orderId, feeName: '费用', amount: amount);
}
