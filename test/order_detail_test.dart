import 'package:cctt/models/order.dart';
import 'package:cctt/models/stock_movement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('totalQuantity sums original item quantity values only', () {
    final order = Order(
      id: 'order-1',
      partnerName: '供应商',
      warehouseId: 'warehouse-1',
      type: MovementType.inbound,
      timestamp: 1,
    );
    final detail = OrderDetail(
      order: order,
      items: [
        OrderItem(
          id: 'item-1',
          orderId: order.id,
          itemName: '回丝',
          quantity: 1482.6,
          unitPrice: 5500,
        ),
        OrderItem(
          id: 'item-2',
          orderId: order.id,
          itemName: '回毛',
          quantity: 2820.8,
          unitPrice: 5800,
        ),
      ],
      fees: [
        OrderFee(orderId: order.id, feeName: '运费', amount: 200),
      ],
    );

    expect(detail.totalQuantity, 4303.4);
  });
}