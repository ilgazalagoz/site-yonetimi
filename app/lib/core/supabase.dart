import 'package:supabase_flutter/supabase_flutter.dart';

/// Uygulamanın her yerinden kullanılan Supabase istemcisi.
SupabaseClient get supabase => Supabase.instance.client;

/// Supabase'in İngilizce hata mesajlarını kullanıcıya Türkçe gösterir.
String authErrorMessage(AuthException e) {
  final m = e.message.toLowerCase();
  if (m.contains('invalid login')) return 'E-posta veya şifre hatalı.';
  if (m.contains('not confirmed')) {
    return 'E-posta adresin henüz doğrulanmamış. Gelen kutunu kontrol et.';
  }
  if (m.contains('already registered')) {
    return 'Bu e-posta ile zaten bir hesap var.';
  }
  if (m.contains('password')) return 'Şifre en az 8 karakter olmalı.';
  if (m.contains('rate limit')) {
    return 'Çok fazla deneme yapıldı, biraz bekleyip tekrar dene.';
  }
  return e.message;
}
