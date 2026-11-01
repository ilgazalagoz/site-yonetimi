import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/auth_gate.dart';

// Bu değerler koda yazılmaz, `--dart-define-from-file=env.json` ile verilir.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');

bool get _configured => _supabaseUrl.isNotEmpty && _supabaseKey.isNotEmpty;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_configured) {
    await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseKey);
  }
  runApp(const SiteYonetimiApp());
}

class SiteYonetimiApp extends StatelessWidget {
  const SiteYonetimiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Site Yönetimi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: _configured ? const AuthGate() : const _ConfigErrorPage(),
    );
  }
}

class _ConfigErrorPage extends StatelessWidget {
  const _ConfigErrorPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'env.json bulunamadı veya boş.\n'
            'Çalıştırırken --dart-define-from-file=env.json ekle.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
