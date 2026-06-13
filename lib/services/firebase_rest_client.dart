import 'dart:convert';
import 'package:http/http.dart' as http;
import '../firebase_options.dart';

class FirebaseRestClient {
  static final String _baseUrl =
      DefaultFirebaseOptions.android.databaseURL ?? '';
  static final String _apiKey =
      DefaultFirebaseOptions.android.apiKey ?? '';

  static Future<Map<String, dynamic>?> get(String path) async {
    final uri = Uri.parse('$_baseUrl/$path.json');
    final res = await http.get(uri);
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(res.body);
    if (decoded is! Map) return null;
    return decoded.cast<String, dynamic>();
  }

  static Future<bool> push(String path, Map<String, dynamic> data) async {
    final uri = Uri.parse('$_baseUrl/$path.json');
    final res = await http.post(uri, body: jsonEncode(data));
    return res.statusCode == 200;
  }

  static Future<bool> put(String path, Map<String, dynamic> data) async {
    final uri = Uri.parse('$_baseUrl/$path.json');
    final res = await http.put(uri, body: jsonEncode(data));
    return res.statusCode == 200;
  }

  static Future<bool> patch(String path, Map<String, dynamic> data) async {
    final uri = Uri.parse('$_baseUrl/$path.json');
    final res = await http.patch(uri, body: jsonEncode(data));
    return res.statusCode == 200;
  }

  static Future<bool> set(String path, dynamic value) async {
    final uri = Uri.parse('$_baseUrl/$path.json');
    final res = await http.put(uri, body: jsonEncode(value));
    return res.statusCode == 200;
  }

  static Future<dynamic> getRaw(String path) async {
    final uri = Uri.parse('$_baseUrl/$path.json');
    final res = await http.get(uri);
    if (res.statusCode != 200) return null;
    return jsonDecode(res.body);
  }

  static int serverTimestamp() {
    return DateTime.now().millisecondsSinceEpoch;
  }
}
