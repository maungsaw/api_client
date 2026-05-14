import 'package:apiclient/src/model.dart'
    show RPCAuthResponse, ClientGetRequest, RPCCompany, ClientListResponse, ClientResponse, ClientRPCPostRequest, QueryParamSerializable, OdooErrorResponse;
import 'package:dio/dio.dart' show Dio, DioException, Options;
import 'package:flutter/rendering.dart' show debugPrint;

/// Service
mixin ApiClientService {
  final dio = Dio();

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
          final cookieString = _extractCookies(response.headers.map['set-cookie']);
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

          // Update using copyWith
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

  Future<ClientResponse> changePasswordRPC(String oldValue, String newValue, String baseUrl, String cookies, String model) async {
    try {
      final response = await dio.post(
        '$baseUrl/web/dataset/call_kw',
        options: Options(headers: {'Cookie': '$cookies'}),
        data: {
          "jsonrpc": "2.0",
          "params": {
            "model": model, // Usually the model for password changes
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
          if (errorName == 'odoo.http.SessionExpiredException') {
            return ClientResponse(statusCode: 401, message: "Session Expired. Please login again.", data: null);
          }
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
        return ClientResponse(statusCode: response.statusCode ?? 500, message: response.statusMessage ?? "Failed to create", data: null);
      }
    } on DioException catch (e) {
      return ClientResponse(statusCode: e.response?.statusCode ?? 500, message: e.message ?? "Unknown Dio error", data: null);
    }
  }

  Future<ClientResponse> deactivateRPC(int id, String baseUrl, String cookies, String model) async {
    try {
      final response = await dio.post(
        '$baseUrl/web/dataset/call_kw',
        options: Options(headers: {'Cookie': '$cookies'}),
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
          if (errorName == 'odoo.http.SessionExpiredException') {
            return ClientResponse(statusCode: 401, message: "Session Expired. Please login again.", data: null);
          }
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
        return ClientResponse(statusCode: response.statusCode ?? 500, message: response.statusMessage ?? "Failed to create", data: null);
      }
    } on DioException catch (e) {
      return ClientResponse(statusCode: e.response?.statusCode ?? 500, message: e.message ?? "Unknown Dio error", data: null);
    }
  }

  Future<ClientListResponse<T>> getAllRPC<T>({
    required String cookies,
    required String baseUrl,
    required ClientGetRequest request,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    try {
      final response = await dio.post(
        '$baseUrl/web/dataset/call_kw',
        options: Options(headers: {'Cookie': cookies}),
        data: request.toJson(),
      );

      if (response.statusCode == 200) {
        final odooRes = OdooErrorResponse.fromJson(response.data);
        if (odooRes.error != null) {
          final errorName = odooRes.error?.data.name;
          final errorCode = odooRes.error?.code;
          final errorMessage = odooRes.error?.message ?? "Unknown Odoo Error";
          if (errorName == 'odoo.http.SessionExpiredException') {
            return ClientListResponse(statusCode: 401, message: "Session Expired. Please login again.", data: []);
          }
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

  Future<ClientResponse<T>> getRPC<T>({
    required String cookies,
    required String baseUrl,
    required ClientGetRequest request,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    try {
      final response = await dio.post(
        '$baseUrl/web/dataset/call_kw',
        options: Options(headers: {'Cookie': cookies}),
        data: request.toJson(),
      );
      if (response.statusCode == 200) {
        final odooRes = OdooErrorResponse.fromJson(response.data);
        if (odooRes.error != null) {
          final errorName = odooRes.error?.data.name;
          final errorCode = odooRes.error?.code;
          final errorMessage = odooRes.error?.message ?? "Unknown Odoo Error";
          if (errorName == 'odoo.http.SessionExpiredException') {
            return ClientResponse(statusCode: 401, message: "Session Expired. Please login again.", data: null);
          }
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
    } on Exception catch (e) {
      return ClientResponse(statusCode: 500, message: e.toString(), data: null);
    }
  }

  Future<ClientListResponse<T>> getCustomRPC<T>({
    required String cookies,
    required String baseUrl,
    required Map<String, dynamic> request,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    try {
      final response = await dio.post(
        baseUrl,
        options: Options(headers: {'Cookie': cookies}),
        data: request,
      );
      if (response.statusCode == 200) {
        final odooRes = OdooErrorResponse.fromJson(response.data);
        if (odooRes.error != null) {
          final errorName = odooRes.error?.data.name;
          final errorCode = odooRes.error?.code;
          final errorMessage = odooRes.error?.message ?? "Unknown Odoo Error";
          if (errorName == 'odoo.http.SessionExpiredException') {
            return ClientListResponse(statusCode: 401, message: "Session Expired. Please login again.", data: []);
          }
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
    } on Exception catch (e) {
      return ClientListResponse(statusCode: 500, message: e.toString(), data: []);
    }
  }

  Future<ClientResponse<T>> createRPC<T>(ClientRPCPostRequest request, String cookie, String baseUrl) async {
    try {
      final response = await dio.post(
        '$baseUrl/web/dataset/call_kw',
        options: Options(headers: {'Cookie': cookie}),
        data: request.toJson(),
      );

      if (response.statusCode == 200) {
        final odooRes = OdooErrorResponse.fromJson(response.data);
        if (odooRes.error != null) {
          final errorName = odooRes.error?.data.name;
          final errorCode = odooRes.error?.code;
          final errorMessage = odooRes.error?.data.message ?? "Unknown Odoo Error";
          if (errorName == 'odoo.http.SessionExpiredException') {
            return ClientResponse(statusCode: 401, message: "Session Expired. Please login again.", data: null);
          }
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
    required R Function(Map<String, dynamic>) fromJson, // R is the model type
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
        debugPrint('status code ${response.data}');
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
      debugPrint('Error fetching from $url: $e');
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

    // Safely join URL parts
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
      if (dioError.response != null) {
        return ClientResponse(statusCode: dioError.response!.statusCode ?? 400, message: 'Server Error: ${dioError.message}', data: dioError.response!.data);
      } else {
        return ClientResponse(statusCode: 400, message: dioError.message ?? 'Dio Error', data: null);
      }
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
      if (dioError.response != null) {
        return ClientResponse(statusCode: dioError.response!.statusCode ?? 400, message: 'Server Error: ${dioError.message}', data: dioError.response!.data);
      } else {
        return ClientResponse(statusCode: 400, message: 'Server Error: ${dioError.message}', data: null);
      }
    } catch (e) {
      return ClientResponse(statusCode: 500, message: e.toString(), data: null);
    }
  }

  Future<ClientResponse?> createRest<T>(String baseUrl, String param, String? token, T? data, String type) async {
    final options = token != null
        ? Options(headers: {'Authorization': 'Bearer $token'}, receiveTimeout: const Duration(seconds: 5))
        : Options(receiveTimeout: const Duration(seconds: 5));
    try {
      final response = type == 'form-data'
          ? await dio.post('$baseUrl$param', data: data, options: options)
          : await dio.post('$baseUrl$param', queryParameters: data is Map<String, dynamic> ? data : null, options: options);

      return ClientResponse(statusCode: response.statusCode ?? 200, message: response.statusMessage ?? 'Created', data: response.data);
    } on DioException catch (dioError) {
      if (dioError.response != null) {
        return ClientResponse(
          statusCode: dioError.response!.statusCode ?? 400,
          message: dioError.response!.statusMessage ?? 'Request Error',
          data: dioError.response!.data,
        );
      } else {
        return ClientResponse(statusCode: 500, message: 'Server Error: ${dioError.message}', data: null);
      }
    } catch (e) {
      return ClientResponse(statusCode: 500, message: e.toString(), data: null);
    }
  }

  String? _extractCookies(List<String>? cookies) {
    if (cookies == null || cookies.isEmpty) return null;

    // Extract only the first occurrence of each cookie key
    final Map<String, String> cookieMap = {};
    for (var cookie in cookies) {
      final keyValue = cookie.split(';').first.split('=');
      if (keyValue.length == 2) {
        cookieMap[keyValue[0].trim()] = keyValue[1].trim();
      }
    }
    return cookieMap.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }
}
