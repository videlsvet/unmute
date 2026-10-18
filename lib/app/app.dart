import 'package:flutter/material.dart';

import '../core/models/track.dart';
import '../core/services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_mark.dart';
import '../widgets/premium_components.dart';
import 'unmute_shell.dart';

class UnmuteApp extends StatelessWidget {
  const UnmuteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UNMUTE',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: AppTheme.dark(),
      home: const _AppBootstrap(),
    );
  }
}

class _BootstrapState {
  const _BootstrapState({
    required this.token,
    required this.favorites,
  });

  final String? token;
  final List<Track> favorites;
}

class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  final AuthService _authService = AuthService();
  late final Future<_BootstrapState> _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = _loadBootstrapState();
  }

  Future<_BootstrapState> _loadBootstrapState() async {
    final token = await _authService.getSavedToken();
    if (token == null || token.isEmpty) {
      return const _BootstrapState(token: null, favorites: []);
    }

    try {
      await _authService.getProfile(token);
      final favorites = await _authService.listFavorites(token);
      return _BootstrapState(token: token, favorites: favorites);
    } catch (_) {
      await _authService.logout();
      return const _BootstrapState(token: null, favorites: []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BootstrapState>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StartupScreen();
        }

        final state =
            snapshot.data ?? const _BootstrapState(token: null, favorites: []);
        return UnmuteShell(
          initialToken: state.token,
          initialFavorites: state.favorites,
        );
      },
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DynamicGradientBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: PremiumSurface(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
              radius: AppTheme.radiusXl,
              color: AppTheme.surface.withValues(alpha: 0.82),
              shadow: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandMark(size: 76, padding: 12),
                  const SizedBox(height: 20),
                  Text(
                    'UNMUTE',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Загружаем аккаунт, избранное и стартовое состояние приложения.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 22),
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.6),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
