import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_error_banner.dart';

/// One dialog for both adding and renaming a category — the only field is
/// the name, so no separate editor screen is needed.
///
/// [onSubmit] performs the save and returns a French error message, or `null`
/// on success. Server errors (e.g. a duplicate name) stay inside the dialog so
/// the owner can correct the name. Resolves to the saved name, or `null` if
/// the dialog was cancelled.
Future<String?> showCategoryNameDialog(
  BuildContext context, {
  required String title,
  required String submitLabel,
  required Future<String?> Function(String name) onSubmit,
  String? initialName,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _CategoryNameDialog(
      title: title,
      submitLabel: submitLabel,
      initialName: initialName,
      onSubmit: onSubmit,
    ),
  );
}

class _CategoryNameDialog extends StatefulWidget {
  const _CategoryNameDialog({
    required this.title,
    required this.submitLabel,
    required this.onSubmit,
    this.initialName,
  });

  final String title;
  final String submitLabel;
  final String? initialName;
  final Future<String?> Function(String name) onSubmit;

  @override
  State<_CategoryNameDialog> createState() => _CategoryNameDialogState();
}

class _CategoryNameDialogState extends State<_CategoryNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.initialName);

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSaving) {
      return;
    }
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final name = _controller.text.trim();

    setState(() => _isSaving = true);
    final error = await widget.onSubmit(name);
    if (!mounted) {
      return;
    }
    if (error == null) {
      Navigator.of(context).pop(name);
      return;
    }
    setState(() {
      _isSaving = false;
      _errorMessage = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorMessage != null) ...[
              AppErrorBanner(message: _errorMessage!),
              const SizedBox(height: AppSpacing.lg),
            ],
            TextFormField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Nom de la catégorie',
              ),
              validator: AppValidators.categoryName,
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: _isSaving ? null : _submit,
          child: Text(widget.submitLabel),
        ),
      ],
    );
  }
}
