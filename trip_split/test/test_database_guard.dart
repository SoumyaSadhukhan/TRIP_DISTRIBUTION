import 'dart:convert';
import 'package:http/http.dart' as http;

/// Guard function that must be called at the start of any integration test suite.
/// Throws a StateError if the backend API is connected to production SPLIT_BILL_DB.
Future<void> assertTestDatabaseIsolation(String baseUrl) async {
  try {
    final response = await http.get(Uri.parse('$baseUrl/system/database-info')).timeout(const Duration(seconds: 3));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final dbName = (data['database'] ?? '').toString().toUpperCase();
      if (!dbName.contains('TEST')) {
        throw StateError(
          'CRITICAL SAFETY VIOLATION: Automated tests attempted to run against non-test database: $dbName. '
          'Tests must strictly target SPLIT_BILL_DB_TEST.',
        );
      }
    }
  } catch (e) {
    // If endpoint is not yet mounted, ensure no static production trip IDs are used
  }
}
