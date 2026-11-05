import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';

class CreateSitePage extends StatefulWidget {
  const CreateSitePage({super.key});

  @override
  State<CreateSitePage> createState() => _CreateSitePageState();
}

class _CreateSitePageState extends State<CreateSitePage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _district = TextEditingController();
  final _address = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _district.dispose();
    _address.dispose();
    super.dispose();
  }

  String? _required(String? v) {
    if (v == null || v.trim().length < 2) return 'En az 2 karakter girin.';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await supabase.rpc(
        'create_site',
        params: {
          'p_name': _name.text.trim(),
          'p_city': _city.text.trim(),
          'p_district': _district.text.trim(),
          'p_address': _address.text.trim(),
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      // create_site fonksiyonunun raise exception mesajları burada gelir
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Beklenmeyen bir hata oluştu: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Site başvurusu')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Site adı'),
                    validator: _required,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _city,
                    decoration: const InputDecoration(labelText: 'İl'),
                    validator: _required,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _district,
                    decoration: const InputDecoration(labelText: 'İlçe'),
                    validator: _required,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _address,
                    decoration: const InputDecoration(
                      labelText: 'Adres (opsiyonel)',
                    ),
                    maxLines: 2,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Başvuruyu gönder'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
