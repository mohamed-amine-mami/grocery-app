import 'package:flutter/material.dart';

import '../../../../data/repositories/store_repository.dart';
import '../../../core/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_error_banner.dart';
import '../../../core/widgets/app_primary_button.dart';
import '../../auth/views/sign_out.dart';
import '../../owner/views/owner_shell.dart';
import '../view_models/store_create_view_model.dart';
import 'store_form_fields.dart';

/// `Création du magasin` — the final step of the owner onboarding flow.
class StoreCreateView extends StatefulWidget {
  const StoreCreateView({super.key});

  @override
  State<StoreCreateView> createState() => _StoreCreateViewState();
}

class _StoreCreateViewState extends State<StoreCreateView> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = StoreFormControllers();

  late final StoreRepository _storeRepository;
  StoreCreateViewModel? _viewModel;
  String? _errorMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _storeRepository = AppServices.of(context).storeRepository;
    _viewModel ??= StoreCreateViewModel(storeRepository: _storeRepository)
      ..addListener(_onViewModelChanged);
  }

  void _onViewModelChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _viewModel?.removeListener(_onViewModelChanged);
    _controllers.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final result = await _viewModel!.createStore(
      name: _controllers.name.text.trim(),
      address: _controllers.address.text.trim(),
      description: _controllers.description.text.trim(),
      photo: _controllers.photo.text.trim(),
      latitude: _controllers.latitudeValue,
      longitude: _controllers.longitudeValue,
    );

    if (!mounted) {
      return;
    }

    final store = result.store;
    if (store == null) {
      setState(() => _errorMessage = result.error);
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => OwnerShell(store: store)),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = _viewModel?.isBusy ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Créer votre magasin'),
        actions: [
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => signOut(context),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Dernière étape : présentez votre magasin.',
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xxl),
                if (_errorMessage != null) ...[
                  AppErrorBanner(message: _errorMessage!),
                  const SizedBox(height: AppSpacing.lg),
                ],
                StoreFormFields(controllers: _controllers, onSubmit: _submit),
                const SizedBox(height: AppSpacing.xxl),
                AppPrimaryButton(
                  label: 'Créer mon magasin',
                  isLoading: isBusy,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
