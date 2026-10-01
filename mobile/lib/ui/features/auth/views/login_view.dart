import 'package:flutter/material.dart';

import '../../../authenticated_home.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_error_banner.dart';
import '../../../core/widgets/app_password_field.dart';
import '../../../core/widgets/app_primary_button.dart';
import '../../../core/widgets/brand_mark.dart';
import '../view_models/auth_scope.dart';
import 'account_type_view.dart';

/// `Connexion` — login with phone number + password.
///
/// Branded and vertically centered: the same content block sits in the
/// middle of the screen when there's room, and scrolls up to stay visible
/// once the keyboard opens, on any device size.
class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final auth = AuthScope.of(context);
    final error = await auth.login(
      phoneNumber: _phoneController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) {
      return;
    }

    if (error != null) {
      setState(() => _errorMessage = error);
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthenticatedHome()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pagePadding,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: AppSpacing.md),
                      Center(
                        child: BrandMark(
                          iconSize: 96,
                          spacing: AppSpacing.sm,
                          nameStyle: textTheme.titleLarge?.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      Text('Connexion', style: textTheme.headlineSmall),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Connectez-vous pour continuer.',
                        style: textTheme.bodyLarge?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      if (_errorMessage != null) ...[
                        AppErrorBanner(message: _errorMessage!),
                        const SizedBox(height: AppSpacing.lg),
                      ],
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
                      AppPasswordField(
                        controller: _passwordController,
                        label: 'Mot de passe',
                        validator: (value) => AppValidators.required(
                          value,
                          message: 'Le mot de passe est requis.',
                        ),
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      AppPrimaryButton(
                        label: 'Se connecter',
                        isLoading: auth.isBusy,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AccountTypeView(),
                            ),
                          );
                        },
                        child: const Text('Nouveau ici ? Créer un compte'),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
