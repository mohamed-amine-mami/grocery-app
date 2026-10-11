import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/auth_response.dart';
import 'package:grocery_mobile/data/models/brand.dart';
import 'package:grocery_mobile/data/models/catalog_category.dart';
import 'package:grocery_mobile/ui/core/utils/search_text.dart';
import 'package:grocery_mobile/data/models/catalog_product.dart';
import 'package:grocery_mobile/data/models/customer_order.dart';
import 'package:grocery_mobile/data/models/customer_product.dart';
import 'package:grocery_mobile/data/models/customer_store.dart';
import 'package:grocery_mobile/data/models/order.dart';
import 'package:grocery_mobile/data/models/sale_unit.dart';
import 'package:grocery_mobile/data/models/store.dart';
import 'package:grocery_mobile/data/models/store_product.dart';
import 'package:grocery_mobile/data/models/user.dart';
import 'package:grocery_mobile/data/repositories/auth_repository.dart';
import 'package:grocery_mobile/data/repositories/catalog_repository.dart';
import 'package:grocery_mobile/data/repositories/customer_orders_repository.dart';
import 'package:grocery_mobile/data/repositories/customer_stores_repository.dart';
import 'package:grocery_mobile/data/repositories/orders_repository.dart';
import 'package:grocery_mobile/data/repositories/store_products_repository.dart';
import 'package:grocery_mobile/data/repositories/store_repository.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/data/services/image_picker_service.dart';
import 'package:grocery_mobile/data/services/token_storage.dart';
import 'package:grocery_mobile/ui/app.dart';
import 'package:grocery_mobile/ui/features/auth/view_models/auth_view_model.dart';

/// In-memory stand-ins for the repositories, so widget tests never touch the
/// network. They subclass the real ones and override only what the tests use.

/// A token store that remembers what happened to it. `token: null` means
/// there is no stored session.
class StoredToken extends TokenStorage {
  StoredToken({this.token = 'stored-token'});

  String? token;
  int clearCalls = 0;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> clearToken() async {
    clearCalls++;
    token = null;
  }
}

class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository(super.apiClient, this._user, {this.meError});

  User _user;

  // ── photo ──
  /// What `setPhoto` / `removePhoto` throw while non-null.
  Object? photoError;

  /// While set, photo requests wait for it — so a test can look at the
  /// loading state — before answering.
  Completer<void>? photoGate;

  /// With [photoError], the photo is nevertheless cleared on the "server"
  /// (the 503-on-delete case: only deleting the stored file failed).
  bool removeClearsDespiteError = false;

  int setPhotoCalls = 0;
  int removePhotoCalls = 0;
  PickedImage? lastUploaded;

  User _withPhoto(String? photo) => _user = User(
    id: _user.id,
    name: _user.name,
    email: _user.email,
    phoneNumber: _user.phoneNumber,
    whatsappNumber: _user.whatsappNumber,
    photo: photo,
    role: _user.role,
  );

  @override
  Future<User> setPhoto(PickedImage image) async {
    setPhotoCalls++;
    lastUploaded = image;
    await photoGate?.future;
    if (photoError != null) {
      throw photoError!;
    }
    return _withPhoto(
      'https://res.example/users/${_user.id}/profile-$setPhotoCalls.jpg',
    );
  }

  @override
  Future<User> removePhoto() async {
    removePhotoCalls++;
    await photoGate?.future;
    if (photoError != null) {
      if (removeClearsDespiteError) {
        _withPhoto(null);
      }
      throw photoError!;
    }
    return _withPhoto(null);
  }

  /// While non-null, `me()` throws it (e.g. a [NetworkException] or a 401).
  Object? meError;

  @override
  Future<User> me() async {
    final error = meError;
    if (error != null) {
      throw error;
    }
    return _user;
  }

  @override
  Future<AuthResponse> register({
    required String name,
    required String email,
    required String password,
    required String phoneNumber,
    required UserRole role,
    String? whatsappNumber,
  }) async => AuthResponse(
    accessToken: 'new-token',
    user: User(
      id: 99,
      name: name,
      email: email,
      phoneNumber: phoneNumber,
      role: role,
    ),
  );
}

class FakeStoreRepository extends StoreRepository {
  FakeStoreRepository(super.apiClient, {this.store, this.fails = false});

  Store? store;
  final bool fails;

  /// What the last `update` call sent, for assertions.
  Map<String, Object?>? lastUpdate;

  // ── photo (see FakeAuthRepository) ──
  Object? photoError;
  Completer<void>? photoGate;
  bool removeClearsDespiteError = false;
  int setPhotoCalls = 0;
  int removePhotoCalls = 0;
  PickedImage? lastUploaded;

  Store _withPhoto(String? photo) {
    final current = store!;
    return store = Store(
      id: current.id,
      name: current.name,
      address: current.address,
      description: current.description,
      photo: photo,
      latitude: current.latitude,
      longitude: current.longitude,
      isOpen: current.isOpen,
      ownerId: current.ownerId,
    );
  }

  @override
  Future<Store> setPhoto(PickedImage image) async {
    setPhotoCalls++;
    lastUploaded = image;
    await photoGate?.future;
    if (photoError != null) {
      throw photoError!;
    }
    return _withPhoto(
      'https://res.example/stores/${store!.id}/photo-$setPhotoCalls.jpg',
    );
  }

  @override
  Future<Store> removePhoto() async {
    removePhotoCalls++;
    await photoGate?.future;
    if (photoError != null) {
      if (removeClearsDespiteError) {
        _withPhoto(null);
      }
      throw photoError!;
    }
    return _withPhoto(null);
  }

