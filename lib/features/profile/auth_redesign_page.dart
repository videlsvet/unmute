import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import '../../theme/app_theme.dart';

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
  final _confirmPasswordController = TextEditingController();

  bool _isRegisterMode = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nicknameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _switchMode(bool register) {
    if (_isRegisterMode == register) return;
    setState(() {
      _isRegisterMode = register;
      _error = null;
      _confirmPasswordController.clear();
    });
  }

  String _formatError(dynamic e) {
    final str = e.toString().replaceAll('Exception: ', '').trim();
    final lower = str.toLowerCase();
    if (lower.contains('user already exists')) {
      return 'Пользователь с таким ником уже существует. Попробуйте войти.';
    }
    if (lower.contains('wrong password')) {
      return 'Неверный пароль. Проверьте правильность ввода.';
    }
    if (lower.contains('user not found')) {
      return 'Пользователь не найден. Проверьте ник или зарегистрируйтесь.';
    }
    if (lower.contains('nickname and password required')) {
      return 'Введите ник и пароль.';
    }
    if (lower.contains('socketexception') || lower.contains('connection')) {
      return 'Нет связи с сервером. Проверьте подключение к интернету.';
    }
    return str.isNotEmpty ? str : 'Произошла ошибка. Попробуйте снова.';
  }

  Future<void> _submit() async {
    final nickname = _nicknameController.text.trim();
    final password = _passwordController.text.trim();

    if (nickname.isEmpty) {
      setState(() => _error = 'Введите никнейм');
      return;
    }
    if (nickname.length < 3) {
      setState(() => _error = 'Никнейм должен быть не менее 3 символов');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Введите пароль');
      return;
    }
    if (password.length < 4) {
      setState(() => _error = 'Пароль должен быть не менее 4 символов');
      return;
    }

    if (_isRegisterMode) {
      final confirmPassword = _confirmPasswordController.text.trim();
      if (confirmPassword != password) {
        setState(() => _error = 'Пароли не совпадают');
        return;
      }
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_isRegisterMode) {
        await widget.authService.register(
          nickname: nickname,
          password: password,
        );
      } else {
        await widget.authService.login(
          nickname: nickname,
          password: password,
        );
      }
      await widget.onLoggedIn();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _formatError(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 720;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 24 : 32,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App Icon / Logo
                  Center(
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppTheme.accent, AppTheme.accent2],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.accent.withValues(alpha: 0.35),
                            blurRadius: 28,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.music_note_rounded,
                        size: 40,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Brand Title
                  const Text(
                    'UNMUTE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isRegisterMode
                        ? 'Создайте аккаунт для синхронизации музыки'
                        : 'Сохраняй лайки, собирай плейлисты',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Segmented Switcher (Вход / Регистрация)
                  Container(
                    height: 48,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _loading ? null : () => _switchMode(false),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: !_isRegisterMode
                                    ? AppTheme.accent
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Вход',
                                style: TextStyle(
                                  color: !_isRegisterMode
                                      ? Colors.black
                                      : Colors.white.withValues(alpha: 0.7),
                                  fontSize: 15,
                                  fontWeight: !_isRegisterMode
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: _loading ? null : () => _switchMode(true),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _isRegisterMode
                                    ? AppTheme.accent
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Регистрация',
                                style: TextStyle(
                                  color: _isRegisterMode
                                      ? Colors.black
                                      : Colors.white.withValues(alpha: 0.7),
                                  fontSize: 15,
                                  fontWeight: _isRegisterMode
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Nickname Field
                  TextField(
                    controller: _nicknameController,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    cursorColor: AppTheme.accent,
                    decoration: InputDecoration(
                      hintText: 'Никнейм',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 15,
                      ),
                      prefixIcon: Icon(
                        Icons.person_outline_rounded,
                        color: Colors.white.withValues(alpha: 0.5),
                        size: 20,
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.08),
                          width: 1,
                        ),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                        borderSide: BorderSide(
                          color: AppTheme.accent,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Password Field
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: _isRegisterMode
                        ? TextInputAction.next
                        : TextInputAction.done,
                    onSubmitted: (_) {
                      if (!_isRegisterMode && !_loading) {
                        _submit();
                      }
                    },
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    cursorColor: AppTheme.accent,
                    decoration: InputDecoration(
                      hintText: 'Пароль',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 15,
                      ),
                      prefixIcon: Icon(
                        Icons.lock_outline_rounded,
                        color: Colors.white.withValues(alpha: 0.5),
                        size: 20,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: Colors.white.withValues(alpha: 0.5),
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.08),
                          width: 1,
                        ),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                        borderSide: BorderSide(
                          color: AppTheme.accent,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),

                  // Confirm Password Field (Register Mode Only)
                  if (_isRegisterMode) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirmPassword,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        if (!_loading) {
                          _submit();
                        }
                      },
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      cursorColor: AppTheme.accent,
                      decoration: InputDecoration(
                        hintText: 'Повторите пароль',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 15,
                        ),
                        prefixIcon: Icon(
                          Icons.lock_reset_rounded,
                          color: Colors.white.withValues(alpha: 0.5),
                          size: 20,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: Colors.white.withValues(alpha: 0.5),
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() => _obscureConfirmPassword =
                                !_obscureConfirmPassword);
                          },
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.08),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.08),
                            width: 1,
                          ),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(16)),
                          borderSide: BorderSide(
                            color: AppTheme.accent,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],

                  // Error Message Banner
                  if ((_error ?? '').isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.danger.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.danger.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppTheme.danger,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 28),

                  // Main Action Button (Войти / Зарегистрироваться)
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor:
                            AppTheme.accent.withValues(alpha: 0.5),
                        disabledForegroundColor: Colors.black45,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.black),
                              ),
                            )
                          : Text(
                              _isRegisterMode
                                  ? 'Создать аккаунт'
                                  : 'Войти в аккаунт',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Toggle mode text link
                  Center(
                    child: TextButton(
                      onPressed: _loading
                          ? null
                          : () => _switchMode(!_isRegisterMode),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                      ),
                      child: Text(
                        _isRegisterMode
                            ? 'Уже есть аккаунт? Войти'
                            : 'Впервые в UNMUTE? Создать аккаунт',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accent2,
                        ),
                      ),
                    ),
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
