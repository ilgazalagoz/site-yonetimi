import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';
import '../home/home_page.dart';
import 'login_page.dart';

/// Oturum açık mı kapalı mı diye bakar, ona göre ekranı seçer.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, _) {
        final session = supabase.auth.currentSession;
        return session == null ? const LoginPage() : const HomePage();
      },
    );
  }
}