  @override
  Future<Store?> getMine() async {
    if (fails) {
      throw const NetworkException('offline');
    }
    return store;
  }

  @override
  Future<Store> update({
    required String name,
    required String address,
    String? description,
    double? latitude,
    double? longitude,
  }) async {
    lastUpdate = {
      'name': name,
      'address': address,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
    };
    return store = Store(
      id: store!.id,
      name: name,
      address: address,
      description: description,
      latitude: latitude,
      longitude: longitude,
      isOpen: store!.isOpen,
      ownerId: store!.ownerId,
    );
  }

  @override
  Future<Store> setOpen({required bool isOpen}) async {
    final current = store!;
    return store = Store(
      id: current.id,
      name: current.name,
      address: current.address,
      isOpen: isOpen,
      ownerId: current.ownerId,
    );
  }
}

/// The global catalog, in memory. Read-only, like the real thing.
class FakeCatalogRepository extends CatalogRepository {
  FakeCatalogRepository(
    super.apiClient, {
    this.categoryList = const [],
    this.items = const [],
    this.fails = false,
    this.gate,
  });

  final List<CatalogCategory> categoryList;
  List<CatalogItem> items;

  /// When true, every call fails like an unreachable backend. Flip it back to
  /// false to let a retry succeed.
  bool fails;

  /// When set, every call waits for it to complete — lets a test look at the
  /// loading state.
  Completer<void>? gate;

  /// How many times the catalog was fetched (a page or the whole list).
  int productsCalls = 0;

  /// Flags a product as sold by the store, the way the backend would after an
  /// add (or because another device added it).
  void markAdded(int productId, int storeProductId) {
    items = [
      for (final item in items)
        if (item.product.id == productId)
          CatalogItem(
            product: item.product,
            inMyStore: true,
            storeProductId: storeProductId,
            storeProductArchived: false,
          )
        else
          item,
    ];
  }

  /// Flags a product as archived in the store.
  void markArchived(int productId, int storeProductId) {
    items = [
      for (final item in items)
        if (item.product.id == productId)
          CatalogItem(
            product: item.product,
            inMyStore: false,
            storeProductId: storeProductId,
            storeProductArchived: true,
          )
        else
          item,
    ];
  }

  /// Removes a product from the catalog (the catalog archived it).
  void remove(int productId) {
    items = [
      for (final item in items)
        if (item.product.id != productId) item,
    ];
  }

  /// Every `browse` call, in order.
  final List<BrowseCall> browseCalls = [];

  /// Called at the start of every `browse`, before it answers — lets a test
  /// hold one request back (to make a reply arrive late) or count them.
  Future<void> Function(BrowseCall call)? onBrowse;

  @override
  Future<List<CatalogCategory>> categories() async {
    if (fails) {
      throw const NetworkException('offline');
    }
    if (categoryList.isNotEmpty) {
      return [...categoryList];
    }
    // Derived from the products, alphabetical, with how many each has.
    final byId = <int, CategoryRef>{};
    final counts = <int, int>{};
    for (final item in items) {
      byId[item.product.category.id] = item.product.category;
      counts[item.product.category.id] =
          (counts[item.product.category.id] ?? 0) + 1;
    }
    return [
      for (final category in byId.values)
        CatalogCategory(
          id: category.id,
          slug: category.slug,
          name: category.name,
          productCount: counts[category.id]!,
        ),
    ]..sort(
      (a, b) => SearchText.fold(a.name).compareTo(SearchText.fold(b.name)),
    );
  }

  @override
  Future<CatalogPage> browse({
    String? query,
    int? categoryId,
    String? cursor,
    int? limit,
  }) async {
    final call = BrowseCall(
      query: query,
      categoryId: categoryId,
      cursor: cursor,
      limit: limit,
    );
    browseCalls.add(call);
    productsCalls++;
    await onBrowse?.call(call);
    await gate?.future;
    if (fails) {
      throw const NetworkException('offline');
    }
    // `items` is already in the backend's order; the cursor is the index of
    // the first row of the next page.
    final matching = [
      for (final item in items)
        if ((categoryId == null || item.product.category.id == categoryId) &&
            SearchText.matches(
              '${item.product.name} ${item.product.brand?.name ?? ''} '
              '${item.product.category.name}',
              query ?? '',
            ))
          item,
    ];
    final start = cursor == null ? 0 : int.parse(cursor);
    final size = limit ?? 50;
    final end = (start + size).clamp(0, matching.length);
    return CatalogPage(
      items: matching.sublist(start.clamp(0, matching.length), end),
      total: matching.length,
      nextCursor: end < matching.length ? '$end' : null,
    );
  }

  @override
  Future<CatalogItem?> product(int productId) async {
    if (fails) {
      throw const NetworkException('offline');
    }
    for (final item in items) {
      if (item.product.id == productId) {
        return item;
      }
    }
    return null;
  }

  @override
  Future<List<CatalogItem>> products({int? categoryId}) async {
    productsCalls++;
    await gate?.future;
    if (fails) {
      throw const NetworkException('offline');
    }
    return [
      for (final item in items)
        if (categoryId == null || item.product.category.id == categoryId) item,
    ];
  }
}

/// What the picker asked `browse` for.
class BrowseCall {
  const BrowseCall({this.query, this.categoryId, this.cursor, this.limit});

  final String? query;
  final int? categoryId;
  final String? cursor;
  final int? limit;

  @override
  String toString() =>
      'BrowseCall(q: $query, categoryId: $categoryId, cursor: $cursor, limit: $limit)';
}

