import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_yonetimi/main.dart';

void main() {
  testWidgets('Site Yönetimi uygulamasi aciliyor', (WidgetTester tester) async {
    await tester.pumpWidget(const SiteYonetimiApp());

    // Uygulamanın ana widget'ı oluşturulmuş mu?
    expect(find.byType(SiteYonetimiApp), findsOneWidget);

    // MaterialApp ekrana yüklenmiş mi?
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
