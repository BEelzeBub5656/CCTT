import 'package:cctt/services/ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OcrResponse formal template parsing', () {
    test('maps summary fields, warnings and date', () {
      final response = OcrResponse.fromJson({
        'success': true,
        'document_type': 'formal',
        'warning': [
          '价格OCR值与净重、总金额不一致，已校正为9200元/吨',
        ],
        'orders': [
          {
            'partnerName': '俞晓宏',
            'type': 'outbound',
            'date_hint': '2026-02-25',
            'items': [
              {'itemName': '自保色', 'quantity': 126},
              {'itemName': '自保色', 'quantity': 125},
            ],
            'totalPieces': 2,
            'grossWeight': 251,
            'tareWeight': 2,
            'quantity': 249,
            'unitPrice': 9200,
            'totalAmount': 2290.8,
            'remark': '装货人：吴煜明',
          },
        ],
      });

      expect(response.documentType, 'formal');
      expect(response.warnings, hasLength(1));
      final order = response.firstOrder!;
      expect(order.partnerName, '俞晓宏');
      expect(order.type, 'outbound');
      expect(order.totalPieces, 2);
      expect(order.grossWeight, 251);
      expect(order.tareWeight, 2);
      expect(order.quantity, 249);
      expect(order.unitPrice, 9200);
      expect(order.totalAmount, 2290.8);
      expect(order.remark, '装货人：吴煜明');
      expect(order.parsedDate(), DateTime(2026, 2, 25));
    });

    test('converts per-piece gross weights to exact net weights', () {
      final order = OcrOrder.fromJson({
        'partnerName': '邹红亮',
        'type': 'outbound',
        'items': [
          {'itemName': '保色', 'quantity': 128},
          {'itemName': '保色', 'quantity': 126},
          {'itemName': '保色', 'quantity': 125},
        ],
        'grossWeight': 379,
        'tareWeight': 3,
        'quantity': 376,
        'unitPrice': 9500,
      });

      final items = order.normalizedItems(isFormal: true);

      expect(items, hasLength(3));
      expect(items.map((item) => item.grossWeight), [128, 126, 125]);
      expect(items.map((item) => item.tareWeight), [1, 1, 1]);
      expect(items.map((item) => item.quantity), [127, 125, 124]);
      expect(items.every((item) => item.unitPrice == 9500), isTrue);
      expect(items.every((item) => item.totalPieces == 1), isTrue);
      expect(
        items.fold<double>(0, (sum, item) => sum + item.grossWeight),
        379,
      );
      expect(
        items.fold<double>(0, (sum, item) => sum + item.tareWeight),
        3,
      );
      expect(
        items.fold<double>(0, (sum, item) => sum + item.quantity),
        376,
      );
    });

    test('keeps non-formal handwritten items unchanged', () {
      const order = OcrOrder(
        partnerName: '测试客户',
        type: 'inbound',
        unitPrice: 5000,
        items: [
          OcrItem(itemName: '回毛', quantity: 600, unitPrice: 4800),
        ],
      );

      final items = order.normalizedItems(isFormal: false);

      expect(items.single.quantity, 600);
      expect(items.single.grossWeight, 0);
      expect(items.single.tareWeight, 0);
      expect(items.single.unitPrice, 5000);
    });

    test('supports Chinese and short date hints', () {
      const chinese = OcrOrder(
        partnerName: '',
        type: 'outbound',
        dateHint: '2026年7月23日',
      );
      const short = OcrOrder(
        partnerName: '',
        type: 'outbound',
        dateHint: '7.23',
      );

      expect(chinese.parsedDate(), DateTime(2026, 7, 23));
      expect(
        short.parsedDate(referenceDate: DateTime(2026, 1, 1)),
        DateTime(2026, 7, 23),
      );
    });

    test('parses multiple handwritten orders and manual-fill hints', () {
      final response = OcrResponse.fromJson({
        'success': true,
        'document_type': 'handwritten',
        'orders': [
          {
            'partnerName': '客户甲',
            'type': 'supply',
            'date_hint': '2025-03-06',
            'items': [
              {
                'itemName': '回毛',
                'quantity': 1482.6,
                'unitPrice': 0,
                'itemRemark': '单价无法确定，请手动填写',
              },
            ],
            'warning': ['单价无法确定，请手动填写'],
          },
          {
            'partnerName': '',
            'type': 'supply',
            'date_hint': '2025-03-07',
            'items': [
              {
                'itemName': '',
                'quantity': 0,
                'unitPrice': 5200,
                'itemRemark': '重量无法确定，请手动填写',
              },
            ],
            'warnings': ['交易对象和重量无法确定，请手动填写'],
          },
        ],
      });

      expect(response.orders, hasLength(2));
      expect(response.orders.first.parsedDate(), DateTime(2025, 3, 6));
      expect(response.orders.first.warnings, hasLength(1));
      expect(response.orders.first.items.single.itemRemark, '单价无法确定，请手动填写');
      expect(response.orders.last.parsedDate(), DateTime(2025, 3, 7));
      expect(response.orders.last.partnerName, isEmpty);
      expect(response.orders.last.items.single.quantity, 0);
      expect(response.orders.last.warnings.single, contains('请手动填写'));
    });

    test('parses daily production rows as zero-price inbound orders', () {
      final response = OcrResponse.fromJson({
        'success': true,
        'document_type': 'production',
        'productionTotal': 1951,
        'orders': [
          {
            'partnerName': '本厂生产',
            'type': 'inbound',
            'date_hint': '2026-03-13',
            'items': [
              {'itemName': '', 'quantity': 927, 'unitPrice': 0},
            ],
            'remark': '生产入库',
          },
          {
            'partnerName': '本厂生产',
            'type': 'inbound',
            'date_hint': '2026-03-14',
            'items': [
              {'itemName': '', 'quantity': 1024, 'unitPrice': 0},
            ],
            'warning': ['右侧日产量未识别，已按当日明细重量合计'],
          },
        ],
      });

      expect(response.documentType, 'production');
      expect(response.orders, hasLength(2));
      expect(response.orders.first.partnerName, '本厂生产');
      expect(response.orders.first.type, 'inbound');
      expect(response.orders.first.parsedDate(), DateTime(2026, 3, 13));
      expect(response.orders.first.items.single.itemName, isEmpty);
      expect(response.orders.first.items.single.quantity, 927);
      expect(response.orders.first.items.single.unitPrice, 0);
      expect(response.orders.last.warnings.single, contains('明细重量合计'));
    });
  });
}