/// The store's offerings, in memory. Mirrors the backend's rules closely
/// enough for view-model and widget tests: archive/restore, the owner switch,
/// derived availability, and the stock-changed refusal.
class FakeStoreProductsRepository extends StoreProductsRepository {
  FakeStoreProductsRepository(
    super.apiClient, {
    List<StoreProduct> products = const [],
    this.fails = false,
    this.catalog = const [],
    this.onCreated,
  }) {
    for (final product in products) {
      _products.add(product);
      _nextId = product.id >= _nextId ? product.id + 1 : _nextId;
    }
  }

  final _products = <StoreProduct>[];
  var _nextId = 1;

  /// When true, listing fails like an unreachable backend.
  final bool fails;

  /// The catalog this store can add from (what `create` looks products up in).
  final List<CatalogItem> catalog;

  /// Called after a successful `create` — lets a test keep the fake catalog in
  /// step, the way the real backend's catalog listing follows.
  final void Function(StoreProduct created)? onCreated;

  /// When set, `create` fails with it (an [ApiException], [NetworkException]…).
  /// Clear it to let a retry succeed.
  Object? createError;

  /// What the last create / update sent, for assertions.
  NewStoreProduct? lastCreate;
  int createCalls = 0;
  StoreProductUpdate? lastUpdate;
  int? lastUpdatedId;
  int updateCalls = 0;
  int availabilityCalls = 0;
  int archiveCalls = 0;
  int restoreCalls = 0;

  /// When set, `update` / `setAvailability` / `archive` / `restore` fail with
  /// it. Clear it to let a retry succeed.
  Object? updateError;
  Object? availabilityError;
  Object? archiveError;
  Object? restoreError;

  /// An order (or another device) changes the stock behind the screen's back.
  void changeStockExternally(int id, int stock) {
    _products[_indexOf(id)] = rebuildStoreProduct(
      _products[_indexOf(id)],
      stockQuantity: stock,
      keepStock: false,
    );
  }

  List<String> get names => [
    for (final p in _products)
      if (!p.isArchived) p.product.name,
  ];

  StoreProduct byName(String name) =>
      _products.firstWhere((p) => p.product.name == name);

  int _indexOf(int id) => _products.indexWhere((p) => p.id == id);

  @override
  Future<List<StoreProduct>> list({
    StoreProductStatus status = StoreProductStatus.active,
    int? categoryId,
  }) async {
    if (fails) {
      throw const NetworkException('offline');
    }
    return [
      for (final p in _products)
        if ((status == StoreProductStatus.all ||
                p.isArchived == (status == StoreProductStatus.archived)) &&
            (categoryId == null || p.category.id == categoryId))
          p,
    ]..sort((a, b) => a.product.name.compareTo(b.product.name));
  }

  @override
  Future<StoreProduct> get(int id) async => _products[_indexOf(id)];

  @override
  Future<StoreProduct> create(NewStoreProduct input) async {
    createCalls++;
    lastCreate = input;
    final error = createError;
    if (error != null) {
      throw error;
    }
    if (_products.any((p) => p.productId == input.productId)) {
      throw const ApiException(
        statusCode: 409,
        message: 'Your store already sells this product',
      );
    }
    final product = catalog
        .firstWhere((item) => item.product.id == input.productId)
        .product;
    final unit = input.saleUnit ?? product.defaultSaleUnit;
    final created = fakeStoreProduct(
      id: _nextId++,
      product: product,
      saleUnit: unit,
      priceMillimes: input.priceMillimes,
      minQuantity: input.minQuantity ?? product.defaultMinQuantity,
      quantityStep: input.quantityStep ?? product.defaultQuantityStep,
      maxQuantity: input.noMaximum
          ? null
          : (input.maxQuantity ?? product.defaultMaxQuantity),
      trackStock: input.trackStock ?? false,
      stockQuantity: input.trackStock == true ? input.stockQuantity : null,
      isAvailable: input.isAvailable ?? true,
    );
    _products.add(created);
    onCreated?.call(created);
    return created;
  }

  @override
  Future<StoreProduct> setAvailability(
    int id, {
    required bool isAvailable,
  }) async {
    availabilityCalls++;
    if (availabilityError != null) {
      throw availabilityError!;
    }
    return _products[_indexOf(id)] = rebuildStoreProduct(
      _products[_indexOf(id)],
      isAvailable: isAvailable,
    );
  }

  @override
  Future<void> archive(int id) async {
    archiveCalls++;
    if (archiveError != null) {
      throw archiveError!;
    }
    _products[_indexOf(id)] = rebuildStoreProduct(
      _products[_indexOf(id)],
      isArchived: true,
    );
  }

  @override
  Future<StoreProduct> restore(int id) async {
    restoreCalls++;
    if (restoreError != null) {
      throw restoreError!;
    }
    return _products[_indexOf(id)] = rebuildStoreProduct(
      _products[_indexOf(id)],
      isArchived: false,
    );
  }

  @override
  Future<StoreProduct> update(int id, StoreProductUpdate input) async {
    updateCalls++;
    if (updateError != null) {
      throw updateError!;
    }
    lastUpdate = input;
    lastUpdatedId = id;
    final current = _products[_indexOf(id)];
    if (current.isArchived) {
      throw const ApiException(
        statusCode: 409,
        message: 'Archived products cannot be modified',
      );
    }
    final stock = input.stock;
    if (stock != null && stock.expectedStockQuantity != current.stockQuantity) {
      throw StockChangedException(currentStockQuantity: current.stockQuantity);
    }
    final trackStock = stock?.trackStock ?? current.trackStock;
    return _products[_indexOf(id)] = rebuildStoreProduct(
      current,
      priceMillimes: input.priceMillimes,
      saleUnit: input.saleUnit,
      minQuantity: input.minQuantity,
      quantityStep: input.quantityStep,
      maxQuantity: input.clearMaxQuantity ? null : input.maxQuantity,
      clearMaxQuantity: input.clearMaxQuantity,
      trackStock: trackStock,
      stockQuantity: !trackStock ? null : stock?.stockQuantity,
      keepStock: stock == null,
    );
  }
}

