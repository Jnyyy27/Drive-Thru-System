import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

import 'auth_token_store.dart';

class ApiClient {
  ApiClient(this._tokenStore)
      : _dio = Dio(
          BaseOptions(
            baseUrl: const String.fromEnvironment(
              'API_BASE_URL',
              defaultValue: 'https://vehicleentrysystem.duckdns.org/api',
            ),
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 90),
            headers: const {'Accept': 'application/json'},
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _tokenStore.getIdToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  final AuthTokenStore _tokenStore;

  String get baseUrl => _dio.options.baseUrl;

  Future<Map<String, dynamic>> health() async {
    final response = await _dio.get('/health');
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> me() async {
    final response = await _dio.get('/me');
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> detectPlate(XFile image) async {
    final bytes = await image.readAsBytes();
    final formData = FormData.fromMap({
      'image': MultipartFile.fromBytes(
        bytes,
        filename: image.name,
        contentType: _mediaTypeFor(image.name, bytes),
      ),
    });

    final response = await _dio.post('/detect-plate', data: formData);
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> assistantChat({
    required String plateNumber,
    required String direction,
    required String message,
    List<Map<String, dynamic>>? history,
    List<Map<String, dynamic>>? menuItems,
  }) async {
    final response = await _dio.post(
      '/assistant-chat',
      data: <String, dynamic>{
        'plate_number': plateNumber,
        'direction': direction,
        'message': message,
        'history': history ?? const <Map<String, dynamic>>[],
        if (menuItems != null) 'menu_items': menuItems,
      },
    );
    return _asMap(response.data);
  }

  Future<String?> currentToken() => _tokenStore.getIdToken();

  Future<void> saveToken(String token) => _tokenStore.saveIdToken(token);

  Future<void> clearToken() => _tokenStore.clear();

  Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    return {'value': data};
  }

  MediaType _mediaTypeFor(String name, Uint8List bytes) {
    final mimeType =
        lookupMimeType(name, headerBytes: bytes.take(32).toList()) ?? 'image/jpeg';
    final parts = mimeType.split('/');
    return MediaType(parts.first, parts.length > 1 ? parts[1] : 'jpeg');
  }
}