abstract class QueryParamSerializable {
  Map<String, dynamic> toQueryParams();
}

/// Request model
class ClientGetRequest {
  final String model;
  final String method;
  final List<dynamic> domain;
  final List<String> fields;

  ClientGetRequest({required this.model, required this.method, required this.domain, required this.fields});

  Map<String, dynamic> toJson() {
    return {
      "jsonrpc": "2.0",
      "method": "call",
      "params": {
        'model': model,
        'method': method,
        'args': fields.isEmpty ? domain : [],
        'kwargs': fields.isNotEmpty ? {"domain": domain, "fields": fields} : {},
      },
    };
  }
}

/// Response model
class ClientListResponse<T> {
  final int statusCode;
  final String message;
  final List<T> data;

  ClientListResponse({required this.statusCode, required this.message, required this.data});
}

class ClientResponse<T> {
  final int statusCode;
  final String message;
  final T? data;

  ClientResponse({required this.statusCode, required this.message, this.data});
}

class ClientRPCPostRequest<T> {
  final String model;
  final String method;
  final List<T> args;
  final Map<String, T> kwargs;

  ClientRPCPostRequest({required this.model, required this.method, this.args = const [], this.kwargs = const {}});

  Map<String, dynamic> toJson() {
    return {
      "jsonrpc": "2.0",
      "method": "call",
      "params": {"model": model, "method": method, "args": args, "kwargs": kwargs},
    };
  }
}

class RPCAuthResponse {
  final String? cookie;
  final int? userId;
  final RPCCompany? company;
  final String? companyId;
  final String? salesTeamGroupId;
  final String? message;

  RPCAuthResponse(this.message, {this.cookie, this.userId, this.companyId, this.company, this.salesTeamGroupId});

  RPCAuthResponse copyWith({String? cookie, int? userId, RPCCompany? company, String? companyId, String? salesTeamGroupId, String? message}) {
    return RPCAuthResponse(
      message ?? this.message,
      cookie: cookie ?? this.cookie,
      userId: userId ?? this.userId,
      companyId: companyId ?? this.companyId,
      company: company ?? this.company,
      salesTeamGroupId: salesTeamGroupId ?? this.salesTeamGroupId,
    );
  }
}

class RPCCompany {
  final int currentCompany;
  final Map<String, RPCSubCompany> allowedCompanies;

  RPCCompany({required this.currentCompany, required this.allowedCompanies});

  factory RPCCompany.fromJson(Map<String, dynamic> json) {
    final allowedMap = Map<String, dynamic>.from(json['allowed_companies']);
    return RPCCompany(
      currentCompany: json['current_company'],
      allowedCompanies: allowedMap.map((key, value) {
        return MapEntry(key, RPCSubCompany.fromJson(value));
      }),
    );
  }
}

class RPCSubCompany {
  final int id;
  final String name;

  RPCSubCompany({required this.id, required this.name});

  factory RPCSubCompany.fromJson(Map<String, dynamic> json) {
    return RPCSubCompany(id: json['id'], name: json['name']);
  }
}

class OdooErrorResponse {
  final OdooError? error;

  OdooErrorResponse({this.error});

  factory OdooErrorResponse.fromJson(Map<String, dynamic> json) {
    return OdooErrorResponse(error: json['error'] != null ? OdooError.fromJson(json['error']) : null);
  }
}

class OdooError {
  final int code;
  final String message;
  final ErrorData data;

  OdooError({required this.code, required this.message, required this.data});

  factory OdooError.fromJson(Map<String, dynamic> json) {
    return OdooError(code: json['code'], message: json['message'], data: ErrorData.fromJson(json['data']));
  }
}

class ErrorData {
  final String name;
  final String? message;

  ErrorData({required this.name, this.message});

  factory ErrorData.fromJson(Map<String, dynamic> json) {
    return ErrorData(name: json['name'], message: json['message']);
  }
}