/// A copy of [p] with some fields changed. The derived availability is
/// recomputed the way the backend does it.
StoreProduct rebuildStoreProduct(
  StoreProduct p, {
  bool? isAvailable,
  bool? isArchived,
  int? priceMillimes,
  SaleUnit? saleUnit,
  int? minQuantity,
  int? quantityStep,
  int? maxQuantity,
  bool clearMaxQuantity = false,
  bool? trackStock,
  int? stockQuantity,
  bool keepStock = true,
}) {
  final track = trackStock ?? p.trackStock;
  final stock = keepStock ? p.stockQuantity : stockQuantity;
  final min = minQuantity ?? p.minQuantity;
  final available = isAvailable ?? p.isAvailable;
  final archived = isArchived ?? p.isArchived;
  final reason = archived
      ? UnavailabilityReason.archived
      : !available
      ? UnavailabilityReason.ownerDisabled
      : !p.product.isActive || !p.category.isActive
      ? UnavailabilityReason.catalogArchived
      : track && (stock ?? 0) <= 0
      ? UnavailabilityReason.outOfStock
      : track && stock! < min
      ? UnavailabilityReason.stockBelowMinimum
      : null;
  return StoreProduct(
    id: p.id,
    product: p.product,
    saleUnit: saleUnit ?? p.saleUnit,
    priceMillimes: priceMillimes ?? p.priceMillimes,
    minQuantity: min,
    quantityStep: quantityStep ?? p.quantityStep,
    maxQuantity: clearMaxQuantity ? null : (maxQuantity ?? p.maxQuantity),
    trackStock: track,
    stockQuantity: stock,
    isAvailable: available,
    isOrderable: reason == null,
    unavailabilityReason: reason,
    isArchived: archived,
  );
}

const fakeVegetables = CategoryRef(id: 3, slug: 'legumes', name: 'Légumes');
const fakePickerFruits = CategoryRef(id: 11, slug: 'fruits', name: 'Fruits');
const fakeFruits = CategoryRef(
  id: 1,
  slug: 'fruits-legumes',
  name: 'Fruits et légumes',
);
const fakeDairy = CategoryRef(
  id: 2,
  slug: 'produits-laitiers',
  name: 'Produits laitiers',
);

/// The global catalog product bananas/tomatoes/eggs are offerings of. It has
/// no price, stock or availability — those are the store product's.
CatalogProduct fakeCatalogProduct({
  int id = 1,
  String slug = 'tomate',
  String name = 'Tomate',
  CategoryRef category = fakeFruits,
  SaleUnit unit = SaleUnit.kg,
  int min = 500,
  int step = 100,
  int? max = 10000,
  Brand? brand,
  String? photo,
}) => CatalogProduct(
  id: id,
  slug: slug,
  name: name,
  photo: photo,
  brand: brand,
  category: category,
  defaultSaleUnit: unit,
  allowedSaleUnits: unit == SaleUnit.piece
      ? const [SaleUnit.piece]
      : [unit, SaleUnit.piece],
  defaultMinQuantity: min,
  defaultQuantityStep: step,
  defaultMaxQuantity: max,
);

/// A row of the catalog picker.
CatalogItem fakeCatalogItem({
  required int id,
  required String name,
  String? slug,
  CategoryRef category = fakePickerFruits,
  SaleUnit unit = SaleUnit.kg,
  bool inMyStore = false,
  bool storeProductArchived = false,
  Brand? brand,
  String? photo,
}) => CatalogItem(
  product: fakeCatalogProduct(
    brand: brand,
    photo: photo,
    id: id,
    slug: slug ?? name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'),
    name: name,
    category: category,
    unit: unit,
  ),
  inMyStore: inMyStore,
  storeProductId: inMyStore || storeProductArchived ? 100 + id : null,
  storeProductArchived: storeProductArchived,
);

/// A small catalog: fruits, vegetables and dairy, with Banane already in the
/// store.
List<CatalogItem> fakeCatalogItems() => [
  fakeCatalogItem(id: 1, name: 'Banane', inMyStore: true),
  fakeCatalogItem(id: 2, name: 'Pomme'),
  fakeCatalogItem(id: 3, name: 'Pomme de terre', category: fakeVegetables),
  fakeCatalogItem(id: 4, name: 'Tomate', category: fakeVegetables),
  fakeCatalogItem(
    id: 5,
    name: 'Œufs',
    slug: 'oeufs',
    category: fakeDairy,
    unit: SaleUnit.piece,
  ),
  fakeCatalogItem(
    id: 6,
    name: 'Lait entier 1 L',
    category: fakeDairy,
    unit: SaleUnit.piece,
  ),
];

/// A store's offering of [product].
StoreProduct fakeStoreProduct({
  int id = 1,
  CatalogProduct? product,
  SaleUnit? saleUnit,
  int priceMillimes = 1800,
  int minQuantity = 500,
  int quantityStep = 500,
  int? maxQuantity = 10000,
  bool trackStock = false,
  int? stockQuantity,
  bool isAvailable = true,
  bool isArchived = false,
}) {
  final catalog = product ?? fakeCatalogProduct();
  return rebuildStoreProduct(
    StoreProduct(
      id: id,
      product: catalog,
      saleUnit: saleUnit ?? catalog.defaultSaleUnit,
      priceMillimes: priceMillimes,
      minQuantity: minQuantity,
      quantityStep: quantityStep,
      maxQuantity: maxQuantity,
      trackStock: trackStock,
      stockQuantity: stockQuantity,
      isAvailable: true,
      isOrderable: true,
    ),
    isAvailable: isAvailable,
    isArchived: isArchived,
  );
}

