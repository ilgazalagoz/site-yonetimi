import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase.dart';

class ResidentDashboard extends StatefulWidget {
  final Map<String, dynamic> membership;

  const ResidentDashboard({super.key, required this.membership});

  @override
  State<ResidentDashboard> createState() => _ResidentDashboardState();
}

class _ResidentDashboardState extends State<ResidentDashboard> {
  bool _loading = true;
  List<Map<String, dynamic>> _announcements = [];
  List<Map<String, dynamic>> _tickets = [];
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
      final siteId = widget.membership['site_id'];

      final annRes = await supabase
          .from('announcements')
          .select('id, title, body, created_at, pinned')
          .eq('site_id', siteId)
          .order('pinned', ascending: false)
          .order('created_at', ascending: false)
          .limit(5);

      final tickRes = await supabase
          .from('tickets')
          .select('id, title, description, status, created_at')
          .eq('site_id', siteId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _announcements = List<Map<String, dynamic>>.from(annRes);
          _tickets = List<Map<String, dynamic>>.from(tickRes);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Bilgiler alınırken hata: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _createTicketDialog() async {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    bool saving = false;
    String? err;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          title: const Text('Yeni Arıza / Talep Bildir'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Konu', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Açıklama', border: OutlineInputBorder()),
              ),
              if (err != null) ...[
                const SizedBox(height: 8),
                Text(err!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (titleController.text.trim().isEmpty || descController.text.trim().isEmpty) {
                        setDState(() => err = 'Tüm alanları doldurunuz.');
                        return;
                      }

                      setDState(() {
                        saving = true;
                        err = null;
                      });

                      try {
                        await supabase.from('tickets').insert({
                          'site_id': widget.membership['site_id'],
                          'unit_id': widget.membership['unit_id'],
                          'created_by': supabase.auth.currentUser!.id,
                          'title': titleController.text.trim(),
                          'description': descController.text.trim(),
                          'status': 'open',
                        });
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          _loadData();
                        }
                      } catch (e) {
                        setDState(() {
                          saving = false;
                          err = 'Kayıt başarısız: $e';
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Gönder'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final site = widget.membership['sites'] as Map<String, dynamic>?;
    final unit = widget.membership['units'] as Map<String, dynamic>?;
    final block = unit?['blocks']?['name'] ?? '';
    final unitNo = unit?['unit_no'] ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: Colors.indigo.shade50,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.indigo,
                    child: const Icon(Icons.home, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          site?['name'] ?? 'Sitem',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.indigo),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Dairem: $block Blok - No: $unitNo',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _createTicketDialog,
                    icon: const Icon(Icons.build),
                    label: const Text('Arıza Bildir'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            Text('Site Duyuruları', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_announcements.isEmpty)
              const Card(
                child: Padding(padding: EdgeInsets.all(16), child: Text('Henüz bir duyuru bulunmuyor.')),
              )
            else
              ..._announcements.map((a) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(a['pinned'] == true ? Icons.push_pin : Icons.campaign, color: Colors.amber.shade800),
                      title: Text(a['title'] ?? ''),
                      subtitle: Text(a['body'] ?? ''),
                    ),
                  )),
            const SizedBox(height: 24),
            Text('Arıza ve Destek Taleplerim', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_tickets.isEmpty)
              const Card(
                child: Padding(padding: EdgeInsets.all(16), child: Text('Henüz açtığınız bir arıza talebi bulunmuyor.')),
              )
            else
              ..._tickets.map((t) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.build_circle_outlined, color: Colors.indigo),
                      title: Text(t['title'] ?? ''),
                      subtitle: Text(t['description'] ?? ''),
                      trailing: Chip(
                        label: Text(t['status'] ?? 'open', style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                  )),
          ],
        ],
      ),
    );
  }
}
