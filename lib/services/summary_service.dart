import '../data/database_helper.dart';
import '../models/order.dart';
import '../models/stock_movement.dart';

/// 汇总页使用的总计数据。
class SummaryTotals {
  final int orderCount;
  final int itemCount;
  final double totalWeight;
  final double itemAmount;
  final double feeAmount;

  const SummaryTotals({
    required this.orderCount,
    required this.itemCount,
    required this.totalWeight,
    required this.itemAmount,
    required this.feeAmount,
  });

  double get totalAmount => itemAmount + feeAmount;
  bool get isEmpty => orderCount == 0;
}

/// 单个品类的明细汇总。品类金额不包含无法归属到具体品类的额外费用。
class CategorySummary {
  final String name;
  final int itemCount;
  final double totalWeight;
  final double amount;

  const CategorySummary({
    required this.name,
    required this.itemCount,
    required this.totalWeight,
    required this.amount,
  });
}

/// 单个进货客户的总计和品类明细。
class PartnerSummary {
  final String partnerName;
  final SummaryTotals totals;
  final List<CategorySummary> categories;

  const PartnerSummary({
    required this.partnerName,
    required this.totals,
    required this.categories,
  });
}

/// 指定日期范围内生成的完整汇总表。
class SummaryReport {
  final DateTime startDate;
  final DateTime endDate;
  final SummaryTotals outbound;
  final SummaryTotals inbound;
  final List<CategorySummary> inboundCategories;
  final SummaryTotals supply;
  final List<PartnerSummary> supplyPartners;

  const SummaryReport({
    required this.startDate,
    required this.endDate,
    required this.outbound,
    required this.inbound,
    required this.inboundCategories,
    required this.supply,
    required this.supplyPartners,
  });
}

class SummaryService {
  const SummaryService._();

  /// 从本地数据库读取完整 Order 数据并生成汇总表。
  static Future<SummaryReport> generate({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final db = DatabaseHelper.instance;
    final orders = await db.getAllOrders();
    final details = <OrderDetail>[];

    for (final order in orders) {
      details.add(
        OrderDetail(
          order: order,
          items: await db.getOrderItems(order.id),
          fees: await db.getOrderFees(order.id),
        ),
      );
    }

    return buildReport(
      orderDetails: details,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// 纯计算入口，便于测试统计口径。
  static SummaryReport buildReport({
    required List<OrderDetail> orderDetails,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    if (start.isAfter(end)) {
      throw ArgumentError('开始日期不能晚于结束日期');
    }
    final endExclusive = end.add(const Duration(days: 1));

    final outbound = _TotalsAccumulator();
    final inbound = _TotalsAccumulator();
    final inboundCategories = <String, _CategoryAccumulator>{};
    final supply = _TotalsAccumulator();
    final supplyPartners = <String, _PartnerAccumulator>{};

    for (final detail in orderDetails) {
      final order = detail.order;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(order.timestamp);
      if (order.isDeleted ||
          timestamp.isBefore(start) ||
          !timestamp.isBefore(endExclusive)) {
        continue;
      }

      switch (order.type) {
        case MovementType.outbound:
          outbound.addOrder(detail);
        case MovementType.inbound:
          inbound.addOrder(detail);
          _addItemsToCategories(inboundCategories, detail.items);
        case MovementType.supply:
          supply.addOrder(detail);
          final partnerName = _normalizedLabel(order.partnerName, '未填写客户');
          final partner = supplyPartners.putIfAbsent(
            partnerName,
            () => _PartnerAccumulator(partnerName),
          );
          partner.addOrder(detail);
      }
    }

    final inboundCategoryList = inboundCategories.values
        .map((category) => category.freeze())
        .toList()
      ..sort(_compareCategories);
    final partnerList = supplyPartners.values
        .map((partner) => partner.freeze())
        .toList()
      ..sort((a, b) => a.partnerName.compareTo(b.partnerName));

    return SummaryReport(
      startDate: start,
      endDate: end,
      outbound: outbound.freeze(),
      inbound: inbound.freeze(),
      inboundCategories: inboundCategoryList,
      supply: supply.freeze(),
      supplyPartners: partnerList,
    );
  }

  static void _addItemsToCategories(
    Map<String, _CategoryAccumulator> categories,
    List<OrderItem> items,
  ) {
    for (final item in items) {
      final name = _normalizedLabel(item.itemName, '未分类');
      categories.putIfAbsent(name, () => _CategoryAccumulator(name)).add(item);
    }
  }

  static String _normalizedLabel(String value, String fallback) {
    final normalized = value.trim();
    return normalized.isEmpty ? fallback : normalized;
  }

  static int _compareCategories(CategorySummary a, CategorySummary b) {
    final weightOrder = b.totalWeight.compareTo(a.totalWeight);
    return weightOrder != 0 ? weightOrder : a.name.compareTo(b.name);
  }
}

class _TotalsAccumulator {
  int orderCount = 0;
  int itemCount = 0;
  double totalWeight = 0;
  double itemAmount = 0;
  double feeAmount = 0;

  void addOrder(OrderDetail detail) {
    orderCount++;
    itemCount += detail.items.length;
    for (final item in detail.items) {
      totalWeight += item.quantity;
      itemAmount += item.amount;
    }
    for (final fee in detail.fees) {
      feeAmount += fee.amount;
    }
  }

  SummaryTotals freeze() => SummaryTotals(
        orderCount: orderCount,
        itemCount: itemCount,
        totalWeight: totalWeight,
        itemAmount: itemAmount,
        feeAmount: feeAmount,
      );
}

class _CategoryAccumulator {
  final String name;
  int itemCount = 0;
  double totalWeight = 0;
  double amount = 0;

  _CategoryAccumulator(this.name);

  void add(OrderItem item) {
    itemCount++;
    totalWeight += item.quantity;
    amount += item.amount;
  }

  CategorySummary freeze() => CategorySummary(
        name: name,
        itemCount: itemCount,
        totalWeight: totalWeight,
        amount: amount,
      );
}

class _PartnerAccumulator {
  final String partnerName;
  final _TotalsAccumulator totals = _TotalsAccumulator();
  final Map<String, _CategoryAccumulator> categories = {};

  _PartnerAccumulator(this.partnerName);

  void addOrder(OrderDetail detail) {
    totals.addOrder(detail);
    SummaryService._addItemsToCategories(categories, detail.items);
  }

  PartnerSummary freeze() {
    final categoryList = categories.values
        .map((category) => category.freeze())
        .toList()
      ..sort(SummaryService._compareCategories);
    return PartnerSummary(
      partnerName: partnerName,
      totals: totals.freeze(),
      categories: categoryList,
    );
  }
}
