import 'package:flutter/material.dart';

import '../../../../data/models/user.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_error_banner.dart';
import '../../../core/widgets/app_password_field.dart';
import '../../../core/widgets/app_primary_button.dart';
import '../view_models/auth_scope.dart';

/// Shared registration fields for both account types (they collect the same
/// `User` fields — only the role and what happens next differ).
class RegisterForm extends StatefulWidget {
  const RegisterForm({
    required this.role,
    required this.submitLabel,
    required this.onSuccess,
    super.key,
  });

  final UserRole role;
  final String submitLabel;
  final void Function(BuildContext context) onSuccess;

  @override
  State<RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<RegisterForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _whatsappController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final auth = AuthScope.of(context);
    final error = await auth.register(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      phoneNumber: _phoneController.text.trim(),
      role: widget.role,
      whatsappNumber: _whatsappController.text.trim(),
    );

    if (!mounted) {
      return;
    }

    if (error != null) {
      setState(() => _errorMessage = error);
      return;
    }

    widget.onSuccess(context);
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.pagePadding),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorMessage != null) ...[
              AppErrorBanner(message: _errorMessage!),
              const SizedBox(height: AppSpacing.lg),
            ],
            TextFormField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              decoration: const InputDecoration(labelText: 'Nom'),
              validator: AppValidators.name,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Adresse e-mail'),
              validator: AppValidators.email,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.telephoneNumber],
              decoration: const InputDecoration(
                labelText: 'Numéro de téléphone',
              ),
              validator: AppValidators.phoneNumber,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _whatsappController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Numéro WhatsApp'),
              validator: AppValidators.optionalPhoneNumber,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppPasswordField(
              controller: _passwordController,
              label: 'Mot de passe',
              validator: AppValidators.password,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.xxl),
            AppPrimaryButton(
              label: widget.submitLabel,
              isLoading: auth.isBusy,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
