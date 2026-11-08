import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase.dart';

class AddBlockDialog extends StatefulWidget {
  final String siteId;
  final Map<String, dynamic>? block;

  const AddBlockDialog({
    super.key,
    required this.siteId,
    this.block,
  });

  @override
  State<AddBlockDialog> createState() => _AddBlockDialogState();
}

class _AddBlockDialogState extends State<AddBlockDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  bool _saving = false;
  String? _error;

  bool get isEditing => widget.block != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.block?['name'] ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final name = _nameController.text.trim();
      if (isEditing) {
        await supabase.from('blocks').update({
          'name': name,
        }).eq('id', widget.block!['id']);
      } else {
        await supabase.from('blocks').insert({
          'site_id': widget.siteId,
          'name': name,
        });
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          if (e.message.contains('unique') || e.code == '23505') {
            _error = 'Bu isimde bir blok zaten mevcut.';
          } else {
            _error = 'İşlem başarısız: ${e.message}';
          }
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
            isEditing ? Icons.edit : Icons.domain_add,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(isEditing ? 'Bloku Düzenle' : 'Yeni Blok Ekle'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 420),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Blok Adı *',
                  hintText: 'Örn. A Blok, B Blok, Doğu Blok',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.domain),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Blok adı zorunludur.';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
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
              : Text(isEditing ? 'Güncelle' : 'Kaydet'),
        ),
      ],
    );
  }
}
