class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.nickname,
    required this.creditsBalance,
    this.role = 'USER',
  });

  final String id;
  final String email;
  final String nickname;
  final int creditsBalance;
  final String role;

  bool get isGuest => role == 'GUEST';

  /// 独立客户端在无法连接后端时使用的本地游客身份。
  factory AuthUser.localGuest() => const AuthUser(
    id: 'local-guest',
    email: '',
    nickname: '游客',
    creditsBalance: 0,
    role: 'GUEST',
  );

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: (json['id'] as String?) ?? '',
    email: (json['email'] as String?) ?? '',
    nickname: (json['nickname'] as String?) ?? '',
    creditsBalance: (json['credits_balance'] is int)
        ? json['credits_balance'] as int
        : (json['credits_balance'] is num)
        ? (json['credits_balance'] as num).round()
        : 0,
    role: (json['role'] as String?) ?? 'USER',
  );
}

class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
    accessToken: (json['access_token'] as String?) ?? '',
    refreshToken: (json['refresh_token'] as String?) ?? '',
  );
}

class AuthSession {
  const AuthSession({required this.user, required this.tokens});

  final AuthUser user;
  final AuthTokens tokens;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
    tokens: AuthTokens.fromJson(json['tokens'] as Map<String, dynamic>),
  );
}
