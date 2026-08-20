import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

import 'auth_token_store.dart';

class ApiClient {
  ApiClient(this._tokenStore, {this.onUnauthorized})
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
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            await _tokenStore.clear();
            onUnauthorized?.call();
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;
  final AuthTokenStore _tokenStore;

  /// Called when the server returns 401 (token expired / invalid).
  final void Function()? onUnauthorized;

  String get baseUrl => _dio.options.baseUrl;

  Future<Map<String, dynamic>> health() async {
    final response = await _dio.get('/health');
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> me() async {
    final response = await _dio.get('/me');
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> dashboardSummary() async {
    final response = await _dio.get('/dashboard');
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> menu() async {
    final response = await _dio.get('/menu');
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> logs() async {
    final response = await _dio.get('/logs');
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> ordersDisplay() async {
    final response = await _dio.get('/orders/display');
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> orderCart({required String plateNumber}) async {
    final response = await _dio.get(
      '/orders/cart',
      queryParameters: <String, dynamic>{'plate_number': plateNumber},
    );
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> addCartItem({
    required String plateNumber,
    required int menuId,
    int quantity = 1,
  }) async {
    final response = await _dio.post(
      '/orders/cart/items',
      data: <String, dynamic>{
        'plate_number': plateNumber,
        'menu_id': menuId,
        'quantity': quantity,
      },
    );
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> updateCartItemQuantity({
    required String plateNumber,
    required int menuId,
    required int quantity,
  }) async {
    final response = await _dio.patch(
      '/orders/cart/items',
      data: <String, dynamic>{
        'plate_number': plateNumber,
        'menu_id': menuId,
        'quantity': quantity,
      },
    );
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> confirmCartOrder({
    required String plateNumber,
  }) async {
    final response = await _dio.post(
      '/orders/cart/confirm',
      data: <String, dynamic>{'plate_number': plateNumber},
    );
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

  Future<Map<String, dynamic>> submitEntry({
    required String plateNumber,
  }) async {
    final response = await _dio.post(
      '/entry',
      data: <String, dynamic>{'plate_number': plateNumber},
    );
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
        ...?menuItems == null
            ? null
            : <String, dynamic>{'menu_items': menuItems},
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
        lookupMimeType(name, headerBytes: bytes.take(32).toList()) ??
        'image/jpeg';
    final parts = mimeType.split('/');
    return MediaType(parts.first, parts.length > 1 ? parts[1] : 'jpeg');
  }
}
