import 'package:ai_image_studio/core/network/api_client.dart';
import 'package:ai_image_studio/core/storage/token_storage.dart';
import 'package:ai_image_studio/features/auth/data/auth_models.dart';
import 'package:ai_image_studio/features/auth/data/auth_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => SecureTokenStorage(),
);

/// ApiClient 用这个 provider 拿到 session 失效回调。
/// 拆出独立 provider 是为了打破 apiClientProvider <-> authControllerProvider
/// 之间的循环依赖:apiClient 不再直接 watch authController,改为读一个
/// 单独的回调槽位,由 AuthController 启动时把自己写进去。
final sessionInvalidatedProvider = StateProvider<void Function()?>(
  (ref) => null,
);

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    tokenStorage: ref.watch(tokenStorageProvider),
    onSessionInvalidated: ref.watch(sessionInvalidatedProvider),
  ),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    apiClient: ref.watch(apiClientProvider),
    tokenStorage: ref.watch(tokenStorageProvider),
  ),
);

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) {
    final controller = AuthController(ref.watch(authRepositoryProvider));
    // 把 controller 的回调注入到 apiClient 看得见的槽位上。
    // 必须延后到当前 build phase 之外再写 sessionInvalidatedProvider,
    // 否则触发 "Providers are not allowed to modify other providers
    // during their initialization"。
    Future<void>.delayed(Duration.zero, () {
      ref.read(sessionInvalidatedProvider.notifier).state =
          controller.onSessionInvalidated;
    });
    return controller;
  },
);

class AuthState {
  const AuthState({
    this.user,
    this.initialized = false,
    this.submitting = false,
    this.errorMessage,
  });

  final AuthUser? user;
  final bool initialized;
  final bool submitting;
  final String? errorMessage;

  AuthState copyWith({
    AuthUser? user,
    bool? initialized,
    bool? submitting,
    String? errorMessage,
    bool clearError = false,
  }) =>
      AuthState(
        user: user ?? this.user,
        initialized: initialized ?? this.initialized,
        submitting: submitting ?? this.submitting,
        errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      );
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository) : super(const AuthState());

  final AuthRepository _repository;
  Future<void>? _initializing;

  Future<void> initialize() {
    if (state.initialized) return Future.value();
    return _initializing ??= _doInitialize().whenComplete(() {
      _initializing = null;
    });
  }

  Future<void> _doInitialize() async {
    try {
      var user = await _repository.restoreSession();
      if (user == null) {
        final session = await _repository.guest();
        user = session.user;
      }
      state = AuthState(user: user, initialized: true);
    } catch (error) {
      // 初始化失败时不要卡在 splash,带上错误但不阻塞后续 retry。
      state = AuthState(initialized: true, errorMessage: error.toString());
    }
  }

  Future<void> refreshProfile() async {
    // 简单的去重:30 秒内不重复打 /me
    final now = DateTime.now();
    if (now.difference(_lastRefreshAt).inSeconds < 30) return;
    _lastRefreshAt = now;
    try {
      final user = await _repository.restoreSession();
      if (user != null) {
        state = AuthState(user: user, initialized: true);
      }
    } catch (_) {
      // Keep the existing profile during a transient refresh failure.
    }
  }

  /// 来自 [ApiClient] 的 401 通知:refresh_token 已失效,强制进入未登录态。
  void onSessionInvalidated() {
    if (!state.initialized) return;
    state = AuthState(initialized: true, errorMessage: '登录已过期,请重新登录');
  }

  DateTime _lastRefreshAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<bool> login({required String email, required String password}) async {
    return _submit(() => _repository.login(email: email, password: password));
  }

  Future<bool> register({
    required String email,
    required String password,
    required String nickname,
  }) async {
    return _submit(
      () => _repository.register(
        email: email,
        password: password,
        nickname: nickname,
      ),
    );
  }

  Future<void> logout() async {
    await _repository.logout();
    state = const AuthState(initialized: true);
  }

  Future<bool> _submit(Future<AuthSession> Function() operation) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final session = await operation();
      state = AuthState(user: session.user, initialized: true);
      return true;
    } catch (error) {
      state = AuthState(initialized: true, errorMessage: error.toString());
      return false;
    }
  }
}
