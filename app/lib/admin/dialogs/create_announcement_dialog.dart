import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase.dart';

class CreateAnnouncementDialog extends StatefulWidget {
  final String siteId;
  final Map<String, dynamic>? announcement;

  const CreateAnnouncementDialog({
    super.key,
    required this.siteId,
    this.announcement,
  });

  @override
  State<CreateAnnouncementDialog> createState() => _CreateAnnouncementDialogState();
}

class _CreateAnnouncementDialogState extends State<CreateAnnouncementDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late bool _isPinned;

  bool _saving = false;
  String? _error;

  bool get isEditing => widget.announcement != null;

  @override
  void initState() {
    super.initState();
    _titleController =
        TextEditingController(text: widget.announcement?['title'] ?? '');
    _bodyController =
        TextEditingController(text: widget.announcement?['body'] ?? '');
    _isPinned = widget.announcement?['pinned'] == true;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => _error = 'Oturum bilgisi bulunamadı. Lütfen tekrar giriş yapın.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final title = _titleController.text.trim();
      final body = _bodyController.text.trim();

      if (isEditing) {
        await supabase.from('announcements').update({
          'title': title,
          'body': body,
          'pinned': _isPinned,
        }).eq('id', widget.announcement!['id']);
      } else {
        await supabase.from('announcements').insert({
          'site_id': widget.siteId,
          'title': title,
          'body': body,
          'pinned': _isPinned,
          'created_by': user.id,
        });
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Duyuru kaydedilemedi: ${e.message}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Beklenmeyen hata: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            isEditing ? Icons.edit_note : Icons.campaign,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(isEditing ? 'Duyuruyu Düzenle' : 'Yeni Duyuru Oluştur'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 380, maxWidth: 520),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _titleController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Duyuru Başlığı *',
                    hintText: 'Örn. Asansör Bakımı Hakkında Bilgilendirme',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.title),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Başlık zorunludur.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _bodyController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Duyuru Metni *',
                    hintText: 'Sakinlerinize iletmek istediğiniz detayları buraya yazın...',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Duyuru metni zorunludur.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Row(
                    children: [
                      Icon(Icons.push_pin, size: 20, color: Colors.amber),
                      SizedBox(width: 8),
                      Text(
                        'Önemli / Sabitlenmiş Duyuru',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ],
                  ),
                  subtitle: const Text(
                    'Sabitlenen duyurular sakin ekranında en üstte ve vurgulanmış olarak listelenir.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  value: _isPinned,
                  onChanged: (val) => setState(() => _isPinned = val),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, size: 18, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('İptal'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(isEditing ? 'Güncelle' : 'Yayınla'),
        ),
      ],
    );
  }
}
