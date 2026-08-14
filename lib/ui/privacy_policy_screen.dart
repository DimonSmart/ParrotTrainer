import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(strings.privacyTitle)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(strings.privacyBody, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}
