import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase.dart';

class SuperAdminView extends StatefulWidget {
  const SuperAdminView({super.key});

  @override
  State<SuperAdminView> createState() => _SuperAdminViewState();
}

class _SuperAdminViewState extends State<SuperAdminView> {
  bool _loading = true;
  List<Map<String, dynamic>> _pendingSites = [];
  List<Map<String, dynamic>> _allSites = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSites();
  }

  Future<void> _loadSites() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      List<Map<String, dynamic>> sitesList = [];

      try {
        // 1. Foreign key join ile profili birlikte çekmeyi dene
        final res = await supabase
            .from('sites')
            .select('id, name, city, district, address, status, created_at, created_by, profiles!created_by(full_name, phone)')
            .order('created_at', ascending: false);
        sitesList = List<Map<String, dynamic>>.from(res);
      } catch (_) {
        // 2. Eğer join isim çakışması olursa doğrudan siteleri çek
        final res = await supabase
            .from('sites')
            .select('id, name, city, district, address, status, created_at, created_by')
            .order('created_at', ascending: false);
        sitesList = List<Map<String, dynamic>>.from(res);
      }

      if (mounted) {
        setState(() {
          _allSites = sitesList;
          _pendingSites = sitesList.where((s) => s['status'] == 'pending').toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Siteler yüklenirken hata oluştu: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _approveSite(String siteId) async {
    try {
      await supabase.rpc('approve_site', params: {'p_site_id': siteId});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Site başvurusu onaylandı ve yönetici aktif edildi.')),
        );
        _loadSites();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Onaylama hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _rejectSite(String siteId) async {
    final reasonController = TextEditingController();
    final shouldReject = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Başvuruyu Reddet'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            labelText: 'Red Nedeni',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reddet'),
          ),
        ],
      ),
    );

    if (shouldReject == true && mounted) {
      try {
        await supabase.rpc('reject_site', params: {
          'p_site_id': siteId,
          'p_reason': reasonController.text.trim().isEmpty ? 'Uygun görülmedi' : reasonController.text.trim(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Site başvurusu reddedildi.')),
          );
          _loadSites();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _loadSites,
                icon: const Icon(Icons.refresh),
                label: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: Colors.indigo.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.admin_panel_settings, color: Colors.indigo),
                const SizedBox(width: 8),
                Text(
                  'Süper Admin Yönetim Paneli',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.indigo.shade900,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Yenile',
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadSites,
                ),
              ],
            ),
          ),
          TabBar(
            labelColor: Colors.indigo,
            indicatorColor: Colors.indigo,
            tabs: [
              Tab(
                text: 'Onay Bekleyenler (${_pendingSites.length})',
                icon: const Icon(Icons.pending_actions),
              ),
              Tab(
                text: 'Tüm Siteler (${_allSites.length})',
                icon: const Icon(Icons.apartment),
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildPendingList(),
                _buildAllList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingList() {
    if (_pendingSites.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'Şu an onay bekleyen site başvurusu bulunmuyor.\nYeni bir kullanıcı site başvurusu yaptığında burada görünecektir.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingSites.length,
      itemBuilder: (context, index) {
        final site = _pendingSites[index];
        final applicant = site['profiles'] as Map<String, dynamic>?;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      site['name'] ?? '',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Chip(
                      label: Text('Onay Bekliyor', style: TextStyle(color: Colors.orange, fontSize: 12)),
                      backgroundColor: Color(0xFFFFF3E0),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Konum: ${site['city']} / ${site['district']}'),
                if (site['address'] != null && site['address'].toString().isNotEmpty)
                  Text('Adres: ${site['address']}'),
                const SizedBox(height: 8),
                Text('Başvuran: ${applicant?['full_name'] ?? 'Yönetici Adayı'}${applicant?['phone'] != null ? ' (${applicant!['phone']})' : ''}'),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: () => _rejectSite(site['id']),
                      child: const Text('Reddet'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.green),
                      onPressed: () => _approveSite(site['id']),
                      child: const Text('Onayla ve Aç'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAllList() {
    if (_allSites.isEmpty) {
      return const Center(
        child: Text('Kayıtlı site bulunmuyor.', style: TextStyle(color: Colors.black54)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _allSites.length,
      itemBuilder: (context, index) {
        final site = _allSites[index];
        final status = site['status'] ?? 'pending';

        Color statusColor = Colors.grey;
        String statusText = status;
        if (status == 'active') {
          statusColor = Colors.green;
          statusText = 'Aktif';
        } else if (status == 'pending') {
          statusColor = Colors.orange;
          statusText = 'Beklemede';
        } else if (status == 'rejected') {
          statusColor = Colors.red;
          statusText = 'Reddedildi';
        }

        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.location_city)),
          title: Text(site['name'] ?? ''),
          subtitle: Text('${site['city']} / ${site['district']}'),
          trailing: Chip(
            label: Text(statusText, style: TextStyle(color: statusColor, fontSize: 12)),
            backgroundColor: statusColor.withOpacity(0.1),
          ),
        );
      },
    );
  }
}
