import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Prompts for the PIN that protects the saved SSH key (see
/// credential_crypto.dart / ssh_credentials.dart) - replaces the old
/// OS-biometric gate (LocalAuthService), since the PIN here isn't just a
/// gate, it IS the encryption key material.
///
/// [confirm]: true when setting a NEW PIN (first save, or replacing an
/// existing one) - requires typing it twice so a typo doesn't lock the
/// user out of their own data. false when unlocking an existing save -
/// a single field, wrong entries are caught by decryption failing
/// (AES-GCM auth tag mismatch), not by this dialog.
///
/// Returns the entered PIN, or null if the user cancelled.
Future<String?> promptForPin(
  BuildContext context, {
  required String title,
  required String message,
  bool confirm = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _PinPromptDialog(title: title, message: message, confirm: confirm),
  );
}

class _PinPromptDialog extends StatefulWidget {
  final String title;
  final String message;
  final bool confirm;
  const _PinPromptDialog({required this.title, required this.message, required this.confirm});

  @override
  State<_PinPromptDialog> createState() => _PinPromptDialogState();
}

class _PinPromptDialogState extends State<_PinPromptDialog> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _pinController.text;
    if (pin.length < 4) {
      setState(() => _error = 'PIN must be at least 4 characters.');
      return;
    }
    if (widget.confirm && pin != _confirmController.text) {
      setState(() => _error = "PINs don't match.");
      return;
    }
    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AxColors.s2,
      title: Text(widget.title, style: AxTextStyles.sans.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message, style: AxTextStyles.sans.copyWith(fontSize: 12, color: AxColors.fg2, height: 1.5)),
            const SizedBox(height: 14),
            _field(_pinController, hint: 'PIN', autofocus: true),
            if (widget.confirm) ...[
              const SizedBox(height: 10),
              _field(_confirmController, hint: 'Confirm PIN'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: AxTextStyles.mono.copyWith(fontSize: 11.5, color: AxColors.bad)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Continue')),
      ],
    );
  }

  Widget _field(TextEditingController controller, {required String hint, bool autofocus = false}) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: true,
      onSubmitted: (_) => _submit(),
      style: AxTextStyles.sans.copyWith(fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AxTextStyles.sans.copyWith(fontSize: 12, color: AxColors.fg3),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        filled: true,
        fillColor: AxColors.s1,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AxColors.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AxColors.line)),
      ),
    );
  }
}
