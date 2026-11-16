import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}

void main() {
  setUpAll(() {
    HttpOverrides.global = RealHttpOverrides();
  });

  testWidgets('Test button tap with HTTP inside runAsync', (WidgetTester tester) async {
    String status = 'idle';

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Center(
              child: Column(
                children: [
                  Text(status),
                  ElevatedButton(
                    onPressed: () async {
                      final res = await http.get(Uri.parse('http://127.0.0.1:5262/swagger/v1/swagger.json'));
                      setState(() {
                        status = 'HTTP_${res.statusCode}';
                      });
                    },
                    child: const Text('Fetch'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('idle'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Fetch'));
      await Future.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();

    expect(find.text('HTTP_200'), findsOneWidget);
    print('Button tap made real HTTP call and updated UI to HTTP_200!');
  });
}
