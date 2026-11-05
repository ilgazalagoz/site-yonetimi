import 'package:flutter/material.dart';
import '../core/supabase.dart';
import '../sites/create_site_page.dart';
import '../invites/claim_invite_dialog.dart';
import '../super_admin/super_admin_view.dart';
import '../admin/admin_dashboard.dart';
import '../resident/resident_dashboard.dart';
import '../technician/technician_dashboard.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _loading = true;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _memberships = [];
  Map<String, dynamic>? _pendingSite;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _error = 'Oturum bilgisi bulunamadı. Lütfen tekrar giriş yapın.';
        _loading = false;
      });
      return;
    }

    try {
      // 1. Profil bilgisini çek
      final profileRes = await supabase
          .from('profiles')
          .select('full_name, phone, is_super_admin')
          .eq('id', user.id)
          .single();

      // Eğer kullanıcı Süper Admin ise diğer sorgulara gerek kalmadan doğrudan paneli aç
      if (profileRes['is_super_admin'] == true) {
        if (mounted) {
          setState(() {
            _profile = profileRes;
            _loading = false;
          });
        }
        return;
      }

      // 2. Normal kullanıcılar için aktif üyelikleri çek
      final memberRes = await supabase
          .from('memberships')
          .select(
            'id, role, status, site_id, unit_id, sites(id, name, city, district)',
          )
          .eq('user_id', user.id)
          .eq('status', 'active');

      // 3. Kullanıcının bekleyen bir site başvurusu var mı kontrol et
      final pendingSiteRes = await supabase
          .from('sites')
          .select('id, name, status, created_at')
          .eq('created_by', user.id)
          .eq('status', 'pending')
          .maybeSingle();

      if (mounted) {
        setState(() {
          _profile = profileRes;
          _memberships = List<Map<String, dynamic>>.from(memberRes);
          _pendingSite = pendingSiteRes;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Hata detayı: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _openClaimInviteDialog() async {
    final result = await showDialog(
      context: context,
      builder: (context) => const ClaimInviteDialog(),
    );

    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result['site_name']} sitesine başarıyla katıldınız!',
          ),
          backgroundColor: Colors.green,
        ),
      );
      _loadInitialData();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Site Yönetimi'),
          actions: [
            IconButton(
              tooltip: 'Çıkış Yap',
              icon: const Icon(Icons.logout),
              onPressed: () => supabase.auth.signOut(),
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Bilgiler Yüklenemedi',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _loadInitialData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tekrar Dene'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isSuperAdmin = _profile?['is_super_admin'] == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Site Yönetimi'),
        actions: [
          if (isSuperAdmin)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Chip(
                avatar: const Icon(Icons.shield, size: 16, color: Colors.white),
                label: const Text(
                  'Süper Admin',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
                backgroundColor: Colors.indigo.shade800,
              ),
            ),
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh),
            onPressed: _loadInitialData,
          ),
          IconButton(
            tooltip: 'Çıkış yap',
            icon: const Icon(Icons.logout),
            onPressed: () => supabase.auth.signOut(),
          ),
        ],
      ),
      body: _buildBody(isSuperAdmin),
    );
  }

  Widget _buildBody(bool isSuperAdmin) {
    // 1. Süper Admin Paneli
    if (isSuperAdmin) {
      return const SuperAdminView();
    }

    // 2. Aktif Üyelik Paneli
    if (_memberships.isNotEmpty) {
      final activeMembership = _memberships.first;
      final role = activeMembership['role'] as String;

      if (role == 'site_admin') {
        final site = activeMembership['sites'] as Map<String, dynamic>;
        return AdminDashboard(site: site);
      } else if (role == 'technician') {
        return TechnicianDashboard(membership: activeMembership);
      } else {
        return ResidentDashboard(membership: activeMembership);
      }
    }

    // 3. Henüz bir siteye bağlı olmayan kullanıcı (Onboarding)
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Hoş Geldiniz, ${_profile?['full_name'] ?? ''}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                supabase.auth.currentUser?.email ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 24),

              if (_pendingSite != null) ...[
                Card(
                  color: Colors.amber.shade50,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: Colors.amber.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.hourglass_top,
                          color: Colors.orange,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_pendingSite!['name']} Başvurunuz İnceleniyor',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Site başvurunuz Süper Admin onayından sonra aktifleşecektir.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Daire Kodunu Gir
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.vpn_key_outlined, color: Colors.indigo),
                          SizedBox(width: 8),
                          Text(
                            'Daire Davet Kodum Var',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Yöneticiniz tarafından e-posta adresinize gönderilen 6 haneli kodu girerek dairenize bağlanın.',
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _openClaimInviteDialog,
                        icon: const Icon(Icons.mark_email_read),
                        label: const Text('Davet Kodunu Gir'),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Site Başvurusu Yap
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.business_outlined, color: Colors.teal),
                          SizedBox(width: 8),
                          Text(
                            'Site / Apartman Yöneticisiyim',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Kendi sitenizi veya apartmanınızı sisteme eklemek için yönetici başvurusu yapın.',
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final created = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CreateSitePage(),
                            ),
                          );
                          if (created == true) {
                            _loadInitialData();
                          }
                        },
                        icon: const Icon(Icons.add_home_work),
                        label: const Text('Yeni Site Başvurusu Yap'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
