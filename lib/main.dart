import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'pages/home_page.dart';
import 'services/storage_cleanup_service.dart';
import 'theme/cctt_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await StorageCleanupService.runAfterUpgrade();
  } catch (_) {
    // 清理失败不能阻止 App 启动，下个版本仍会再次尝试。
  }
  runApp(const CcttApp());
}

class CcttApp extends StatelessWidget {
  const CcttApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CCTT',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      theme: buildCcttTheme(),
      home: const HomePage(),
    );
  }
}
