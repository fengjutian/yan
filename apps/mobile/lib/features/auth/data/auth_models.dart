class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.nickname,
    required this.creditsBalance,
  });

  final String id;
  final String email;
  final String nickname;
  final int creditsBalance;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'] as String,
    email: json['email'] as String,
    nickname: json['nickname'] as String,
    creditsBalance: json['credits_balance'] as int,
  );
}

class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String,
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