/// A KG product: 1,800 DT/kg, ordered by 500 g up to 10 kg.
StoreProduct fakeTomatoes({
  int id = 1,
  CategoryRef category = fakeFruits,
  bool isAvailable = true,
  bool trackStock = false,
  int? stockQuantity,
}) => fakeStoreProduct(
  id: id,
  product: fakeCatalogProduct(id: id, category: category),
  isAvailable: isAvailable,
  trackStock: trackStock,
  stockQuantity: stockQuantity,
);

/// A PIECE product: 0,350 DT each.
StoreProduct fakeEggs({int id = 2, CategoryRef category = fakeDairy}) =>
    fakeStoreProduct(
      id: id,
      product: fakeCatalogProduct(
        id: id,
        slug: 'oeufs',
        name: 'Œufs',
        category: category,
        unit: SaleUnit.piece,
        min: 1,
        step: 1,
        max: null,
      ),
      priceMillimes: 350,
      minQuantity: 1,
      quantityStep: 1,
      maxQuantity: null,
    );

const testOwner = User(
  id: 1,
  name: 'Karim',
  email: 'karim@example.com',
  phoneNumber: '+21612345678',
  role: UserRole.owner,
);

const testClient = User(
  id: 2,
  name: 'Sana',
  email: 'sana@example.com',
  phoneNumber: '+21698765432',
  role: UserRole.client,
);

const closedStore = Store(
  id: 10,
  name: 'Menzah Market',
  address: '12 Rue de la Liberté, Tunis',
  isOpen: false,
  ownerId: 1,
);

/// Boots the whole app with an already-stored session for [user].
Future<void> pumpAppSignedInAs(
  WidgetTester tester,
  User user, {
  required StoreRepository Function(ApiClient) storeRepository,
  CatalogRepository Function(ApiClient)? catalogRepository,
  StoreProductsRepository Function(ApiClient)? storeProductsRepository,
  OrdersRepository Function(ApiClient)? ordersRepository,
  CustomerStoresRepository Function(ApiClient)? customerStoresRepository,
  CustomerOrdersRepository Function(ApiClient)? customerOrdersRepository,
  FakeAuthRepository Function(ApiClient)? authRepository,
  TokenStorage? tokenStorage,
  ImagePickerService? imagePickerService,
}) async {
  final apiClient = ApiClient();
  await tester.pumpWidget(
    GroceryApp(
      imagePickerService: imagePickerService ?? FakeImagePickerService(),
      authViewModel: AuthViewModel(
        authRepository:
            (authRepository ?? (api) => FakeAuthRepository(api, user))(
              apiClient,
            ),
        tokenStorage: tokenStorage ?? StoredToken(),
        apiClient: apiClient,
      ),
      storeRepository: storeRepository(apiClient),
      catalogRepository: (catalogRepository ?? FakeCatalogRepository.new)(
        apiClient,
      ),
      storeProductsRepository:
          (storeProductsRepository ?? FakeStoreProductsRepository.new)(
            apiClient,
          ),
      ordersRepository: (ordersRepository ?? FakeOrdersRepository.new)(
        apiClient,
      ),
      customerStoresRepository:
          (customerStoresRepository ?? FakeCustomerStoresRepository.new)(
            apiClient,
          ),
      customerOrdersRepository:
          (customerOrdersRepository ?? FakeCustomerOrdersRepository.new)(
            apiClient,
          ),
    ),
  );
  await tester.pumpAndSettle();
}

// ── Orders ────────────────────────────────────────────────────────────────

/// An order as the owner's API returns it. Defaults: a pending order of two
/// lines (tomatoes 500 g, eggs ×6), placed by Sana, to be picked up in 4 h.
Order fakeOrder({
  int id = 1,
  String code = 'K7M2QX',
  OrderStatus status = OrderStatus.pending,
  String customerName = 'Sana Ben Ali',
  String customerPhone = '+21698765432',
  DateTime? requestedPickupAt,
  DateTime? createdAt,
  List<OrderItem>? items,
  List<OrderEvent>? events,
  int? totalMillimes,
  bool storeAdjusted = false,
}) {
  final lines =
      items ??
      [
        fakeOrderItem(id: id * 10 + 1),
        fakeOrderItem(
          id: id * 10 + 2,
          name: 'Œufs',
          unit: SaleUnit.piece,
          quantity: 6,
          unitPrice: 350,
          lineTotal: 2100,
        ),
      ];
  final created = createdAt ?? DateTime.utc(2026, 10, 4, 14, 48, 2, 454);
  return Order(
    id: id,
    code: code,
    status: status,
    requestedPickupAt:
        requestedPickupAt ??
        DateTime.now().toUtc().add(const Duration(hours: 4)),
    totalMillimes:
        totalMillimes ??
        lines
            .where((line) => !line.isRemoved)
            .fold(0, (sum, line) => sum + line.lineTotalMillimes),
    storeAdjusted: storeAdjusted || lines.any((line) => line.isRemoved),
    customerName: customerName,
    customerPhone: customerPhone,
    items: lines,
    events:
        events ??
        [
          OrderEvent(
            toStatus: OrderStatus.pending,
            actorType: OrderActorType.client,
            createdAt: created,
          ),
        ],
    createdAt: created,
    updatedAt: created,
  );
}

