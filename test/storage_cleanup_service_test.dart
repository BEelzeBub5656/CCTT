import 'dart:io';

import 'package:cctt/services/storage_cleanup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('StorageCleanupService', () {
    late Directory sandbox;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('cctt_cleanup_test_');
    });

    tearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });

    test('only deletes generated OCR images and CCTT update APKs', () async {
      final documents = Directory(p.join(sandbox.path, 'documents'));
      final ocrTemp = Directory(p.join(documents.path, 'ocr_temp'));
      final external = Directory(p.join(sandbox.path, 'external'));
      final businessPhotos = Directory(p.join(documents.path, 'order_photos'));
      await ocrTemp.create(recursive: true);
      await external.create(recursive: true);
      await businessPhotos.create(recursive: true);

      final ocrImage = File(p.join(
        ocrTemp.path,
        'ocr_123e4567-e89b-12d3-a456-426614174000.jpg',
      ));
      final oldApk = File(p.join(external.path, 'cctt-0.1.6.apk'));
      final database = File(p.join(documents.path, 'cctt.db'));
      final businessPhoto = File(p.join(businessPhotos.path, 'order.jpg'));
      final unrelatedOcrFile = File(p.join(ocrTemp.path, 'manual-note.txt'));
      final unrelatedApk = File(p.join(external.path, 'other-app.apk'));
      for (final file in [
        ocrImage,
        oldApk,
        database,
        businessPhoto,
        unrelatedOcrFile,
        unrelatedApk,
      ]) {
        await file.writeAsString('test');
      }

      final result = await StorageCleanupService.cleanupManagedFiles(
        documentsDirectory: documents,
        externalDirectory: external,
      );

      expect(result.deletedFiles, 2);
      expect(result.failedFiles, 0);
      expect(await ocrImage.exists(), isFalse);
      expect(await oldApk.exists(), isFalse);
      expect(await database.exists(), isTrue);
      expect(await businessPhoto.exists(), isTrue);
      expect(await unrelatedOcrFile.exists(), isTrue);
      expect(await unrelatedApk.exists(), isTrue);
    });

    test('missing managed directories are safe no-ops', () async {
      final result = await StorageCleanupService.cleanupManagedFiles(
        documentsDirectory: Directory(p.join(sandbox.path, 'missing')),
      );

      expect(result.deletedFiles, 0);
      expect(result.failedFiles, 0);
    });
  });
}
