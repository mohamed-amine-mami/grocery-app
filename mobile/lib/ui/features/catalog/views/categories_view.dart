import 'package:flutter/material.dart';

import '../../../../data/models/store_category.dart';
import '../../../core/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_primary_button.dart';
import '../view_models/category_list_view_model.dart';
import 'category_name_dialog.dart';

/// `Catégories` — the store's categories, opened from the Catalogue screen.
///
/// It owns its [ScaffoldMessenger]: its snackbars are dismissed with the
/// screen instead of reappearing over the Catalogue (and its add button) once
/// the owner goes back.
class CategoriesView extends StatelessWidget {
  const CategoriesView({super.key});

  @override
  Widget build(BuildContext context) =>
      const ScaffoldMessenger(child: _CategoriesScreen());
}

class _CategoriesScreen extends StatefulWidget {
  const _CategoriesScreen();

  @override
  State<_CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<_CategoriesScreen> {
  CategoryListViewModel? _viewModel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewModel ??= CategoryListViewModel(
      categoryRepository: AppServices.of(context).categoryRepository,
    )..load();
  }

  @override
  void dispose() {
    _viewModel?.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _add() async {
    final name = await showCategoryNameDialog(
      context,
      title: 'Nouvelle catégorie',
      submitLabel: 'Ajouter',
      onSubmit: _viewModel!.create,
    );
    if (name != null && mounted) {
      _showMessage('Catégorie « $name » ajoutée.');
    }
  }

  Future<void> _rename(StoreCategory category) async {
    final name = await showCategoryNameDialog(
      context,
      title: 'Renommer la catégorie',
      submitLabel: 'Enregistrer',
      initialName: category.name,
      onSubmit: (name) => _viewModel!.rename(category, name),
    );
    if (name != null && mounted) {
      _showMessage('Catégorie renommée.');
    }
  }

  Future<void> _delete(StoreCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la catégorie ?'),
        content: Text(
          '« ${category.name} » sera supprimée. Cette action est définitive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final error = await _viewModel!.delete(category);
    if (mounted) {
      _showMessage(error ?? 'Catégorie supprimée.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel!,
      builder: (context, _) {
        final viewModel = _viewModel!;
        return Scaffold(
          appBar: AppBar(title: const Text('Catégories')),
          body: SafeArea(
            child: switch (viewModel.status) {
              CategoryListStatus.loading => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              CategoryListStatus.failed => _LoadFailed(onRetry: viewModel.load),
              CategoryListStatus.ready when viewModel.categories.isEmpty =>
                _EmptyState(onAdd: _add),
              CategoryListStatus.ready => _CategoryList(
                categories: viewModel.categories,
                onAdd: _add,
                onRename: _rename,
                onDelete: _delete,
              ),
            },
          ),
        );
      },
    );
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({
    required this.categories,
    required this.onAdd,
    required this.onRename,
    required this.onDelete,
  });

  final List<StoreCategory> categories;
  final VoidCallback onAdd;
  final ValueChanged<StoreCategory> onRename;
  final ValueChanged<StoreCategory> onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.pagePadding),
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (index, category) in categories.indexed) ...[
                if (index > 0) const Divider(height: 1),
                ListTile(
                  title: Text(category.name, style: textTheme.bodyLarge),
                  contentPadding: const EdgeInsets.only(
                    left: AppSpacing.lg,
                    right: AppSpacing.xs,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Renommer « ${category.name} »',
                        icon: const Icon(Icons.edit_rounded),
                        color: AppColors.textSecondary,
                        onPressed: () => onRename(category),
                      ),
                      IconButton(
                        tooltip: 'Supprimer « ${category.name} »',
                        icon: const Icon(Icons.delete_outline_rounded),
                        color: AppColors.textSecondary,
                        onPressed: () => onDelete(category),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Ajouter une catégorie'),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.pagePadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.category_rounded,
            size: 48,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Aucune catégorie',
            style: textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Les catégories organisent vos produits : fruits et légumes, produits laitiers, boissons…',
            style: textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),
          AppPrimaryButton(label: 'Ajouter une catégorie', onPressed: onAdd),
        ],
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.pagePadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Impossible de charger les catégories.',
            style: textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Vérifiez votre connexion, puis réessayez.',
            style: textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),
          AppPrimaryButton(label: 'Réessayer', onPressed: onRetry),
        ],
      ),
    );
  }
}
