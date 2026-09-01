import 'package:ai_image_studio/core/network/api_client.dart';
import 'package:ai_image_studio/core/storage/token_storage.dart';
import 'package:ai_image_studio/features/auth/data/auth_models.dart';
import 'package:ai_image_studio/features/auth/data/auth_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => SecureTokenStorage(),
);

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    apiClient: ref.watch(apiClientProvider),
    tokenStorage: ref.watch(tokenStorageProvider),
  ),
);

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>(
      (ref) => AuthController(ref.watch(authRepositoryProvider)),
    );

class AuthState {
  const AuthState({this.user, this.submitting = false, this.errorMessage});

  final AuthUser? user;
  final bool submitting;
  final String? errorMessage;

  AuthState copyWith({
    AuthUser? user,
    bool? submitting,
    String? errorMessage,
    bool clearError = false,
  }) => AuthState(
    user: user ?? this.user,
    submitting: submitting ?? this.submitting,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
  );
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository) : super(const AuthState());

  final AuthRepository _repository;

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
    state = const AuthState();
  }

  Future<bool> _submit(Future<AuthSession> Function() operation) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final session = await operation();
      state = AuthState(user: session.user);
      return true;
    } catch (error) {
      state = AuthState(errorMessage: error.toString());
      return false;
    }
  }
}