OrderItem fakeOrderItem({
  int id = 1,
  String name = 'Tomate',
  SaleUnit unit = SaleUnit.kg,
  int quantity = 500,
  int unitPrice = 1800,
  int lineTotal = 900,
  DateTime? removedAt,
}) => OrderItem(
  id: id,
  productName: name,
  saleUnit: unit,
  quantity: quantity,
  unitPriceMillimes: unitPrice,
  lineTotalMillimes: lineTotal,
  removedAt: removedAt,
);

/// The owner's orders, in memory. Lists newest first with the backend's
/// paging and status filter; transitions follow the backend's lifecycle just
/// closely enough for the screens (the real rules are the backend's).
class FakeOrdersRepository extends OrdersRepository {
  FakeOrdersRepository(
    super.apiClient, {
    List<Order> orders = const [],
    this.fails = false,
  }) : _orders = [...orders];

  List<Order> _orders;

  /// While true, every call fails like an unreachable backend.
  bool fails;

  /// While non-null, `list` / `get` / transitions fail with it.
  Object? listError;
  Object? getError;
  Object? transitionError;

  /// When set, `list` waits for it — lets a test look at the loading state or
  /// overlap requests.
  Completer<void>? gate;

  final listCalls = <({OrderStatus? status, int page, int limit})>[];
  int getCalls = 0;

  /// `confirm` / `cancel` / … calls, as `action:id` (and what they sent).
  final transitions = <String>[];
  List<int>? lastRemoved;
  String? lastReason;

  /// What the next `get` answers for [id] (e.g. the customer cancelled).
  void replace(Order order) {
    _orders = [
      for (final o in _orders)
        if (o.id == order.id) order else o,
    ];
  }

  void add(Order order) => _orders = [..._orders, order];

  Order byId(int id) => _orders.firstWhere((o) => o.id == id);

  int get listCallCount => listCalls.length;

  @override
  Future<OrderPage> list({
    OrderStatus? status,
    int page = 1,
    int limit = 20,
  }) async {
    listCalls.add((status: status, page: page, limit: limit));
    await gate?.future;
    if (fails) {
      throw const NetworkException('offline');
    }
    if (listError != null) {
      throw listError!;
    }
    final matching = [
      for (final o in _orders)
        if (status == null || o.status == status) o,
    ]..sort((a, b) => b.id.compareTo(a.id));
    final start = (page - 1) * limit;
    return OrderPage(
      orders: matching.skip(start).take(limit).toList(),
      page: page,
      limit: limit,
      total: matching.length,
    );
  }

  @override
  Future<Order> get(int id) async {
    getCalls++;
    if (fails) {
      throw const NetworkException('offline');
    }
    if (getError != null) {
      throw getError!;
    }
    return byId(id);
  }

  @override
  Future<OrderTransition> confirm(
    int id, {
    List<int> removeItemIds = const [],
  }) {
    lastRemoved = removeItemIds;
    return _move(id, 'confirm', OrderStatus.confirmed, removed: removeItemIds);
  }

  @override
  Future<OrderTransition> markReady(int id) =>
      _move(id, 'ready', OrderStatus.readyForPickup);

  @override
  Future<OrderTransition> complete(int id) =>
      _move(id, 'complete', OrderStatus.completed);

  @override
  Future<OrderTransition> cancel(int id, {required String reason}) {
    lastReason = reason;
    return _move(id, 'cancel', OrderStatus.cancelled, reason: reason);
  }

  @override
  Future<OrderTransition> markNoShow(int id) =>
      _move(id, 'no-show', OrderStatus.noShow);

  Future<OrderTransition> _move(
    int id,
    String action,
    OrderStatus target, {
    List<int> removed = const [],
    String? reason,
  }) async {
    transitions.add('$action:$id');
    if (fails) {
      throw const NetworkException('offline');
    }
    if (transitionError != null) {
      throw transitionError!;
    }
    final current = byId(id);
    final now = DateTime.now().toUtc();
    final items = [
      for (final item in current.items)
        removed.contains(item.id) && !item.isRemoved
            ? fakeOrderItem(
                id: item.id,
                name: item.productName,
                unit: item.saleUnit,
                quantity: item.quantity,
                unitPrice: item.unitPriceMillimes,
                lineTotal: item.lineTotalMillimes,
                removedAt: now,
              )
            : item,
    ];
    final updated = Order(
      id: current.id,
      code: current.code,
      status: target,
      requestedPickupAt: current.requestedPickupAt,
      totalMillimes: items
          .where((item) => !item.isRemoved)
          .fold(0, (sum, item) => sum + item.lineTotalMillimes),
      storeAdjusted: items.any((item) => item.isRemoved),
      customerName: current.customerName,
      customerPhone: current.customerPhone,
      items: items,
      events: [
        ...current.events,
        OrderEvent(
          fromStatus: current.status,
          toStatus: target,
          actorType: OrderActorType.owner,
          reason: reason,
          createdAt: now,
        ),
      ],
      createdAt: current.createdAt,
      updatedAt: now,
    );
    replace(updated);
    return OrderTransition(changed: true, order: updated);
  }
}

/// The backend's 409 for an order that is not where the screen thought.
const orderStateChanged = ApiException(
  statusCode: 409,
  code: 'ORDER_STATE_CHANGED',
  message: 'Order is CANCELLED; it cannot move to CONFIRMED',
);

// ── Customer ──────────────────────────────────────────────────────────────

CustomerStore fakeCustomerStore({
  int id = 10,
  String name = 'Menzah Market',
  String address = '12 Rue de la Liberté, Tunis',
  bool isOpen = true,
  String? photo,
  String? description,
}) => CustomerStore(
  id: id,
  name: name,
  address: address,
  isOpen: isOpen,
  photo: photo,
  description: description,
);

