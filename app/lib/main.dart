import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Bu değerler koda yazılmaz, `--dart-define-from-file=env.json` ile verilir.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');

bool get _configured => _supabaseUrl.isNotEmpty && _supabaseKey.isNotEmpty;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_configured) {
    await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseKey);
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
      home: Scaffold(
        body: Center(
          child: Text(
            _configured
                ? 'Supabase bağlantısı hazır'
                : 'env.json bulunamadı veya boş. Çalıştırırken '
                      '--dart-define-from-file=env.json ekle.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
