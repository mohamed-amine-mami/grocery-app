import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/auth_response.dart';
import 'package:grocery_mobile/data/models/product.dart';
import 'package:grocery_mobile/data/models/sale_unit.dart';
import 'package:grocery_mobile/data/models/store.dart';
import 'package:grocery_mobile/data/models/store_category.dart';
import 'package:grocery_mobile/data/models/user.dart';
import 'package:grocery_mobile/data/repositories/auth_repository.dart';
import 'package:grocery_mobile/data/repositories/category_repository.dart';
import 'package:grocery_mobile/data/repositories/product_repository.dart';
import 'package:grocery_mobile/data/repositories/store_repository.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
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

  final User _user;

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
    String? photo,
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
    String? photo,
    double? latitude,
    double? longitude,
  }) async {
    lastUpdate = {
      'name': name,
      'address': address,
      'description': description,
      'photo': photo,
      'latitude': latitude,
      'longitude': longitude,
    };
    return store = Store(
      id: store!.id,
      name: name,
      address: address,
      description: description,
      photo: photo,
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

class FakeCategoryRepository extends CategoryRepository {
  FakeCategoryRepository(
    super.apiClient, {
    List<String> names = const [],
    this.fails = false,
  }) {
    for (final name in names) {
      _categories.add(StoreCategory(id: _nextId++, name: name));
    }
  }

  final _categories = <StoreCategory>[];
  var _nextId = 1;

  /// When true, `list()` fails like an unreachable backend.
  final bool fails;

  List<String> get names => [for (final c in _categories) c.name];

  bool _taken(String name, {int? exceptId}) => _categories.any(
    (c) => c.id != exceptId && c.name.toLowerCase() == name.toLowerCase(),
  );

  @override
  Future<List<StoreCategory>> list() async {
    if (fails) {
      throw const NetworkException('offline');
    }
    return [..._categories]..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Future<StoreCategory> create(String name) async {
    if (_taken(name)) {
      throw const ApiException(statusCode: 409);
    }
    final category = StoreCategory(id: _nextId++, name: name);
    _categories.add(category);
    return category;
  }

  @override
  Future<StoreCategory> rename(int id, String name) async {
    if (_taken(name, exceptId: id)) {
      throw const ApiException(statusCode: 409);
    }
    final index = _categories.indexWhere((c) => c.id == id);
    return _categories[index] = StoreCategory(id: id, name: name);
  }

  @override
  Future<void> delete(int id) async {
    _categories.removeWhere((c) => c.id == id);
  }
}

class FakeProductRepository extends ProductRepository {
  FakeProductRepository(super.apiClient, {List<Product> products = const []}) {
    for (final product in products) {
      _products.add(product);
      _nextId = product.id >= _nextId ? product.id + 1 : _nextId;
    }
  }

  final _products = <Product>[];
  var _nextId = 1;

  /// What the last create/update sent, for assertions.
  ProductInput? lastInput;
  int? lastUpdatedId;

  List<String> get names => [
    for (final p in _products)
      if (!p.isArchived) p.name,
  ];

  Product byName(String name) => _products.firstWhere((p) => p.name == name);

  bool _nameTaken(String name, {int? exceptId}) => _products.any(
    (p) =>
        !p.isArchived &&
        p.id != exceptId &&
        p.name.toLowerCase() == name.toLowerCase(),
  );

  Product _fromInput(int id, ProductInput input, {bool isAvailable = true}) =>
      Product(
        id: id,
        categoryId: input.categoryId,
        name: input.name,
        description: input.description,
        photo: input.photo,
        saleUnit: input.saleUnit,
        priceMillimes: input.priceMillimes,
        minQuantity: input.minQuantity,
        quantityStep: input.quantityStep,
        maxQuantity: input.maxQuantity,
        isAvailable: isAvailable,
      );

  @override
  Future<List<Product>> listActive() async => [
    for (final p in _products)
      if (!p.isArchived) p,
  ]..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<Product> create(ProductInput input) async {
    lastInput = input;
    if (_nameTaken(input.name)) {
      throw const ApiException(statusCode: 409);
    }
    final product = _fromInput(_nextId++, input);
    _products.add(product);
    return product;
  }

  @override
  Future<Product> update(int id, ProductInput input) async {
    lastInput = input;
    lastUpdatedId = id;
    if (_nameTaken(input.name, exceptId: id)) {
      throw const ApiException(statusCode: 409);
    }
    final index = _products.indexWhere((p) => p.id == id);
    return _products[index] = _fromInput(
      id,
      input,
      isAvailable: _products[index].isAvailable,
    );
  }

  @override
  Future<Product> setAvailability(int id, {required bool isAvailable}) async {
    final index = _products.indexWhere((p) => p.id == id);
    return _products[index] = _products[index].copyWith(
      isAvailable: isAvailable,
    );
  }

  @override
  Future<void> archive(int id) async {
    final index = _products.indexWhere((p) => p.id == id);
    final p = _products[index];
    _products[index] = Product(
      id: p.id,
      categoryId: p.categoryId,
      name: p.name,
      saleUnit: p.saleUnit,
      priceMillimes: p.priceMillimes,
      minQuantity: p.minQuantity,
      quantityStep: p.quantityStep,
      isAvailable: p.isAvailable,
      isArchived: true,
    );
  }
}

/// A KG product: 1,800 DT/kg, ordered by 500 g up to 10 kg.
Product fakeTomatoes({int id = 1, int? categoryId, bool isAvailable = true}) =>
    Product(
      id: id,
      categoryId: categoryId,
      name: 'Tomates',
      saleUnit: SaleUnit.kg,
      priceMillimes: 1800,
      minQuantity: 500,
      quantityStep: 500,
      maxQuantity: 10000,
      isAvailable: isAvailable,
    );

/// A PIECE product: 0,350 DT each.
Product fakeEggs({int id = 2, int? categoryId}) => Product(
  id: id,
  categoryId: categoryId,
  name: 'Œufs',
  saleUnit: SaleUnit.piece,
  priceMillimes: 350,
  minQuantity: 1,
  quantityStep: 1,
  isAvailable: true,
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
  CategoryRepository Function(ApiClient)? categoryRepository,
  ProductRepository Function(ApiClient)? productRepository,
  FakeAuthRepository Function(ApiClient)? authRepository,
  TokenStorage? tokenStorage,
}) async {
  final apiClient = ApiClient();
  await tester.pumpWidget(
    GroceryApp(
      authViewModel: AuthViewModel(
        authRepository:
            (authRepository ?? (api) => FakeAuthRepository(api, user))(
              apiClient,
            ),
        tokenStorage: tokenStorage ?? StoredToken(),
        apiClient: apiClient,
      ),
      storeRepository: storeRepository(apiClient),
      categoryRepository: (categoryRepository ?? FakeCategoryRepository.new)(
        apiClient,
      ),
      productRepository: (productRepository ?? FakeProductRepository.new)(
        apiClient,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
