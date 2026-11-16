import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/local_store.dart';
import '../core/database/maintainly_database.dart';
import '../data/repositories/maintainly_repository.dart';
import 'maintainly_controller.dart';

final maintainlyControllerProvider =
    ChangeNotifierProvider<MaintainlyController>((ref) {
      final storeFuture = LocalStore.create();
      final repositoryFuture = storeFuture.then(
        (store) => MaintainlyRepository(
          store,
          database: MaintainlyDatabase(),
          autoMigrateLegacyDataOnLoad: true,
        ),
      );
      final placeholder = MaintainlyController(
        _DeferredRepository(repositoryFuture),
      );
      placeholder.initialize();
      return placeholder;
    });

class _DeferredRepository implements MaintainlyRepository {
  _DeferredRepository(this._future);
  final Future<MaintainlyRepository> _future;

  @override
  Future<MaintainlyData> load() async => (await _future).load();

  @override
  Future<void> save(MaintainlyData data) async => (await _future).save(data);

  @override
  Future<void> restore(MaintainlyData data) async =>
      (await _future).restore(data);
}
