import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase.dart';

class TechnicianDashboard extends StatefulWidget {
  final Map<String, dynamic> membership;

  const TechnicianDashboard({super.key, required this.membership});

  @override
  State<TechnicianDashboard> createState() => _TechnicianDashboardState();
}

class _TechnicianDashboardState extends State<TechnicianDashboard> {
  bool _loading = true;
  List<Map<String, dynamic>> _tickets = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTickets();
  }

  Future<void> _loadTickets() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final siteId = widget.membership['site_id'];

      List<Map<String, dynamic>> ticketsList = [];
      try {
        final res = await supabase
            .from('tickets')
            .select('id, title, description, status, created_at, profiles!created_by(full_name, phone)')
            .eq('site_id', siteId)
            .order('created_at', ascending: false);
        ticketsList = List<Map<String, dynamic>>.from(res);
      } catch (_) {
        final res = await supabase
            .from('tickets')
            .select('id, title, description, status, created_at')
            .eq('site_id', siteId)
            .order('created_at', ascending: false);
        ticketsList = List<Map<String, dynamic>>.from(res);
      }

      if (mounted) {
        setState(() {
          _tickets = ticketsList;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Arızalar yüklenirken hata: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _updateTicketStatus(String ticketId, String newStatus) async {
    try {
      await supabase.from('tickets').update({
        'status': newStatus,
        'assigned_to': supabase.auth.currentUser!.id,
        'updated_at': DateTime.now().toIso8601String(),
        if (newStatus == 'resolved' || newStatus == 'closed') 'closed_at': DateTime.now().toIso8601String(),
      }).eq('id', ticketId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Talep durumu güncellendi: $newStatus')),
        );
        _loadTickets();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Güncelleme hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final site = widget.membership['sites'] as Map<String, dynamic>?;

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
                    'Teknik Ekip / Arıza Yönetimi',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text('Site: ${site?['name'] ?? ''}', style: const TextStyle(color: Colors.black54)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Yenile',
                onPressed: _loadTickets,
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
          else if (_tickets.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Şu an incelenecek veya açık bir arıza kaydı bulunmuyor.'),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _tickets.length,
              itemBuilder: (context, i) {
                final t = _tickets[i];
                final unit = t['units'] as Map<String, dynamic>?;
                final block = unit?['blocks']?['name'] ?? '';
                final unitNo = unit?['unit_no'] ?? '';
                final creator = t['profiles'] as Map<String, dynamic>?;

                final status = t['status'] as String? ?? 'open';

                Color statusColor = Colors.orange;
                String statusLabel = 'Açık';
                if (status == 'in_progress') {
                  statusColor = Colors.blue;
                  statusLabel = 'İşlemde';
                } else if (status == 'resolved' || status == 'closed') {
                  statusColor = Colors.green;
                  statusLabel = 'Çözüldü';
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              t['title'] ?? '',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Chip(
                              label: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 12)),
                              backgroundColor: statusColor.withOpacity(0.1),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(t['description'] ?? ''),
                        const SizedBox(height: 8),
                        Text(
                          'Konum: $block Blok, No: $unitNo | Bildiren: ${creator?['full_name'] ?? 'Sakin'} (${creator?['phone'] ?? '-'})',
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (status != 'in_progress' && status != 'resolved' && status != 'closed')
                              TextButton(
                                onPressed: () => _updateTicketStatus(t['id'], 'in_progress'),
                                child: const Text('İşleme Al'),
                              ),
                            if (status != 'resolved' && status != 'closed')
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: Colors.green),
                                onPressed: () => _updateTicketStatus(t['id'], 'resolved'),
                                child: const Text('Çözüldü Olarak İşaretle'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