const fakeFruitsCategory = CategoryRef(id: 1, slug: '', name: 'Fruits');
const fakeDairyCategory = CategoryRef(
  id: 2,
  slug: '',
  name: 'Produits laitiers',
);

/// A product of a store's catalogue as a customer sees it. Defaults: bananas
/// sold by the kilo at 1,800 DT, from 500 g, by 100 g, up to 5 kg.
CustomerProduct fakeCustomerProduct({
  int id = 1,
  String name = 'Banane',
  String? description,
  Brand? brand,
  String? photo,
  CategoryRef category = fakeFruitsCategory,
  SaleUnit unit = SaleUnit.kg,
  int priceMillimes = 1800,
  int minQuantity = 500,
  int quantityStep = 100,
  int? maxQuantity = 5000,
  bool isOrderable = true,
  UnavailabilityReason? reason,
}) => CustomerProduct(
  id: id,
  name: name,
  description: description,
  brand: brand,
  photo: photo,
  category: category,
  saleUnit: unit,
  priceMillimes: priceMillimes,
  minQuantity: minQuantity,
  quantityStep: quantityStep,
  maxQuantity: maxQuantity,
  isOrderable: isOrderable,
  unavailabilityReason: isOrderable
      ? null
      : (reason ?? UnavailabilityReason.ownerDisabled),
);

/// Milk: sold by the piece at 1,200 DT, from 1, up to 12.
CustomerProduct fakeMilk({int id = 2, bool isOrderable = true}) =>
    fakeCustomerProduct(
      id: id,
      name: 'Lait Délice 1 L',
      description: 'Lait demi-écrémé',
      category: fakeDairyCategory,
      unit: SaleUnit.piece,
      priceMillimes: 1200,
      minQuantity: 1,
      quantityStep: 1,
      maxQuantity: 12,
      isOrderable: isOrderable,
    );

/// The stores and their catalogues, in memory. Each store answers only with
/// its own products, like the backend.
class FakeCustomerStoresRepository extends CustomerStoresRepository {
  FakeCustomerStoresRepository(
    super.apiClient, {
    List<CustomerStore> stores = const [],
    Map<int, List<CustomerProduct>> products = const {},
    this.fails = false,
  }) : _stores = [...stores],
       _products = {
         for (final e in products.entries) e.key: [...e.value],
       };

  List<CustomerStore> _stores;
  final Map<int, List<CustomerProduct>> _products;

  /// While true, every call fails like an unreachable backend.
  bool fails;

  /// `products` fails for these stores only.
  final failingStores = <int>{};

  /// The store ids `products` was asked for, in order.
  final productCalls = <int>[];
  int storeCalls = 0;

  void setStores(List<CustomerStore> stores) => _stores = [...stores];

  void setProducts(int storeId, List<CustomerProduct> products) =>
      _products[storeId] = [...products];

  @override
  Future<List<CustomerStore>> stores() async {
    storeCalls++;
    if (fails) {
      throw const NetworkException('offline');
    }
    return [..._stores];
  }

  @override
  Future<List<CustomerProduct>> products(int storeId) async {
    productCalls.add(storeId);
    if (fails || failingStores.contains(storeId)) {
      throw const NetworkException('offline');
    }
    if (!_stores.any((s) => s.id == storeId)) {
      throw const ApiException(statusCode: 404);
    }
    return [...?_products[storeId]];
  }
}

/// The customer's orders, in memory. `create` answers like the backend would:
/// with the server's own prices and total (taken from [catalog]), whatever the
/// client estimated.
class FakeCustomerOrdersRepository extends CustomerOrdersRepository {
  FakeCustomerOrdersRepository(
    super.apiClient, {
    List<CustomerOrder> orders = const [],
    this.catalog = const {},
    this.storeName = 'Menzah Market',
  }) : _orders = [...orders];

  List<CustomerOrder> _orders;

  /// Store product id → what the server knows about it (name, unit, price).
  final Map<int, CustomerProduct> catalog;
  final String storeName;

  /// Every request `create` received, in order.
  final created = <NewOrderRequest>[];

  /// When non-empty, the next `create` calls fail with these, in order.
  final createErrors = <Object>[];

  /// Overrides the answer to a successful `create`.
  CustomerOrder Function(NewOrderRequest request)? respond;

  /// Called after a `create` that failed with a network error *as if it had
  /// reached the server first* (the timeout case): the order exists.
  bool createThenTimeout = false;

  Object? listError;
  Object? getError;
  Object? cancelError;
  Completer<void>? gate;

  final listCalls = <({int page, int limit})>[];
  int getCalls = 0;
  int cancelCalls = 0;
  int _nextId = 100;
  final _byKey = <String, CustomerOrder>{};

  void replace(CustomerOrder order) {
    _orders = [
      for (final o in _orders)
        if (o.id == order.id) order else o,
    ];
  }

  void add(CustomerOrder order) => _orders = [..._orders, order];

  CustomerOrder byId(int id) => _orders.firstWhere((o) => o.id == id);

  @override
  Future<CustomerOrder> create(NewOrderRequest request) async {
    created.add(request);
    if (createErrors.isNotEmpty) {
      throw createErrors.removeAt(0);
    }
    // The backend's idempotency: same key → the original order.
    final existing = _byKey[request.idempotencyKey];
    final order = existing ?? (respond?.call(request) ?? _build(request));
    if (existing == null) {
      _byKey[request.idempotencyKey] = order;
      add(order);
    }
    if (createThenTimeout) {
      createThenTimeout = false;
      throw const NetworkException('timeout');
    }
    return order;
  }

