import 'package:e1547/app/app.dart';
import 'package:e1547/client/client.dart';
import 'package:e1547/identity/identity.dart';
import 'package:e1547/shared/shared.dart';
import 'package:e1547/task/task.dart';

class TasksListController extends PageClientDataController<Task> {
  TasksListController({
    required this.client,
    required this.repository,
    required this.identity,
  });

  @override
  final Client client;
  final TaskRepository repository;
  final int identity;

  @override
  Future<List<Task>> fetch(int page, bool force) =>
      repository.page(page: page, identity: identity);
}

class TasksListProvider
    extends
        SubChangeNotifierProvider3<
          Client,
          AppStorage,
          IdentityClient,
          TasksListController
        > {
  TasksListProvider({super.child, super.builder})
    : super(
        create: (context, client, storage, identity) => TasksListController(
          client: client,
          repository: TaskRepository(database: storage.sqlite),
          identity: identity.identity.id,
        ),
      );
}
