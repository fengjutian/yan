import 'package:flutter/widgets.dart';

/// 全局路由观察者。
///
/// 相机页用它感知“被新页面覆盖/重新露出”，在页面不可见时暂停预览和
/// 图像分析，避免相机在后台页面继续占用 GPU 和相机流水线。
///
/// 使用 [Route] 而不是 [ModalRoute] 作为泛型，兼容 GoRouter 的
/// `MaterialPage<void>` 和各类弹层路由。
final RouteObserver<Route<dynamic>> appRouteObserver =
    RouteObserver<Route<dynamic>>();
