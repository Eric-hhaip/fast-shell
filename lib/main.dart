import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_store.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final store = AppStore();
  // 先后台拉起界面（首帧立刻可见），再异步读加密仓库：
  // 解密要跑 HKDF + AES-GCM，还要 spawn ioreg 取设备 UUID，
  // 这些都不该挡在窗口出现之前。SidebarView 会按 store.ready 显示载入态。
  runApp(HhaipShellApp(store: store));
  unawaited(store.init());
}

class HhaipShellApp extends StatelessWidget {
  const HhaipShellApp({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppStore>.value(
      value: store,
      child: MaterialApp(
        title: 'Fast Shell',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const HomePage(),
      ),
    );
  }
}
