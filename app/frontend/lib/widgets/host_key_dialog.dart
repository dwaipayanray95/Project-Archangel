import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Trust-on-first-use host key confirmation dialog, shared between the
/// setup wizard and BackendUpdateDialog - both SSH into a server and
/// need the same "verify this fingerprint" / "server key changed!"
/// prompt (see ssh_transport.dart's HostKeyPrompt/KnownHosts for the
/// TOFU logic this renders for).
Future<bool> showHostKeyConfirmDialog(
  BuildContext context, {
  required String host,
  required String keyType,
  required String fingerprint,
  required bool isMismatch,
}) async {
  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      backgroundColor: AxColors.s2,
      title: Text(
        isMismatch ? 'Server key changed!' : 'Verify server identity',
        style: AxTextStyles.sans.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: isMismatch ? AxColors.bad : null,
        ),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isMismatch)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'This host previously presented a different key. This could mean the '
                  'server was rebuilt - or that something is intercepting this connection. '
                  'Only continue if you\'re certain.',
                  style: AxTextStyles.sans.copyWith(fontSize: 12.5, color: AxColors.bad, height: 1.5),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'First connection to $host - verify this fingerprint matches what your '
                  'cloud provider shows for this server before continuing.',
                  style: AxTextStyles.sans.copyWith(fontSize: 12.5, color: AxColors.fg2, height: 1.5),
                ),
              ),
            Text('$keyType key fingerprint', style: AxTextStyles.sans.copyWith(fontSize: 11, color: AxColors.fg3)),
            const SizedBox(height: 4),
            SelectableText(fingerprint, style: AxTextStyles.mono.copyWith(fontSize: 12.5)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            isMismatch ? 'Trust anyway' : 'Trust this server',
            style: TextStyle(color: isMismatch ? AxColors.bad : null),
          ),
        ),
      ],
    ),
  );
  return accepted ?? false;
}
