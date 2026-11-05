import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase.dart';

class ClaimInviteDialog extends StatefulWidget {
  const ClaimInviteDialog({super.key});

  @override
  State<ClaimInviteDialog> createState() => _ClaimInviteDialogState();
}

class _ClaimInviteDialogState extends State<ClaimInviteDialog> {
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Lütfen e-postanıza gelen davet kodunu girin.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await supabase.rpc(
        'claim_invite',
        params: {'p_code': code.toUpperCase()},
      );

      if (mounted) {
        Navigator.of(context).pop(res);
      }
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Beklenmeyen bir hata oluştu: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.mark_email_read_outlined, color: Colors.indigo),
          SizedBox(width: 8),
          Text('Daire Davet Kodunu Gir'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Site yöneticiniz tarafından e-postanıza gönderilen 6 haneli aktivasyon kodunu buraya giriniz.',
            style: TextStyle(fontSize: 13, color: Colors.black87),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            textCapitalization: TextCapitalization.characters,
            maxLength: 8,
            decoration: InputDecoration(
              labelText: 'Davet Kodu',
              hintText: 'Örn: A8B2C4',
              border: const OutlineInputBorder(),
              errorText: _error,
              counterText: '',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Katıl'),
        ),
      ],
    );
  }
}
