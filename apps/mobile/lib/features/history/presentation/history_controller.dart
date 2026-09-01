import 'package:ai_image_studio/features/generate/data/generate_repository.dart';
import 'package:ai_image_studio/features/generate/data/image_task.dart';
import 'package:ai_image_studio/features/generate/presentation/generate_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final historyControllerProvider =
    StateNotifierProvider.autoDispose<HistoryController, HistoryState>(
  (ref) => HistoryController(ref.watch(generateRepositoryProvider)),
);
final taskDetailProvider = FutureProvider.autoDispose.family<ImageTask, String>(
  (ref, taskId) => ref.watch(generateRepositoryProvider).get(taskId),
);

class HistoryState {
  const HistoryState(
      {this.tasks = const [],
      this.nextCursor = '',
      this.loading = false,
      this.errorMessage});
  final List<ImageTask> tasks;
  final String nextCursor;
  final bool loading;
  final String? errorMessage;
}

class HistoryController extends StateNotifier<HistoryState> {
  HistoryController(this._repository) : super(const HistoryState());
  final GenerateRepository _repository;
  Future<void> refresh() => _load(replace: true);
  Future<void> loadMore() async {
    if (state.loading || state.nextCursor.isEmpty) return;
    await _load(replace: false);
  }

  Future<void> _load({required bool replace}) async {
    if (state.loading) return;
    state = HistoryState(
        tasks: state.tasks, nextCursor: state.nextCursor, loading: true);
    try {
      final page =
          await _repository.list(cursor: replace ? '' : state.nextCursor);
      state = HistoryState(
          tasks: replace ? page.tasks : [...state.tasks, ...page.tasks],
          nextCursor: page.nextCursor);
    } catch (error) {
      state = HistoryState(
          tasks: state.tasks,
          nextCursor: state.nextCursor,
          errorMessage: error.toString());
    }
  }
}
