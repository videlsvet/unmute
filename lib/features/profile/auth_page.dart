import 'package:flutter/material.dart';
import '../../core/services/auth_service.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    required this.authService,
    required this.onLoggedIn,
  });

  final AuthService authService;
  final Future<void> Function() onLoggedIn;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
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
    setState(() {
      _loading = false;
    });
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
    setState(() {
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFF131722),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFF232838)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Вход в аккаунт', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 18),
            TextField(
              controller: _nicknameController,
              decoration: const InputDecoration(
                labelText: 'Ник',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Пароль',
              ),
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
    );
  }
}