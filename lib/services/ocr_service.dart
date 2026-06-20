import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'settings_service.dart';

/// OCR 识别结果中的单条货物明细
class OcrItem {
  final String itemName;
  final double quantity;   // 净重(kg)
  final double unitPrice;  // 元/吨
  final double grossWeight;
  final double tareWeight;
  final int? totalPieces;
  final String? deliveryPerson;

  const OcrItem({
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    this.grossWeight = 0,
    this.tareWeight = 0,
    this.totalPieces,
    this.deliveryPerson,
  });

  factory OcrItem.fromJson(Map<String, dynamic> json) => OcrItem(
        itemName: (json['itemName'] as String?) ?? '',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
        grossWeight: (json['grossWeight'] as num?)?.toDouble() ?? 0,
        tareWeight: (json['tareWeight'] as num?)?.toDouble() ?? 0,
        totalPieces: (json['totalPieces'] as num?)?.toInt(),
        deliveryPerson: json['deliveryPerson'] as String?,
      );
}

/// OCR 识别结果中的额外费用
class OcrFee {
  final String feeName;
  final double amount;

  const OcrFee({required this.feeName, required this.amount});

  factory OcrFee.fromJson(Map<String, dynamic> json) => OcrFee(
        feeName: (json['feeName'] as String?) ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
      );
}

/// OCR 识别的一张单据
class OcrOrder {
  final String partnerName;
  final String type;       // inbound / outbound / supply
  final String? dateHint;  // 如 "4.22"，仅供参考
  final List<OcrItem> items;
  final List<OcrFee> fees;

  const OcrOrder({
    required this.partnerName,
    required this.type,
    this.dateHint,
    this.items = const [],
    this.fees = const [],
  });

  factory OcrOrder.fromJson(Map<String, dynamic> json) => OcrOrder(
        partnerName: (json['partnerName'] as String?) ?? '',
        type: (json['type'] as String?) ?? 'inbound',
        dateHint: json['date_hint'] as String?,
        items: (json['items'] as List<dynamic>?)
                ?.map((e) => OcrItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        fees: (json['fees'] as List<dynamic>?)
                ?.map((e) => OcrFee.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

/// OCR API 完整响应
class OcrResponse {
  final bool success;
  final List<OcrOrder> orders;
  final List<Map<String, dynamic>>? rawTexts;
  final String? documentType;
  final String? error;

  const OcrResponse({
    required this.success,
    this.orders = const [],
    this.rawTexts,
    this.documentType,
    this.error,
  });

  factory OcrResponse.fromJson(Map<String, dynamic> json) => OcrResponse(
        success: json['success'] == true,
        orders: (json['orders'] as List<dynamic>?)
                ?.map((e) => OcrOrder.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        rawTexts: (json['raw_texts'] as List<dynamic>?)
            ?.map((e) => e as Map<String, dynamic>)
            .toList(),
        documentType: json['document_type'] as String?,
        error: json['error'] as String?,
      );

  /// 获取第一张识别到的单据（常用于单张拍照场景）
  OcrOrder? get firstOrder => orders.isNotEmpty ? orders.first : null;
}

/// 云端 OCR 识别服务（PP-OCRv6）
///
/// 拍照 → POST multipart 上传 → 解析结构化数据
class OcrService {
  OcrService._();

  /// 上传图片并返回 OCR 识别结果。
  ///
  /// 读取 [SettingsService.getOcrServerUrl] 作为 API 地址，
  /// 以 multipart/form-data 方式 POST 到 `/api/ocr`。
  /// 30 秒超时，失败时抛出 [OcrException]。
  static Future<OcrResponse> recognize(File image) async {
    final baseUrl = await SettingsService.getOcrServerUrl();
    if (baseUrl.isEmpty) {
      throw OcrException('OCR 服务器地址未配置');
    }

    final url = Uri.parse('$baseUrl/api/ocr');
    final request = http.MultipartRequest('POST', url)
      ..files.add(await http.MultipartFile.fromPath('image', image.path));

    http.StreamedResponse response;
    try {
      response = await request.send().timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw OcrException('OCR 服务响应超时，请稍后重试'),
          );
    } on OcrException {
      rethrow;
    } on SocketException {
      throw OcrException('网络连接失败，请检查网络设置');
    } on HandshakeException {
      throw OcrException('网络连接失败，请检查网络设置');
    } on TlsException {
      throw OcrException('网络连接失败，请检查网络设置');
    }

    if (response.statusCode != 200) {
      throw OcrException('服务器错误 (${response.statusCode})，请稍后重试');
    }

    final body = await response.stream.transform(utf8.decoder).join();
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return OcrResponse.fromJson(json);
    } on FormatException {
      throw OcrException('OCR 返回数据异常');
    }
  }
}

/// OCR 异常
class OcrException implements Exception {
  final String message;
  const OcrException(this.message);

  @override
  String toString() => 'OcrException: $message';
}
