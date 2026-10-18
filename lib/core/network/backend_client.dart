import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class BackendConnectionException implements Exception {
  const BackendConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<http.Response> postJson(
  Uri uri,
  Map<String, dynamic> body, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  try {
    return await http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(timeout);
  } on HandshakeException {
    throw const BackendConnectionException(
      'Не удалось установить защищенное соединение с сервером. '
      'Похоже, у backend сейчас проблема с TLS/сертификатом.',
    );
  } on SocketException {
    throw const BackendConnectionException(
      'Не удалось подключиться к серверу. Проверь сеть и попробуй снова.',
    );
  } on TimeoutException {
    throw const BackendConnectionException(
      'Сервер слишком долго отвечает. Попробуй повторить запрос позже.',
    );
  } on http.ClientException {
    throw const BackendConnectionException(
      'Ошибка сетевого клиента при обращении к серверу.',
    );
  }
}
