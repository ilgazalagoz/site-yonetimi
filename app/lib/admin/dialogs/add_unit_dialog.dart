import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase.dart';

class AddUnitDialog extends StatefulWidget {
  final String siteId;
  final List<Map<String, dynamic>>? blocks;
  final List<Map<String, dynamic>>? unitTypes;
  final String? initialBlockId;
  final Map<String, dynamic>? unit;

  const AddUnitDialog({
    super.key,
    required this.siteId,
    this.blocks,
    this.unitTypes,
    this.initialBlockId,
    this.unit,
  });

  @override
  State<AddUnitDialog> createState() => _AddUnitDialogState();
}

class _AddUnitDialogState extends State<AddUnitDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _unitNoController;

  bool _loadingDependencies = false;
  List<Map<String, dynamic>> _blocks = [];
  List<Map<String, dynamic>> _unitTypes = [];

  String? _selectedBlockId;
  String? _selectedUnitTypeId;
  bool _saving = false;
  String? _error;

  bool get isEditing => widget.unit != null;

  @override
  void initState() {
    super.initState();
    _unitNoController = TextEditingController(text: widget.unit?['unit_no'] ?? '');

    if (widget.blocks != null && widget.unitTypes != null) {
      _blocks = List.from(widget.blocks!);
      _unitTypes = List.from(widget.unitTypes!);
      _initSelections();
    } else {
      _loadDependencies();
    }
  }

  void _initSelections() {
    if (isEditing) {
      _selectedBlockId = widget.unit?['block_id'] as String?;
      _selectedUnitTypeId = widget.unit?['unit_type_id'] as String?;
    } else {
      if (widget.initialBlockId != null &&
          _blocks.any((b) => b['id'] == widget.initialBlockId)) {
        _selectedBlockId = widget.initialBlockId;
      } else if (_blocks.isNotEmpty) {
        _selectedBlockId = _blocks.first['id'] as String;
      }

      if (_unitTypes.isNotEmpty) {
        _selectedUnitTypeId = _unitTypes.first['id'] as String;
      }
    }
  }

  Future<void> _loadDependencies() async {
    setState(() {
      _loadingDependencies = true;
      _error = null;
    });

    try {
      final blocksRes = await supabase
          .from('blocks')
          .select('id, name')
          .eq('site_id', widget.siteId)
          .order('name');

      final unitTypesRes = await supabase
          .from('unit_types')
          .select('id, name, monthly_amount')
          .eq('site_id', widget.siteId)
          .order('name');

      if (mounted) {
        setState(() {
          _blocks = List<Map<String, dynamic>>.from(blocksRes);
          _unitTypes = List<Map<String, dynamic>>.from(unitTypesRes);
          _loadingDependencies = false;
          _initSelections();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingDependencies = false;
          _error = 'Bağlantı hatası: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _unitNoController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedBlockId == null) {
      setState(() => _error = 'Lütfen bir blok seçin.');
      return;
    }
    if (_selectedUnitTypeId == null) {
      setState(() => _error = 'Lütfen bir daire tipi seçin.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final unitNo = _unitNoController.text.trim();

      if (isEditing) {
        await supabase.from('units').update({
          'block_id': _selectedBlockId,
          'unit_type_id': _selectedUnitTypeId,
          'unit_no': unitNo,
        }).eq('id', widget.unit!['id']);
      } else {
        await supabase.from('units').insert({
          'site_id': widget.siteId,
          'block_id': _selectedBlockId,
          'unit_type_id': _selectedUnitTypeId,
          'unit_no': unitNo,
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
            _error = 'Bu blokta bu daire numarası zaten tanımlı.';
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
            isEditing ? Icons.edit : Icons.add_home_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(isEditing ? 'Daireyi Düzenle' : 'Yeni Daire Ekle'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 340, maxWidth: 440),
        child: _loadingDependencies
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_blocks.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.amber),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Daire eklemek için önce en az bir Blok tanımlamalısınız.',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      DropdownButtonFormField<String>(
                        value: _selectedBlockId,
                        decoration: const InputDecoration(
                          labelText: 'Blok *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.domain),
                        ),
                        items: _blocks.map((b) {
                          return DropdownMenuItem<String>(
                            value: b['id'] as String,
                            child: Text(b['name'] as String),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() => _selectedBlockId = val);
                        },
                        validator: (v) => v == null ? 'Blok seçiniz.' : null,
                      ),
                    const SizedBox(height: 16),
                    if (_unitTypes.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.amber),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Daire eklemek için önce en az bir Daire Tipi tanımlamalısınız.',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      DropdownButtonFormField<String>(
                        value: _selectedUnitTypeId,
                        decoration: const InputDecoration(
                          labelText: 'Daire Tipi *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        items: _unitTypes.map((t) {
                          final amount = t['monthly_amount'];
                          return DropdownMenuItem<String>(
                            value: t['id'] as String,
                            child: Text(
                              '${t['name']} (${amount != null ? '$amount ₺' : 'Aidat yok'})',
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() => _selectedUnitTypeId = val);
                        },
                        validator: (v) => v == null ? 'Daire tipi seçiniz.' : null,
                      ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _unitNoController,
                      decoration: const InputDecoration(
                        labelText: 'Daire No *',
                        hintText: 'Örn. 1, 12, 4B',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.pin_outlined),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Daire no zorunludur.';
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
          onPressed: (_saving || _blocks.isEmpty || _unitTypes.isEmpty) ? null : _submit,
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
