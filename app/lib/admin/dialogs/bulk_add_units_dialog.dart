import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase.dart';

class BulkAddUnitsDialog extends StatefulWidget {
  final String siteId;
  final List<Map<String, dynamic>>? blocks;
  final List<Map<String, dynamic>>? unitTypes;
  final String? initialBlockId;

  const BulkAddUnitsDialog({
    super.key,
    required this.siteId,
    this.blocks,
    this.unitTypes,
    this.initialBlockId,
  });

  @override
  State<BulkAddUnitsDialog> createState() => _BulkAddUnitsDialogState();
}

class _BulkAddUnitsDialogState extends State<BulkAddUnitsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _startController = TextEditingController(text: '1');
  final _endController = TextEditingController(text: '10');
  final _prefixController = TextEditingController();

  bool _loadingDependencies = false;
  List<Map<String, dynamic>> _blocks = [];
  List<Map<String, dynamic>> _unitTypes = [];

  String? _selectedBlockId;
  String? _selectedUnitTypeId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.blocks != null && widget.unitTypes != null) {
      _blocks = List.from(widget.blocks!);
      _unitTypes = List.from(widget.unitTypes!);
      _initSelections();
    } else {
      _loadDependencies();
    }
  }

  void _initSelections() {
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
    _startController.dispose();
    _endController.dispose();
    _prefixController.dispose();
    super.dispose();
  }

  int? get _previewCount {
    final start = int.tryParse(_startController.text.trim());
    final end = int.tryParse(_endController.text.trim());
    if (start != null && end != null && end >= start) {
      return (end - start) + 1;
    }
    return null;
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

    final start = int.parse(_startController.text.trim());
    final end = int.parse(_endController.text.trim());
    final prefix = _prefixController.text.trim();

    final total = (end - start) + 1;
    if (total > 150) {
      setState(() => _error = 'Tek seferde en fazla 150 daire ekleyebilirsiniz.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final unitsToInsert = <Map<String, dynamic>>[];
      for (int i = start; i <= end; i++) {
        final unitNo = prefix.isEmpty ? '$i' : '$prefix$i';
        unitsToInsert.add({
          'site_id': widget.siteId,
          'block_id': _selectedBlockId,
          'unit_type_id': _selectedUnitTypeId,
          'unit_no': unitNo,
        });
      }

      await supabase.from('units').insert(unitsToInsert);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          if (e.message.contains('unique') || e.code == '23505') {
            _error =
                'Eklenmek istenen daire numaralarından bazıları bu blokta zaten mevcut.';
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
    final previewCount = _previewCount;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.dynamic_feed, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          const Text('Toplu Daire Ekle'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 360, maxWidth: 460),
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
                    if (_blocks.isEmpty || _unitTypes.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: const Text(
                          'Toplu daire ekleyebilmek için tanımlı en az bir Blok ve Daire Tipi olmalıdır.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    DropdownButtonFormField<String>(
                      value: _selectedBlockId,
                      decoration: const InputDecoration(
                        labelText: 'Hedef Blok *',
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
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: _selectedUnitTypeId,
                      decoration: const InputDecoration(
                        labelText: 'Tüm Daireler İçin Tip *',
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
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _startController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(
                              labelText: 'Başlangıç No *',
                              hintText: '1',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Zorunlu';
                              }
                              final n = int.tryParse(val.trim());
                              if (n == null || n < 1) return '>= 1 olmalı';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _endController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(
                              labelText: 'Bitiş No *',
                              hintText: '20',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Zorunlu';
                              }
                              final end = int.tryParse(val.trim());
                              final start = int.tryParse(_startController.text.trim());
                              if (end == null || end < 1) return '>= 1 olmalı';
                              if (start != null && end < start) {
                                return '>= Başlangıç olmalı';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _prefixController,
                      decoration: const InputDecoration(
                        labelText: 'Opsiyonel Ön Ek (Prefix)',
                        hintText: 'Örn. D- (D-1, D-2...) veya boş bırakın',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.text_fields),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    if (previewCount != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 18, color: Colors.blue.shade800),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Bu işlemle $previewCount adet daire tek seferde oluşturulacak.',
                                style: TextStyle(
                                  color: Colors.blue.shade900,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
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
              : Text('Toplu Ekle (${previewCount ?? 0})'),
        ),
      ],
    );
  }
}
