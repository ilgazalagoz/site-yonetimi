/// Aydınlatma metninin sürümü. Metin değişirse sürümü artır (v2, v3...).
/// Kayıt sırasında hangi sürümün onaylandığı veritabanında saklanır.
const kvkkVersion = 'v1';

/// TASLAK metin. Teslimden önce gözden geçirilmeli.
const kvkkText = '''
Kişisel Verilerin Korunması Aydınlatma Metni (Taslak)

Bu uygulama, bir bitirme projesi kapsamında geliştirilen site yönetim sistemidir. 6698 sayılı Kişisel Verilerin Korunması Kanunu kapsamında verileriniz aşağıdaki şekilde işlenir.

İşlenen veriler: ad soyad, e-posta, telefon (isteğe bağlı), bağlı olduğunuz site ve daire bilgisi, aidat borcu ve ödeme bildirimleri, arıza kayıtları.

İşleme amacı: hesabınızı oluşturmak ve site yönetiminin aidat, duyuru ve arıza süreçlerini yürütmesini sağlamak.

Hukuki sebep: sözleşmenin kurulması ve ifası ile açık rızanız.

Aktarım: Verileriniz yalnızca bağlı olduğunuz sitenin yöneticisi tarafından görülebilir. Sistem altyapısı için kullanılan bulut hizmeti (Supabase) verileri kendi sunucularında barındırır.

Saklama: Hesabınız aktif olduğu sürece saklanır. Hesap silme talebinde kimlik bilgileriniz anonimleştirilir; muhasebe kayıtları anonim olarak korunur.

Haklarınız: KVKK madde 11 uyarınca verilerinize erişme, düzeltilmesini veya silinmesini talep etme hakkına sahipsiniz.
''';