  CustomerOrder _build(NewOrderRequest request) {
    final items = [
      for (final (i, line) in request.lines.indexed)
        () {
          final product = catalog[line.storeProductId]!;
          return OrderItem(
            id: _nextId * 10 + i,
            productName: product.name,
            saleUnit: product.saleUnit,
            quantity: line.quantity,
            unitPriceMillimes: product.priceMillimes,
            lineTotalMillimes: product.saleUnit.lineTotalMillimes(
              priceMillimes: product.priceMillimes,
              quantity: line.quantity,
            ),
          );
        }(),
    ];
    final now = DateTime.now().toUtc();
    return CustomerOrder(
      id: _nextId++,
      code: 'SRV${_nextId}X',
      status: OrderStatus.pending,
      requestedPickupAt: request.requestedPickupAt.toUtc(),
      totalMillimes: items.fold(0, (sum, i) => sum + i.lineTotalMillimes),
      storeAdjusted: false,
      storeName: storeName,
      storeAddress: '12 Rue de la Liberté, Tunis',
      items: items,
      events: [
        OrderEvent(
          toStatus: OrderStatus.pending,
          actorType: OrderActorType.client,
          createdAt: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<CustomerOrderPage> list({int page = 1, int limit = 20}) async {
    listCalls.add((page: page, limit: limit));
    await gate?.future;
    if (listError != null) {
      throw listError!;
    }
    final sorted = [..._orders]..sort((a, b) => b.id.compareTo(a.id));
    return CustomerOrderPage(
      orders: sorted.skip((page - 1) * limit).take(limit).toList(),
      page: page,
      limit: limit,
      total: sorted.length,
    );
  }

  @override
  Future<CustomerOrder> get(int id) async {
    getCalls++;
    if (getError != null) {
      throw getError!;
    }
    return byId(id);
  }

  @override
  Future<CustomerOrderTransition> cancel(int id) async {
    cancelCalls++;
    if (cancelError != null) {
      throw cancelError!;
    }
    final current = byId(id);
    final now = DateTime.now().toUtc();
    final updated = CustomerOrder(
      id: current.id,
      code: current.code,
      status: OrderStatus.cancelled,
      requestedPickupAt: current.requestedPickupAt,
      totalMillimes: current.totalMillimes,
      storeAdjusted: current.storeAdjusted,
      storeName: current.storeName,
      storeAddress: current.storeAddress,
      items: current.items,
      events: [
        ...current.events,
        OrderEvent(
          fromStatus: current.status,
          toStatus: OrderStatus.cancelled,
          actorType: OrderActorType.client,
          createdAt: now,
        ),
      ],
      createdAt: current.createdAt,
      updatedAt: now,
    );
    replace(updated);
    return CustomerOrderTransition(changed: true, order: updated);
  }
}

/// A customer order as the API returns it: one line of bananas, pending.
CustomerOrder fakeCustomerOrder({
  int id = 1,
  String code = 'K7M2QX',
  OrderStatus status = OrderStatus.pending,
  String storeName = 'Menzah Market',
  DateTime? requestedPickupAt,
  List<OrderItem>? items,
  List<OrderEvent>? events,
  int? totalMillimes,
}) {
  final created = DateTime.utc(2026, 10, 4, 14, 48, 2, 454);
  final lines =
      items ??
      [
        fakeOrderItem(id: id * 10 + 1, lineTotal: 900),
        fakeOrderItem(
          id: id * 10 + 2,
          name: 'Lait Délice 1 L',
          unit: SaleUnit.piece,
          quantity: 2,
          unitPrice: 1200,
          lineTotal: 2400,
        ),
      ];
  return CustomerOrder(
    id: id,
    code: code,
    status: status,
    requestedPickupAt:
        requestedPickupAt ??
        DateTime.now().toUtc().add(const Duration(hours: 4)),
    totalMillimes:
        totalMillimes ??
        lines
            .where((l) => !l.isRemoved)
            .fold(0, (s, l) => s + l.lineTotalMillimes),
    storeAdjusted: lines.any((l) => l.isRemoved),
    storeName: storeName,
    storeAddress: '12 Rue de la Liberté, Tunis',
    items: lines,
    events:
        events ??
        [
          OrderEvent(
            toStatus: OrderStatus.pending,
            actorType: OrderActorType.client,
            createdAt: created,
          ),
        ],
    createdAt: created,
    updatedAt: created,
  );
}

/// The backend's 409 for an order that is not where the screen thought.
const customerOrderStateChanged = ApiException(
  statusCode: 409,
  code: 'ORDER_STATE_CHANGED',
);

// ── Photos ────────────────────────────────────────────────────────────────

/// A real 1×1 PNG, so the preview decodes like a photo would.
final tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

PickedImage fakePickedImage({String name = 'photo.png'}) => PickedImage(
  bytes: Uint8List.fromList(tinyPng),
  filename: name,
  contentType: 'image/png',
);

/// Stands in for the camera and library: answers with what it is given, and
/// records which source was asked for.
class FakeImagePickerService implements ImagePickerService {
  /// What the next picks return, in order; `null` is "cancelled". When the
  /// queue is empty a small PNG is returned.
  final results = <PickedImage?>[];

  /// While non-null, `pick` throws it.
  Object? error;

  final calls = <PhotoSource>[];

  @override
  Future<PickedImage?> pick(PhotoSource source) async {
    calls.add(source);
    if (error != null) {
      throw error!;
    }
    return results.isEmpty ? fakePickedImage() : results.removeAt(0);
  }
}
