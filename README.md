README.md
Markdown
# API Client (Odoo RPC & Rest API)

A production-ready Flutter/Dart HTTP Client library built on top of `Dio` specifically tailored for Odoo JSON-RPC and standard REST API integrations. It features built-in **Session Persistence** and **Automatic Session Refresh (Anti-Timeout Interceptor)**.

---

## 🚀 Features

* **Odoo JSON-RPC Integration**: Seamless wrappers for `/web/session/authenticate` and `/web/dataset/call_kw` (`search_read`, `create`, `unlink`, etc.).
* **Automatic Session Refresh**: Intercepts `odoo.http.SessionExpiredException` errors behind the scenes, performs an automated re-authentication, and retries the failed request seamlessly without user intervention.
* **Cookie Management**: Powered by `dio_cookie_manager` and `cookie_jar`. No more passing raw cookie strings manually across repositories and layers.
* **REST API Utilities**: Generic helpers for standard GET, POST, PUT, and DELETE HTTP request types with bearer token options.

---

## 📦 Getting Started

### 1. Installation

Add this package to your Flutter project's `pubspec.yaml` via GitHub:

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  apiclient:
    git:
      url: [https://github.com/maungsaw/api_client.git](https://github.com/maungsaw/api_client.git)
      ref: main # or master depending on your branch
Run the pub get command:
Bash
flutter pub get
🏗️ Architectural Technical Guidelines
To maintain clean architecture, avoid calling ApiClientService methods directly inside your UI layers (Widgets). Instead, encapsulate the network logic inside a Repository Layer and manage states using State Management (e.g., BLoC, Provider, Riverpod).
Guideline 1: Exposing Library Models
Ensure your lib/apiclient.dart (root export file) exports both the service and internal models so consumers don't have to target internal src/ directories:
Dart
library apiclient;

export 'src/api_client_service.dart';
export 'src/model.dart';
Guideline 2: Global Service Initialization
Since ApiClientService manages internal memory for session updates and Dio interceptor streams, always instantiate it as a Singleton or inject it via a dependency injection framework like get_it.
📱 Comprehensive Implementation Examples
Step 1: Setup Your App Service Class
Extend the ApiClientService abstract class. Implementing it as a Singleton ensures that the network state, cookies, and underlying Dio interceptor persist globally across your app.
Dart
// data/services/network_service.dart
import 'package:apiclient/apiclient.dart';

class NetworkService extends ApiClientService {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;

  NetworkService._internal() : super();
}
Step 2: Authentication (Odoo RPC)
Call authRPC during app startup or on your login page. The service will securely store the login payloads locally to utilize for background login updates if a 1-hour session timeout occurs.
Dart
final networkService = NetworkService();
const String baseUrl = "[https://erp.example.com](https://erp.example.com)";

final authResponse = await networkService.authRPC(
  username: "developer@example.com",
  password: "securepassword123",
  database: "production_db",
  baseUrl: baseUrl,
);

if (authResponse.message == "Success") {
  print("Logged in successfully! User ID: ${authResponse.userId}");
}
Step 3: Implement the Repository Layer
Once successfully authenticated, do not supply cookie strings manually anymore. The underlying engine handles cookies implicitly. Wrapping the API service inside a data repository cleanly separates network protocols from business workflows.
Dart
// data/repositories/product_repository.dart
import 'package:apiclient/apiclient.dart';
import '../models/product_model.dart';

class ProductRepository {
  final NetworkService _network = NetworkService();
  const String baseUrl = "[https://erp.example.com](https://erp.example.com)";

  Future<List<ProductModel>> getActiveProducts() async {
    final request = ClientGetRequest(
      model: 'product.product',
      method: 'search_read',
      args: [
        [
          ['sale_ok', '=', true],
          ['active', '=', true]
        ]
      ],
      kwargs: {
        'fields': ['id', 'name', 'list_price', 'barcode'],
        'limit': 20
      },
    );

    // Execute call - The core automatically resolves cookies and 1-hour session resets
    final ClientListResponse<ProductModel> response = await _network.getAllRPC<ProductModel>(
      baseUrl: baseUrl,
      request: request,
      fromJson: (json) => ProductModel.fromJson(json),
    );

    if (response.statusCode == 200) {
      return response.data;
    } else {
      throw Exception('Failed to fetch products: ${response.message}');
    }
  }
}
🚨 Developer Rules (Do's and Don'ts)
✅ Do: Always accept results using strong-typed generic bindings (e.g., getAllRPC<YourModel>) to avoid dynamic runtime type issues in the presentation layer.
❌ Don't: Never pass or expect raw String cookies in feature repository parameters. The core interceptor manages session configurations completely.
✅ Do: Utilize standard REST configurations (getAllRest, createRest) when routing HTTP payloads directly outside of the standard Odoo application gateway.
❌ Don't: Avoid bypassing the Repository pattern by making standalone raw calls directly inside state management structures (BLoC events or Provider methods).
⚙️ Under the Hood: Session Expiration Handler
Odoo servers normally expire sessions every hour. This package tackles this with a customized QueuedInterceptorsWrapper:
Every RPC response is carefully examined.
If Odoo rejects the payload via a SessionExpiredException, the interceptor halts the current network queue.
It launches a background login routine utilizing the previously saved credentials.
Upon obtaining a fresh validated token/cookie, it replaces the header configuration, resolves the initial request transparently, and returns it safely to your local application architecture.
👨‍💻 Author
Saw Htun Aung - Technical Consultant Lead / Senior Mobile Developer - @sawhtunaung