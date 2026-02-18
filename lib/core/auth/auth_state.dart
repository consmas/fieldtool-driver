enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final String? token;
  final String? error;

  const AuthState({
    required this.status,
    this.token,
    this.error,
  });

  const AuthState.unknown() : this(status: AuthStatus.unknown);
  const AuthState.unauthenticated([String? error])
      : this(status: AuthStatus.unauthenticated, error: error);
  const AuthState.authenticated(String token)
      : this(status: AuthStatus.authenticated, token: token);
}
