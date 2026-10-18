import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import '../../widgets/app_header.dart';
import '../../widgets/glass_panel.dart';

class AuthRedesignPage extends StatefulWidget {
  const AuthRedesignPage({
    super.key,
    required this.authService,
    required this.onLoggedIn,
  });

  final AuthService authService;
  final Future<void> Function() onLoggedIn;

  @override
  State<AuthRedesignPage> createState() => _AuthRedesignPageState();
}

class _AuthRedesignPageState extends State<AuthRedesignPage> {
  final _nicknameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nicknameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await widget.authService.login(
        nickname: _nicknameController.text.trim(),
        password: _passwordController.text.trim(),
      );
      await widget.onLoggedIn();
    } catch (e) {
      _error = '$e';
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _register() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await widget.authService.register(
        nickname: _nicknameController.text.trim(),
        password: _passwordController.text.trim(),
      );
      await widget.onLoggedIn();
    } catch (e) {
      _error = '$e';
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: GlassPanel(
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF7C5CFF), Color(0xFF3949AB)],
                    ),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'UNMUTE account',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Сохраняй лайки, собирай плейлисты и синхронизируй музыкальную библиотеку между сессиями.',
                        style: TextStyle(
                          color: Color(0xE6FFFFFF),
                          fontSize: 15,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppHeader(
                      title: 'Вход в аккаунт',
                      subtitle: 'Подключись, чтобы хранить коллекции и управлять избранным.',
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _nicknameController,
                      decoration: const InputDecoration(labelText: 'Ник'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Пароль'),
                    ),
                    const SizedBox(height: 14),
                    if ((_error ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _loading ? null : _register,
                            child: const Text('Регистрация'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _loading ? null : _login,
                            child: _loading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Войти'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
