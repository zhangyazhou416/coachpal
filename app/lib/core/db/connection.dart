/// 平台差异收敛：移动/桌面用文件库，Web 用 wasm 数据库。
///
/// 鸿蒙（OHOS 分支）走与 Android 相同的 io 路径。
export 'connection_stub.dart'
    if (dart.library.io) 'connection_io.dart'
    if (dart.library.html) 'connection_web.dart';
