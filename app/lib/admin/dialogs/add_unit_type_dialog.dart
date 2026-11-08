import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase.dart';

class AddUnitTypeDialog extends StatefulWidget {
  final String siteId;
  final Map<String, dynamic>? unitType;

  const AddUnitTypeDialog({
    super.key,
    required this.siteId,
    this.unitType,
  });

  @override
  State<AddUnitTypeDialog> createState() => _AddUnitTypeDialogState();
}

class _AddUnitTypeDialogState extends State<AddUnitTypeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  bool _saving = false;
  String? _error;

  bool get isEditing => widget.unitType != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.unitType?['name'] ?? '');
    final initialAmount = widget.unitType?['monthly_amount'];
    _amountController = TextEditingController(
      text: initialAmount != null ? initialAmount.toString() : '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
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
      final amount = double.parse(_amountController.text.replaceAll(',', '.').trim());

      if (isEditing) {
        await supabase.from('unit_types').update({
          'name': name,
          'monthly_amount': amount,
        }).eq('id', widget.unitType!['id']);
      } else {
        await supabase.from('unit_types').insert({
          'site_id': widget.siteId,
          'name': name,
          'monthly_amount': amount,
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
            _error = 'Bu isimde bir daire tipi zaten mevcut.';
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
            isEditing ? Icons.edit : Icons.category,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(isEditing ? 'Daire Tipini Düzenle' : 'Yeni Daire Tipi Tanımla'),
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
                  labelText: 'Daire Tipi Adı *',
                  hintText: 'Örn. 2+1 Standart, 3+1 Dubleks, 1+0 Stüdyo',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.home_work_outlined),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Tip adı zorunludur.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+[\.,]?\d{0,2}')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Aylık Aidat Tutarı (TL) *',
                  hintText: 'Örn. 1250 veya 1500.00',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.payments_outlined),
                  suffixText: '₺',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Aylık aidat tutarı zorunludur.';
                  }
                  final parsed = double.tryParse(val.replaceAll(',', '.').trim());
                  if (parsed == null) {
                    return 'Geçerli bir tutar girin.';
                  }
                  if (parsed < 0) {
                    return 'Tutar negatif olamaz.';
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
