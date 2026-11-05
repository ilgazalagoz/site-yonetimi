import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase.dart';

class AdminDashboard extends StatefulWidget {
  final Map<String, dynamic> site;

  const AdminDashboard({super.key, required this.site});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  bool _loading = true;
  List<Map<String, dynamic>> _blocks = [];
  List<Map<String, dynamic>> _units = [];
  List<Map<String, dynamic>> _members = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final siteId = widget.site['id'];

      final blocksRes = await supabase
          .from('blocks')
          .select('id, name')
          .eq('site_id', siteId)
          .order('name');

      final unitsRes = await supabase
          .from('units')
          .select('id, unit_no, block_id, blocks(name)')
          .eq('site_id', siteId)
          .order('unit_no');

      List<Map<String, dynamic>> membersList = [];
      try {
        final membersRes = await supabase
            .from('memberships')
            .select('id, role, status, profiles(full_name, phone)')
            .eq('site_id', siteId)
            .eq('status', 'active');
        membersList = List<Map<String, dynamic>>.from(membersRes);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _blocks = List<Map<String, dynamic>>.from(blocksRes);
          _units = List<Map<String, dynamic>>.from(unitsRes);
          _members = membersList;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Bilgiler alınamadı: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _showCreateInviteDialog() async {
    final emailController = TextEditingController();
    String? selectedUnitId;
    String selectedRole = 'resident';
    bool creating = false;
    String? dialogError;
    String? generatedCode;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (generatedCode != null) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Davet Kodu Üretildi'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Bu kodu sakininize iletebilirsiniz (Ayrıca e-posta servisine bağlanabilir):'),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.indigo.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          generatedCode!,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                            color: Colors.indigo,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          tooltip: 'Kodu Kopyala',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: generatedCode!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Kod panoya kopyalandı!')),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Sakin sisteme kayıt olduktan sonra "Daire Davet Kodu" alanına bu kodu girerek dairesine erişim sağlayacaktır.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
              actions: [
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _loadData();
                  },
                  child: const Text('Tamam'),
                ),
              ],
            );
          }

          return AlertDialog(
            title: const Text('Yeni Davet Kodu Oluştur'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedRole,
                    decoration: const InputDecoration(labelText: 'Davet Edilecek Rol'),
                    items: const [
                      DropdownMenuItem(value: 'resident', child: Text('Daire Sakini (Resident)')),
                      DropdownMenuItem(value: 'technician', child: Text('Teknik Ekip (Technic)')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          selectedRole = val;
                          if (val == 'technician') selectedUnitId = null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Kullanıcı E-posta Adresi',
                      hintText: 'ornek@email.com',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (selectedRole == 'resident') ...[
                    const SizedBox(height: 12),
                    if (_units.isEmpty)
                      const Text(
                        'Henüz tanımlı daire yok. Önce daire eklemelisiniz.',
                        style: TextStyle(color: Colors.orange, fontSize: 13),
                      )
                    else
                      DropdownButtonFormField<String>(
                        value: selectedUnitId,
                        decoration: const InputDecoration(
                          labelText: 'Bağlanacak Daire',
                          border: OutlineInputBorder(),
                        ),
                        items: _units.map((u) {
                          final block = u['blocks']?['name'] ?? '';
                          final no = u['unit_no'] ?? '';
                          return DropdownMenuItem<String>(
                            value: u['id'] as String,
                            child: Text('$block Blok - No: $no'),
                          );
                        }).toList(),
                        onChanged: (val) => setDialogState(() => selectedUnitId = val),
                      ),
                  ],
                  if (dialogError != null) ...[
                    const SizedBox(height: 12),
                    Text(dialogError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
              FilledButton(
                onPressed: creating
                    ? null
                    : () async {
                        final email = emailController.text.trim();
                        if (email.isEmpty) {
                          setDialogState(() => dialogError = 'E-posta boş olamaz.');
                          return;
                        }
                        if (selectedRole == 'resident' && selectedUnitId == null) {
                          setDialogState(() => dialogError = 'Lütfen bir daire seçin.');
                          return;
                        }

                        setDialogState(() {
                          creating = true;
                          dialogError = null;
                        });

                        try {
                          final code = await supabase.rpc('create_invite', params: {
                            'p_site_id': widget.site['id'],
                            'p_email': email,
                            'p_role': selectedRole,
                            'p_unit_id': selectedUnitId,
                          });

                          setDialogState(() {
                            creating = false;
                            generatedCode = code.toString();
                          });
                        } catch (e) {
                          setDialogState(() {
                            creating = false;
                            dialogError = 'Davet kodu üretilemedi: $e';
                          });
                        }
                      },
                child: creating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Kodu Üret'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _loadData, child: const Text('Yenile')),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.site['name'] ?? 'Site Yönetimi',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${widget.site['city']} / ${widget.site['district']}',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
              FilledButton.icon(
                onPressed: _showCreateInviteDialog,
                icon: const Icon(Icons.person_add),
                label: const Text('Daire / Sakin Davet Et'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildStatCard('Blok Sayısı', _blocks.length.toString(), Icons.domain, Colors.blue),
              const SizedBox(width: 16),
              _buildStatCard('Daire Sayısı', _units.length.toString(), Icons.meeting_room, Colors.purple),
              const SizedBox(width: 16),
              _buildStatCard('Aktif Üyeler', _members.length.toString(), Icons.people, Colors.green),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Kayıtlı Sakinler ve Üyeler',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_members.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Henüz katılmış bir üye bulunmuyor. Yukarıdan davet kodu üreterek sakinlerinizi ekleyebilirsiniz.'),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _members.length,
              itemBuilder: (context, i) {
                final m = _members[i];
                final profile = m['profiles'] as Map<String, dynamic>?;
                final unit = m['units'] as Map<String, dynamic>?;
                final block = unit?['blocks']?['name'];
                final unitNo = unit?['unit_no'];

                String roleText = m['role'] == 'resident'
                    ? 'Sakin'
                    : (m['role'] == 'technician' ? 'Teknisyen' : 'Yönetici');

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.indigo.shade100,
                      child: Icon(
                        m['role'] == 'resident'
                            ? Icons.home
                            : (m['role'] == 'technician' ? Icons.build : Icons.shield),
                        color: Colors.indigo,
                      ),
                    ),
                    title: Text(profile?['full_name'] ?? 'İsimsiz Kullanıcı'),
                    subtitle: Text(
                      m['role'] == 'resident' && unitNo != null
                          ? '$block Blok, No: $unitNo'
                          : roleText,
                    ),
                    trailing: Chip(
                      label: Text(roleText, style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(backgroundColor: color.withOpacity(0.15), child: Icon(icon, color: color)),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
