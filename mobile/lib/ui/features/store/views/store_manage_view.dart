import 'package:flutter/material.dart';

import '../../../core/photo/editable_photo.dart';
import '../../../core/photo/photo_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_error_banner.dart';
import '../../../core/widgets/app_primary_button.dart';
import '../../auth/views/sign_out.dart';
import '../../owner/view_models/owner_dashboard_view_model.dart';
import '../view_models/store_edit_view_model.dart';
import 'store_form_fields.dart';

/// `Magasin` tab — the open/closed switch and the store's details.
class StoreManageView extends StatefulWidget {
  const StoreManageView({
    required this.viewModel,
    this.dashboardViewModel,
    super.key,
  });

  final StoreEditViewModel viewModel;

  /// Knows how many products can be ordered; used to warn before opening a
  /// store with none. Without it the store simply opens.
  final OwnerDashboardViewModel? dashboardViewModel;

  @override
  State<StoreManageView> createState() => _StoreManageViewState();
}

class _StoreManageViewState extends State<StoreManageView> {
  final _formKey = GlobalKey<FormState>();
  late final StoreFormControllers _controllers = StoreFormControllers(
    store: widget.viewModel.store,
  );

  String? _errorMessage;

  @override
  void dispose() {
    _controllers.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Opening with nothing to order is allowed, after a warning. The count is
  /// refreshed first (the owner may have just changed a product); if it cannot
  /// be established there is no warning: the backend's rules are unchanged.
  Future<bool> _confirmOpenWithoutProducts() async {
    final dashboard = widget.dashboardViewModel;
    if (dashboard == null) {
      return true;
    }
    final known = await dashboard.refresh();
    if (!mounted) {
      return false;
    }
    if (!known || dashboard.hasOrderable) {
      return true;
    }
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ouvrir sans produit disponible ?'),
        content: const Text(
          'Aucun de vos produits n’est disponible à la commande : vos clients '
          'ne pourront pas encore commander. Vous pourrez ajouter ou activer '
          'des produits plus tard.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Ouvrir quand même'),
          ),
        ],
      ),
    );
    return proceed ?? false;
  }

  Future<void> _toggleOpen(bool isOpen) async {
    if (isOpen && !await _confirmOpenWithoutProducts()) {
      return;
    }
    if (!mounted) {
      return;
    }
    final error = await widget.viewModel.setOpen(isOpen: isOpen);
    if (!mounted) {
      return;
    }
    _showMessage(
      error ?? (isOpen ? 'Le magasin est ouvert.' : 'Le magasin est fermé.'),
    );
  }

  Future<void> _save() async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();

    final error = await widget.viewModel.save(
      name: _controllers.name.text.trim(),
      address: _controllers.address.text.trim(),
      description: _controllers.description.text,
      latitude: _controllers.latitudeValue,
      longitude: _controllers.longitudeValue,
    );
    if (!mounted) {
      return;
    }
    if (error != null) {
      setState(() => _errorMessage = error);
      return;
    }
    _showMessage('Modifications enregistrées.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final viewModel = widget.viewModel;
        return Scaffold(
          appBar: AppBar(title: const Text('Magasin')),
          body: SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(AppSpacing.pagePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _OpenSwitchCard(
                    isOpen: viewModel.store.isOpen,
                    isBusy: viewModel.isTogglingOpen,
                    onChanged: _toggleOpen,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  EditablePhoto(
                    shape: PhotoShape.banner,
                    photoUrl: viewModel.store.photo,
                    title: 'Photo du magasin',
                    removeMessage: 'La photo du magasin sera supprimée.',
                    onUpload: viewModel.setPhoto,
                    onRemove: viewModel.removePhoto,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_errorMessage != null) ...[
                          AppErrorBanner(message: _errorMessage!),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                        StoreFormFields(
                          controllers: _controllers,
                          onSubmit: _save,
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        AppPrimaryButton(
                          label: 'Enregistrer',
                          isLoading: viewModel.isSaving,
                          onPressed: _save,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxxl),
                  OutlinedButton(
                    onPressed: () => signOut(context),
                    child: const Text('Se déconnecter'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The manual open/closed switch. Closed means "not accepting orders".
/// State is spelled out in text and icon, never by the switch color alone.
class _OpenSwitchCard extends StatelessWidget {
  const _OpenSwitchCard({
    required this.isOpen,
    required this.isBusy,
    required this.onChanged,
  });

  final bool isOpen;
  final bool isBusy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(
              isOpen ? Icons.storefront_rounded : Icons.lock_clock_rounded,
              color: isOpen ? AppColors.success : AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isOpen ? 'Magasin ouvert' : 'Magasin fermé',
                    style: textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    isOpen ? 'Les clients peuvent passer commande.' : 'Le magasin n’accepte pas de commandes pour le moment.',
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Semantics(
              label: 'Magasin ouvert',
              child: Switch(
                value: isOpen,
                onChanged: isBusy ? null : onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
