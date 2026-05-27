import 'dart:io' show Cookie; // 🔥 [CRITICAL] Cookie.fromSetCookieValue သုံးရန် လိုအပ်သည်
import 'package:apiclient/src/model.dart'
    show RPCAuthResponse, ClientGetRequest, RPCCompany, ClientListResponse, ClientResponse, ClientRPCPostRequest, QueryParamSerializable, OdooErrorResponse;
import 'package:dio/dio.dart' show Dio, DioException, DioExceptionType, Options, QueuedInterceptorsWrapper;
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/rendering.dart' show debugPrint;

/// Base Service Client with Fully Auto Encrypted Session Refresh
abstract class ApiClientService {
  // Main dio client instance
  final Dio dio = Dio();
  final CookieJar cookieJar = CookieJar();

  // 🔥 iOS/Android အတွက် ပိုမိုလုံခြုံသော Encrypted Storage Instance
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // Storage Keys Constants
  static const String _keyUsername = 'odoo_saved_username';
  static const String _keyPassword = 'odoo_saved_password';
  static const String _keyDatabase = 'odoo_saved_database';
  static const String _keyBaseUrl = 'odoo_saved_base_url';

  ApiClientService() {
    // Base Timeout Settings
    dio.options.connectTimeout = const Duration(seconds: 15);
    dio.options.receiveTimeout = const Duration(seconds: 15);

    // CookieManager ထည့်သွင်းခြင်း
    dio.interceptors.add(CookieManager(cookieJar));

    // Session သက်တမ်းကုန်ပါက ကြားဖြတ်ဖမ်းယူမည့် Interceptor Logic
    dio.interceptors.add(
      QueuedInterceptorsWrapper(
        onResponse: (response, handler) async {
          // Retry Request ဖြစ်ပါက ထပ်မစစ်ဘဲ ကျော်သွားရန်
          if (response.requestOptions.extra['is_retry'] == true) {
            return handler.next(response);
          }

          try {
            if (response.data is Map && response.data['error'] != null) {
              final errorData = response.data['error']['data'];
              final errorName = errorData?['name'] ?? "";

              if (errorName == 'odoo.http.SessionExpiredException' || errorName.contains('SessionExpired')) {
                debugPrint('⚠️ Odoo Session Expired! Attempting auto-login refresh...');

                // ၁။ Fresh Client ဖြင့် Login ပြန်ဝင်ခြင်း
                bool isRefreshed = await _refreshSession();

                if (isRefreshed) {
                  debugPrint('🔄 Session refreshed successfully. Building isolated retry client...');

                  final requestOptions = response.requestOptions;

                  // ၂။ ရလာတဲ့ Cookie အသစ်ကို မူရင်း URI အတွက် ဆွဲထုတ်ယူခြင်း
                  final cookies = await cookieJar.loadForRequest(requestOptions.uri);
                  final cookieString = cookies.map((c) => '${c.name}=${c.value}').join('; ');

                  final retryHeaders = Map<String, dynamic>.from(requestOptions.headers);
                  retryHeaders.remove('Cookie');
                  if (cookieString.isNotEmpty) {
                    retryHeaders['Cookie'] = cookieString;
                  }

                  // 🎯 [CRITICAL FIX] Interceptor Queue Deadlock ကင်းဝေးစေရန်
                  // ယာယီ Clean Dio Client အသစ်တစ်ခု ဆောက်၍ ၎င်းဖြင့်သာ Retry ပစ်ပါမည်။
                  final retryDio = Dio();
                  retryDio.options.connectTimeout = const Duration(seconds: 15);
                  retryDio.options.receiveTimeout = const Duration(seconds: 15);

                  debugPrint('🚀 Retrying original request via absolute clean retry client...');

                  // ၃။ ပိတ်ဆို့မှုမရှိသော retryDio ဖြင့် ဒေတာ သွားဆွဲခိုင်းခြင်း
                  final cloneResponse = await retryDio.requestUri(
                    requestOptions.uri,
                    data: requestOptions.data,
                    options: Options(
                      method: requestOptions.method,
                      headers: retryHeaders,
                      contentType: requestOptions.contentType,
                      responseType: requestOptions.responseType,
                    ),
                  );

                  debugPrint('🎉 Retry request completed successfully! Returning data to UI layer.');

                  // ၄။ ရလာတဲ့ response အသစ်ကို မူရင်းပိတ်မိနေတဲ့ နေရာမှာ အစားထိုးဖြေရှင်း (Resolve) ပေးလိုက်ခြင်း
                  return handler.resolve(cloneResponse);
                } else {
                  debugPrint('❌ Auto refresh login failed. Rejecting request.');
                  return handler.reject(
                    DioException(
                      requestOptions: response.requestOptions,
                      response: response,
                      type: DioExceptionType.badResponse,
                      message: "Odoo Session Expired & Auto-Refresh Failed",
                    ),
                  );
                }
              }
            }
            return handler.next(response);
          } catch (e, stackTrace) {
            debugPrint('🚨 Critical Exception caught inside Interceptor onResponse: $e');
            debugPrint('🚨 StackTrace: $stackTrace');

            return handler.reject(
              DioException(
                requestOptions: response.requestOptions,
                response: response,
                type: DioExceptionType.unknown,
                error: e,
                message: "Interceptor Error during session auto-refresh: $e",
              ),
            );
          }
        },
      ),
    );
  }
  // 🔥 [🎯 CRITICAL FIX] Interceptor Loop မပတ်စေရန် Clean Isolated Dio ဖြင့် သီးသန့်မောင်းနှင်သော Auto Login Function
  Future<bool> _refreshSession() async {
    try {
      final username = await _secureStorage.read(key: _keyUsername);
      final password = await _secureStorage.read(key: _keyPassword);
      final database = await _secureStorage.read(key: _keyDatabase);
      final baseUrl = await _secureStorage.read(key: _keyBaseUrl);

      debugPrint('🔍 Attempting auto-refresh with stored credentials: username=$username, database=$database, baseUrl=$baseUrl');
      if (username == null || password == null || database == null || baseUrl == null) {
        debugPrint('❌ Auto refresh aborted: No credentials found in Secure Storage.');
        return false;
      }

      // ကွတ်ကီးအဟောင်းများ အကုန်ရှင်းထုတ်ပစ်ပါ
      await cookieJar.deleteAll();

      // 🎯 [FIX] ပင်မ dio ကြီးကို မသုံးဘဲ Interceptor ကင်းစင်သော ယာယီ Fresh Client အသစ်တစ်ခုကို သုံး၍ သွားခေါ်ပါသည်
      final cleanDio = Dio();
      cleanDio.options.connectTimeout = const Duration(seconds: 10);
      cleanDio.options.receiveTimeout = const Duration(seconds: 10);

      final response = await cleanDio.post(
        '$baseUrl/web/session/authenticate',
        data: {
          'params': {'db': database, 'login': username, 'password': password, 'context': {}},
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        if (response.data['error'] != null) {
          debugPrint('❌ Odoo Re-Auth Logic Error: ${response.data['error']}');
          return false;
        }

        debugPrint('✅ Auto login refresh response successful: ${response.data['result'] != null}');

        // 🎯 [FIX] Clean Dio မှ ရလာသော Set-Cookie Header ဒေတာအသစ်များကို ပင်မ Global CookieJar ထဲသို့ Manual ပြန်ပြောင်းသိမ်းပေးခြင်း
        final rawCookies = response.headers['set-cookie'];
        if (rawCookies != null) {
          final uri = Uri.parse(baseUrl);
          final cookies = rawCookies.map((str) => Cookie.fromSetCookieValue(str)).toList();
          await cookieJar.saveFromResponse(uri, cookies);
          debugPrint('💾 Successfully synchronized new session cookies to global CookieJar.');
        }

        return response.data['result'] != null;
      }

      return false;
    } catch (e) {
      debugPrint('❌ Auto login refresh failed via fresh isolated network client: $e');
      return false;
    }
  }

  Future<RPCAuthResponse> authRPC({required String username, required String password, required String database, required String baseUrl}) async {
    RPCAuthResponse responseModel = RPCAuthResponse('Authentication failed');
    try {
      final response = await dio.post(
        '$baseUrl/web/session/authenticate',
        data: {
          'params': {'db': database, 'login': username, 'password': password, 'context': {}},
        },
      );

      if (response.statusCode == 200) {
        final result = response.data['result'];

        if (result != null) {
          // 🔥 Login ပထမဆုံးအကြိမ် အောင်မြင်မှသာ အချက်အလက်များကို Secure Storage ထဲသို့ Encrypt လုပ်၍ အသေသိမ်းမည်
          await _secureStorage.write(key: _keyUsername, value: username);
          await _secureStorage.write(key: _keyPassword, value: password);
          await _secureStorage.write(key: _keyDatabase, value: database);
          await _secureStorage.write(key: _keyBaseUrl, value: baseUrl);

          final cookies = await cookieJar.loadForRequest(Uri.parse(baseUrl));
          final cookieString = cookies.map((c) => '${c.name}=${c.value}').join('; ');

          String? companyId;
          String? salesTeamGroupId;
          RPCCompany? company;

          if (result['user_companies'] != false) {
            company = RPCCompany.fromJson(result['user_companies']);
            companyId = company.currentCompany.toString();
            salesTeamGroupId = result['x_sales_team_group_id']?.toString();
          } else {
            companyId = result['company_id'].toString();
            salesTeamGroupId = result['x_sales_team_group_id']?.toString();
          }

          final userId = result['uid'];

          responseModel = responseModel.copyWith(
            message: 'Success',
            cookie: cookieString,
            userId: userId,
            companyId: companyId,
            company: company,
            salesTeamGroupId: salesTeamGroupId,
          );
        } else {
          responseModel = responseModel.copyWith(message: 'Authentication failed: result is null');
        }
      } else {
        responseModel = responseModel.copyWith(message: 'Authentication failed: ${response.statusMessage}');
      }
    } on DioException catch (e) {
      responseModel = responseModel.copyWith(message: 'DioException: ${e.message}');
      debugPrint('DioException during authentication: $e');
    } catch (e) {
      responseModel = responseModel.copyWith(message: 'Unexpected error: $e');
      debugPrint('Unexpected error during authentication: $e');
    }

    return responseModel;
  }

  // 🔥 Logout ပြုလုပ်လိုပါက Storage နှင့် Cookie များကို တစ်ခါတည်း ရှင်းလင်းပေးမည့် Helper Function
  Future<void> clearSecureCredentials() async {
    await _secureStorage.deleteAll();
    await cookieJar.deleteAll();
    debugPrint('🧹 Cleared all secure storage credentials and cookie sessions.');
  }

  // --- ကျန်ရှိသော REST API နှင့် RPC Method ကုဒ်များ ပြောင်းလဲမှုမရှိပါ (မူလအတိုင်း ဆက်လက်ရှိနေမည်ဖြစ်သည်) ---

  Future<ClientResponse> changePasswordRPC(String oldValue, String newValue, String baseUrl, String model) async {
    try {
      final response = await dio.post(
        '$baseUrl/web/dataset/call_kw',
        data: {
          "jsonrpc": "2.0",
          "params": {
            "model": model,
            "method": "change_password",
            "args": [oldValue, newValue],
            "kwargs": {},
          },
        },
      );

      if (response.statusCode == 200) {
        final odooRes = OdooErrorResponse.fromJson(response.data);
        if (odooRes.error != null) {
          final errorName = odooRes.error?.data.name;
          final errorCode = odooRes.error?.code;
          final errorMessage = odooRes.error?.message ?? "Unknown Odoo Error";
          if (errorName == 'odoo.exceptions.AccessDenied') {
            return ClientResponse(statusCode: 403, message: "Access Denied. Check permissions or login.", data: null);
          }
          return ClientResponse(statusCode: errorCode ?? 400, message: errorMessage, data: null);
        }
        final data = response.data;
        if (data != null && data['result'] != null) {
          return ClientResponse(statusCode: 200, message: "updated", data: data['result']);
        } else {
          return ClientResponse(statusCode: 500, message: "Unexpected response format", data: null);
        }
      } else {
        return ClientResponse(statusCode: response.statusCode ?? 500, message: response.statusMessage ?? "Failed to update", data: null);
      }
    } on DioException catch (e) {
      return ClientResponse(statusCode: e.response?.statusCode ?? 500, message: e.message ?? "Unknown Dio error", data: null);
    }
  }

  Future<ClientResponse> deactivateRPC(int id, String baseUrl, String model) async {
    try {
      final response = await dio.post(
        '$baseUrl/web/dataset/call_kw',
        data: {
          "jsonrpc": "2.0",
          "params": {
            "model": model,
            "method": "unlink",
            "args": [
              [id],
            ],
            "kwargs": {},
          },
        },
      );

      if (response.statusCode == 200) {
        final odooRes = OdooErrorResponse.fromJson(response.data);
        if (odooRes.error != null) {
          final errorName = odooRes.error?.data.name;
          final errorCode = odooRes.error?.code;
          final errorMessage = odooRes.error?.message ?? "Unknown Odoo Error";
          if (errorName == 'odoo.exceptions.AccessDenied') {
            return ClientResponse(statusCode: 403, message: "Access Denied. Check permissions or login.", data: null);
          }
          return ClientResponse(statusCode: errorCode ?? 400, message: errorMessage, data: null);
        }
        final data = response.data;
        if (data != null && data['result'] != null) {
          return ClientResponse(statusCode: 200, message: "success", data: data['result']);
        } else {
          return ClientResponse(statusCode: 500, message: "Unexpected response format", data: null);
        }
      } else {
        return ClientResponse(statusCode: response.statusCode ?? 500, message: response.statusMessage ?? "Failed", data: null);
      }
    } on DioException catch (e) {
      return ClientResponse(statusCode: e.response?.statusCode ?? 500, message: e.message ?? "Unknown Dio error", data: null);
    }
  }

  Future<ClientListResponse<T>> getAllRPC<T>({
    required String baseUrl,
    required ClientGetRequest request,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    try {
      final response = await dio.post('$baseUrl/web/dataset/call_kw', data: request.toJson());

      if (response.statusCode == 200) {
        final odooRes = OdooErrorResponse.fromJson(response.data);
        if (odooRes.error != null) {
          final errorName = odooRes.error?.data.name;
          final errorCode = odooRes.error?.code;
          final errorMessage = odooRes.error?.message ?? "Unknown Odoo Error";
          if (errorName == 'odoo.exceptions.AccessDenied') {
            return ClientListResponse(statusCode: 403, message: "Access Denied. Check permissions or login.", data: []);
          }
          return ClientListResponse(statusCode: errorCode ?? 400, message: errorMessage, data: []);
        }
        final data = response.data;
        final List<dynamic>? rawList = (data['result'] is List) ? data['result'] : [];
        final List<T> parsed = rawList!.map((e) => fromJson(e as Map<String, dynamic>)).toList();
        return ClientListResponse(statusCode: 200, message: "Success", data: parsed);
      } else {
        return ClientListResponse(statusCode: response.statusCode ?? 500, message: response.statusMessage ?? "Server Error", data: []);
      }
    } on DioException catch (e) {
      debugPrint('Network Error: $e');
      return ClientListResponse(statusCode: 500, message: e.message ?? "Connection Failed", data: []);
    }
  }

  Future<ClientResponse<T>> getRPC<T>({required String baseUrl, required ClientGetRequest request, required T Function(Map<String, dynamic>) fromJson}) async {
    try {
      final response = await dio.post('$baseUrl/web/dataset/call_kw', data: request.toJson());
      if (response.statusCode == 200) {
        final odooRes = OdooErrorResponse.fromJson(response.data);
        if (odooRes.error != null) {
          final errorName = odooRes.error?.data.name;
          final errorCode = odooRes.error?.code;
          final errorMessage = odooRes.error?.message ?? "Unknown Odoo Error";
          if (errorName == 'odoo.exceptions.AccessDenied') {
            return ClientResponse(statusCode: 403, message: "Access Denied. Check permissions or login.", data: null);
          }
          return ClientResponse(statusCode: errorCode ?? 400, message: errorMessage, data: null);
        }
        final T parsed = fromJson(response.data['result'][0] as Map<String, dynamic>);
        return ClientResponse(statusCode: 200, message: "Success", data: parsed);
      } else {
        return ClientResponse(statusCode: response.statusCode ?? 500, message: response.statusMessage ?? "Failed to fetch data", data: null);
      }
    } on DioException catch (e) {
      debugPrint('Error during data fetch: $e');
      return ClientResponse(statusCode: 500, message: e.message ?? "$e", data: null);
    } catch (e) {
      return ClientResponse(statusCode: 500, message: e.toString(), data: null);
    }
  }

  Future<ClientListResponse<T>> getCustomRPC<T>({
    required String baseUrl,
    required Map<String, dynamic> request,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    try {
      final response = await dio.post(baseUrl, data: request);
      if (response.statusCode == 200) {
        final odooRes = OdooErrorResponse.fromJson(response.data);
        if (odooRes.error != null) {
          final errorName = odooRes.error?.data.name;
          final errorCode = odooRes.error?.code;
          final errorMessage = odooRes.error?.message ?? "Unknown Odoo Error";
          if (errorName == 'odoo.exceptions.AccessDenied') {
            return ClientListResponse(statusCode: 403, message: "Access Denied. Check permissions or login.", data: []);
          }
          return ClientListResponse(statusCode: errorCode ?? 400, message: errorMessage, data: []);
        }

        if (response.data['result'] == null) {
          return ClientListResponse(statusCode: 200, message: "Success", data: []);
        }
        final List<dynamic> raw = response.data['result']['response'];
        if (raw.isEmpty) {
          return ClientListResponse(statusCode: 200, message: "Success", data: []);
        }
        final List<T> parsed = raw.map((e) => fromJson(e as Map<String, dynamic>)).toList();
        return ClientListResponse(statusCode: 200, message: "Success", data: parsed);
      } else {
        return ClientListResponse(statusCode: response.statusCode ?? 500, message: response.statusMessage ?? "Failed to fetch data", data: []);
      }
    } on DioException catch (e) {
      debugPrint('Error during data fetch: $e');
      return ClientListResponse(statusCode: 500, message: e.message ?? "$e", data: []);
    } catch (e) {
      return ClientListResponse(statusCode: 500, message: e.toString(), data: []);
    }
  }

  Future<ClientResponse<T>> createRPC<T>(ClientRPCPostRequest request, String baseUrl) async {
    try {
      final response = await dio.post('$baseUrl/web/dataset/call_kw', data: request.toJson());

      if (response.statusCode == 200) {
        final odooRes = OdooErrorResponse.fromJson(response.data);
        if (odooRes.error != null) {
          final errorName = odooRes.error?.data.name;
          final errorCode = odooRes.error?.code;
          final errorMessage = odooRes.error?.data.message ?? "Unknown Odoo Error";
          if (errorName == 'odoo.exceptions.AccessDenied' || errorName == 'odoo.exceptions.AccessError') {
            return ClientResponse(statusCode: 403, message: "Access Denied. Check permissions or ask your admin.", data: null);
          }
          if (errorName == 'odoo.exceptions.ValidationError' && errorMessage.contains("UUID and Salesperson must be unique")) {
            return ClientResponse(statusCode: 409, message: "Already synced (duplicate UUID)", data: null);
          }
          return ClientResponse(statusCode: errorCode ?? 400, message: errorMessage, data: null);
        }
        final data = response.data;
        if (data != null && data['result'] != null) {
          return ClientResponse(statusCode: 200, message: "created", data: data['result']);
        } else {
          return ClientResponse(statusCode: 500, message: "Unexpected response format", data: null);
        }
      } else {
        return ClientResponse(statusCode: 500, message: response.statusMessage ?? "Failed to create", data: null);
      }
    } on DioException catch (e) {
      debugPrint('CreateRPC DIO Message : ${e.response}');
      return ClientResponse(statusCode: 500, message: e.message ?? "Unknown Dio error", data: null);
    }
  }

  Future<ClientListResponse<R>> getAllRest<T extends QueryParamSerializable, R>({
    required String url,
    required String token,
    required bool isList,
    required T queryModel,
    required R Function(Map<String, dynamic>) fromJson,
  }) async {
    try {
      final response = await dio.get(
        url,
        queryParameters: queryModel.toQueryParams(),
        options: token.isEmpty
            ? Options(receiveTimeout: const Duration(seconds: 5))
            : Options(headers: {'Authorization': 'Bearer $token'}, receiveTimeout: const Duration(seconds: 5)),
      );

      if (response.statusCode == 200) {
        final List<dynamic> rawList = isList ? response.data : response.data['data'] ?? [];
        if (rawList.isEmpty) {
          return ClientListResponse<R>(statusCode: 200, message: "Success", data: []);
        }
        final List<R> parsed = rawList.map((e) => fromJson(e as Map<String, dynamic>)).toList();
        return ClientListResponse<R>(statusCode: 200, message: "Success", data: parsed);
      } else {
        return ClientListResponse<R>(statusCode: response.statusCode ?? 500, message: "Failed", data: []);
      }
    } on DioException catch (e) {
      return ClientListResponse<R>(statusCode: e.response?.statusCode ?? 500, message: e.message ?? "Unknown Dio error", data: []);
    }
  }

  Future<ClientResponse<T>> getRest<T>({
    required String baseUrl,
    required String endpoint,
    required String token,
    bool isList = false,
    int? id,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    final options = token.isEmpty
        ? Options(receiveTimeout: const Duration(seconds: 5))
        : Options(headers: {'Authorization': 'Bearer $token'}, receiveTimeout: const Duration(seconds: 5));

    final String path = id == null ? endpoint : '$endpoint/$id';
    final String fullUrl = baseUrl.endsWith('/') ? '$baseUrl$path' : '$baseUrl/$path';

    try {
      final response = await dio.get(fullUrl, options: options);
      final rawData = isList ? response.data : response.data['data'];
      return ClientResponse<T>(statusCode: response.statusCode ?? 200, message: response.statusMessage ?? 'OK', data: fromJson(rawData));
    } on DioException catch (e) {
      return ClientResponse<T>(statusCode: e.response?.statusCode ?? 400, message: 'Server Error: ${e.message}', data: null);
    } catch (e) {
      return ClientResponse<T>(statusCode: 500, message: 'Unexpected Error: $e', data: null);
    }
  }

  Future<ClientResponse> deleteRest(String baseUrl, String param, int id) async {
    try {
      final response = await dio.delete('$baseUrl$param/$id', options: Options(receiveTimeout: const Duration(seconds: 5)));
      return ClientResponse(statusCode: response.statusCode ?? 200, message: response.statusMessage ?? 'Deleted', data: response.data);
    } on DioException catch (dioError) {
      return ClientResponse(statusCode: dioError.response?.statusCode ?? 400, message: 'Server Error: ${dioError.message}', data: dioError.response?.data);
    } catch (e) {
      return ClientResponse(statusCode: 500, message: e.toString(), data: null);
    }
  }

  Future<ClientResponse> updateRest<T>(String baseUrl, String token, String endpoint, int? id, T data) async {
    final options = Options(headers: {'Authorization': 'Bearer $token'}, receiveTimeout: const Duration(seconds: 5));
    try {
      final String path = id == null ? endpoint : '$endpoint/$id';
      final String fullUrl = baseUrl.endsWith('/') ? '$baseUrl$path' : '$baseUrl/$path';
      final response = await dio.put(fullUrl, queryParameters: data is Map<String, dynamic> ? data : null, options: options);
      return ClientResponse(statusCode: response.statusCode ?? 200, message: response.statusMessage ?? 'Updated', data: response.data);
    } on DioException catch (dioError) {
      return ClientResponse(statusCode: dioError.response?.statusCode ?? 400, message: 'Server Error: ${dioError.message}', data: dioError.response?.data);
    } catch (e) {
      return ClientResponse(statusCode: 500, message: e.toString(), data: null);
    }
  }

  Future<ClientResponse> createRest<T>(String baseUrl, String param, String? token, T? data, String type) async {
    final options = token != null
        ? Options(headers: {'Authorization': 'Bearer $token'}, receiveTimeout: const Duration(seconds: 5))
        : Options(receiveTimeout: const Duration(seconds: 5));
    try {
      final response = type == 'form-data'
          ? await dio.post('$baseUrl$param', data: data, options: options)
          : await dio.post('$baseUrl$param', queryParameters: data is Map<String, dynamic> ? data : null, options: options);

      return ClientResponse(statusCode: response.statusCode ?? 200, message: response.statusMessage ?? 'Created', data: response.data);
    } on DioException catch (dioError) {
      return ClientResponse(
        statusCode: dioError.response?.statusCode ?? 400,
        message: dioError.response?.statusMessage ?? 'Request Error',
        data: dioError.response?.data,
      );
    } catch (e) {
      return ClientResponse(statusCode: 500, message: e.toString(), data: null);
    }
  }
}
