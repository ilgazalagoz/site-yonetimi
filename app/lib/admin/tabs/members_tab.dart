import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase.dart';

class MembersTab extends StatefulWidget {
  final Map<String, dynamic> site;
  final VoidCallback? onDataChanged;

  const MembersTab({
    super.key,
    required this.site,
    this.onDataChanged,
  });

  @override
  State<MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<MembersTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _units = [];
  String _selectedRoleFilter = 'all'; // all, resident, technician, site_admin
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  String get _siteId => widget.site['id'] as String;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final membersRes = await supabase
          .from('memberships')
          .select('id, role, status, created_at, profiles(full_name, phone), units(id, unit_no, blocks(name))')
          .eq('site_id', _siteId)
          .eq('status', 'active');

      final unitsRes = await supabase
          .from('units')
          .select('id, unit_no, block_id, blocks(name)')
          .eq('site_id', _siteId)
          .order('unit_no');

      if (mounted) {
        setState(() {
          _members = List<Map<String, dynamic>>.from(membersRes);
          _units = List<Map<String, dynamic>>.from(unitsRes);
          _loading = false;
        });
        widget.onDataChanged?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Üyeler yüklenirken hata: $e';
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
                  const Text('Bu kodu sakininize iletebilirsiniz:'),
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
                    decoration: const InputDecoration(
                      labelText: 'Davet Edilecek Rol',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'resident', child: Text('Daire Sakini (Resident)')),
                      DropdownMenuItem(value: 'technician', child: Text('Teknik Ekip (Technician)')),
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
                  const SizedBox(height: 14),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Kullanıcı E-posta Adresi',
                      hintText: 'ornek@email.com',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  if (selectedRole == 'resident') ...[
                    const SizedBox(height: 14),
                    if (_units.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Henüz tanımlı daire yok. Önce "Blok & Daire Yönetimi" sekmesinden daire eklemelisiniz.',
                          style: TextStyle(color: Colors.orange, fontSize: 13),
                        ),
                      )
                    else
                      DropdownButtonFormField<String>(
                        value: selectedUnitId,
                        decoration: const InputDecoration(
                          labelText: 'Bağlanacak Daire *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.meeting_room_outlined),
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
                            'p_site_id': _siteId,
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

  List<Map<String, dynamic>> get _filteredMembers {
    return _members.where((m) {
      if (_selectedRoleFilter != 'all' && m['role'] != _selectedRoleFilter) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final profile = m['profiles'] as Map<String, dynamic>?;
        final name = (profile?['full_name'] ?? '').toString().toLowerCase();
        final phone = (profile?['phone'] ?? '').toString().toLowerCase();
        final unit = m['units'] as Map<String, dynamic>?;
        final unitNo = (unit?['unit_no'] ?? '').toString().toLowerCase();
        final block = (unit?['blocks']?['name'] ?? '').toString().toLowerCase();
        return name.contains(q) || phone.contains(q) || unitNo.contains(q) || block.contains(q);
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Yeniden Dene'),
            ),
          ],
        ),
      );
    }

    final filtered = _filteredMembers;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Üst Başlık & Davet Et Butonu
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Sakinler ve Ekip',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_members.length}',
                            style: TextStyle(
                              color: Colors.indigo.shade800,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Siteye bağlı sakinleri, yöneticileri ve teknik personeli yönetin.',
                      style: TextStyle(color: Colors.black54, fontSize: 13),
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
            const SizedBox(height: 16),

            // Filtre ve Arama Barı
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          selected: _selectedRoleFilter == 'all',
                          label: const Text('Tüm Üyeler'),
                          onSelected: (_) => setState(() => _selectedRoleFilter = 'all'),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          selected: _selectedRoleFilter == 'resident',
                          label: const Text('Sakinler'),
                          onSelected: (_) => setState(() => _selectedRoleFilter = 'resident'),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          selected: _selectedRoleFilter == 'technician',
                          label: const Text('Teknik Ekip'),
                          onSelected: (_) => setState(() => _selectedRoleFilter = 'technician'),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          selected: _selectedRoleFilter == 'site_admin',
                          label: const Text('Yöneticiler'),
                          onSelected: (_) => setState(() => _selectedRoleFilter = 'site_admin'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'İsim, telefon, daire ara...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Üye Listesi
            if (_members.isEmpty)
              Card(
                elevation: 0,
                color: Colors.grey.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        const Text(
                          'Henüz katılmış bir üye bulunmuyor.',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Yukarıdan "Daire / Sakin Davet Et" butonuna tıklayarak oluşturacağınız davet kodunu sakinlerinize iletebilirsiniz.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54, fontSize: 13),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _showCreateInviteDialog,
                          icon: const Icon(Icons.person_add),
                          label: const Text('İlk Daveti Oluştur'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (filtered.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        const Text(
                          'Filtre kriterlerinize uyan üye bulunamadı.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final m = filtered[i];
                  final profile = m['profiles'] as Map<String, dynamic>?;
                  final unit = m['units'] as Map<String, dynamic>?;
                  final block = unit?['blocks']?['name'];
                  final unitNo = unit?['unit_no'];
                  final phone = profile?['phone'];

                  String roleText;
                  Color roleColor;
                  IconData roleIcon;

                  switch (m['role']) {
                    case 'resident':
                      roleText = 'Sakin';
                      roleColor = Colors.teal;
                      roleIcon = Icons.home;
                      break;
                    case 'technician':
                      roleText = 'Teknik Personel';
                      roleColor = Colors.orange;
                      roleIcon = Icons.build;
                      break;
                    case 'site_admin':
                    default:
                      roleText = 'Site Yöneticisi';
                      roleColor = Colors.indigo;
                      roleIcon = Icons.shield;
                      break;
                  }

                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: CircleAvatar(
                        backgroundColor: roleColor.withOpacity(0.12),
                        child: Icon(roleIcon, color: roleColor),
                      ),
                      title: Text(
                        profile?['full_name'] ?? 'İsimsiz Kullanıcı',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Row(
                        children: [
                          if (m['role'] == 'resident' && unitNo != null) ...[
                            Icon(Icons.apartment, size: 14, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text('$block Blok, No: $unitNo'),
                            const SizedBox(width: 12),
                          ],
                          if (phone != null && phone.toString().isNotEmpty) ...[
                            Icon(Icons.phone, size: 14, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text(phone.toString()),
                          ],
                        ],
                      ),
                      trailing: Chip(
                        label: Text(
                          roleText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: roleColor,
                          ),
                        ),
                        backgroundColor: roleColor.withOpacity(0.08),
                        side: BorderSide(color: roleColor.withOpacity(0.2)),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
