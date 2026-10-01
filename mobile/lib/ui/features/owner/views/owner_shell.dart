import 'package:flutter/material.dart';

import '../../../../data/models/store.dart';
import '../../../core/app_services.dart';
import '../../catalog/views/catalog_view.dart';
import '../../catalog/views/categories_view.dart';
import '../../store/view_models/store_edit_view_model.dart';
import '../../store/views/store_manage_view.dart';
import '../view_models/owner_dashboard_view_model.dart';
import 'owner_home_view.dart';

/// The owner's areas. `orders` is declared so the navigation is designed for
/// it, but it is not in [_availableTabs] until orders are built — the owner
/// never sees a dead tab.
enum OwnerTab { home, orders, catalog, store }

const _availableTabs = [OwnerTab.home, OwnerTab.catalog, OwnerTab.store];

/// The owner's main navigation once they have a store: **Accueil ·
/// Catalogue · Magasin** (Commandes joins when orders exist). Owners only ever
/// see these — there is no customer-side navigation here.
class OwnerShell extends StatefulWidget {
  const OwnerShell({required this.store, super.key});

  final Store store;

  @override
  State<OwnerShell> createState() => _OwnerShellState();
}

class _OwnerShellState extends State<OwnerShell> {
  StoreEditViewModel? _storeViewModel;
  OwnerDashboardViewModel? _dashboardViewModel;
  OwnerTab _tab = OwnerTab.home;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_storeViewModel == null) {
      final services = AppServices.of(context);
      _storeViewModel = StoreEditViewModel(
        storeRepository: services.storeRepository,
        initialStore: widget.store,
      );
      _dashboardViewModel = OwnerDashboardViewModel(
        categoryRepository: services.categoryRepository,
        productRepository: services.productRepository,
      )..refresh();
    }
  }

  @override
  void dispose() {
    _storeViewModel?.dispose();
    _dashboardViewModel?.dispose();
    super.dispose();
  }

  void _select(OwnerTab tab) {
    setState(() => _tab = tab);
    if (tab == OwnerTab.home) {
      // The catalog or store may have changed since the owner last looked.
      _dashboardViewModel!.refresh();
    }
  }

  Future<void> _openCategories() async {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => const CategoriesView()));
    if (mounted) {
      await _dashboardViewModel!.refresh();
    }
  }

  /// Each tab gets its own [ScaffoldMessenger] so its snackbars are shown by
  /// the tab's own Scaffold — which lifts that tab's floating button above
  /// them. With the single app-wide messenger they would be drawn by the
  /// shell's Scaffold and cover the button for a few seconds.
  Widget _page(OwnerTab tab) => ScaffoldMessenger(child: _content(tab));

  Widget _content(OwnerTab tab) => switch (tab) {
    OwnerTab.home => OwnerHomeView(
      storeViewModel: _storeViewModel!,
      dashboardViewModel: _dashboardViewModel!,
      onOpenCategories: _openCategories,
      onOpenCatalog: () => _select(OwnerTab.catalog),
      onOpenStore: () => _select(OwnerTab.store),
    ),
    OwnerTab.catalog => const CatalogView(),
    OwnerTab.store => StoreManageView(viewModel: _storeViewModel!),
    OwnerTab.orders => const SizedBox.shrink(), // not built yet
  };

  static (String, IconData) _destination(OwnerTab tab) => switch (tab) {
    OwnerTab.home => ('Accueil', Icons.home_rounded),
    OwnerTab.orders => ('Commandes', Icons.receipt_long_rounded),
    OwnerTab.catalog => ('Catalogue', Icons.category_rounded),
    OwnerTab.store => ('Magasin', Icons.storefront_rounded),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack keeps each tab's state (loaded lists, unsaved edits)
      // when switching between them.
      body: IndexedStack(
        index: _availableTabs.indexOf(_tab),
        children: [for (final tab in _availableTabs) _page(tab)],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _availableTabs.indexOf(_tab),
        onDestinationSelected: (index) => _select(_availableTabs[index]),
        destinations: [
          for (final tab in _availableTabs)
            NavigationDestination(
              icon: Icon(_destination(tab).$2),
              label: _destination(tab).$1,
            ),
        ],
      ),
    );
  }
}
