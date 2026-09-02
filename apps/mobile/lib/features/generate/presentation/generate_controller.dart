import 'dart:async';
import 'package:ai_image_studio/features/auth/presentation/auth_controller.dart';
import 'package:ai_image_studio/features/generate/data/generate_repository.dart';
import 'package:ai_image_studio/features/generate/data/image_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final generateRepositoryProvider = Provider<GenerateRepository>(
    (ref) => GenerateRepository(ref.watch(apiClientProvider)));
final generateControllerProvider =
    StateNotifierProvider.autoDispose<GenerateController, GenerateState>(
        (ref) => GenerateController(ref.watch(generateRepositoryProvider)));

class GenerateState {
  const GenerateState(
      {this.prompt = '',
      this.aspectRatio = '1:1',
      this.count = 1,
      this.promptOptimizer = true,
      this.submitting = false,
      this.task,
      this.errorMessage});
  final String prompt;
  final String aspectRatio;
  final int count;
  final bool promptOptimizer;
  final bool submitting;
  final ImageTask? task;
  final String? errorMessage;
  GenerateState copyWith(
          {String? prompt,
          String? aspectRatio,
          int? count,
          bool? promptOptimizer,
          bool? submitting,
          ImageTask? task,
          String? errorMessage,
          bool clearError = false}) =>
      GenerateState(
        prompt: prompt ?? this.prompt,
        aspectRatio: aspectRatio ?? this.aspectRatio,
        count: count ?? this.count,
        promptOptimizer: promptOptimizer ?? this.promptOptimizer,
        submitting: submitting ?? this.submitting,
        task: task ?? this.task,
        errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      );
}

class GenerateController extends StateNotifier<GenerateState> {
  GenerateController(this._repository) : super(const GenerateState());
  final GenerateRepository _repository;
  Timer? _pollTimer;
  void setPrompt(String value) =>
      state = state.copyWith(prompt: value, clearError: true);
  void setAspectRatio(String value) =>
      state = state.copyWith(aspectRatio: value);
  void setCount(int value) => state = state.copyWith(count: value);
  void setPromptOptimizer(bool value) =>
      state = state.copyWith(promptOptimizer: value);

  Future<void> generate() async {
    final prompt = state.prompt.trim();
    if (prompt.isEmpty) {
      state = state.copyWith(errorMessage: '请输入画面描述');
      return;
    }
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final task = await _repository.create(
          prompt: prompt,
          aspectRatio: state.aspectRatio,
          count: state.count,
          promptOptimizer: state.promptOptimizer);
      state = state.copyWith(submitting: false, task: task);
      _schedulePoll(task.id, const Duration(seconds: 2));
    } catch (error) {
      state = state.copyWith(submitting: false, errorMessage: error.toString());
    }
  }

  void _schedulePoll(String taskId, Duration delay) {
    _pollTimer?.cancel();
    _pollTimer = Timer(delay, () => _poll(taskId, delay));
  }

  Future<void> _poll(String taskId, Duration previousDelay) async {
    try {
      final task = await _repository.get(taskId);
      state = state.copyWith(task: task, clearError: true);
      if (!task.isTerminal) {
        _schedulePoll(
            taskId,
            Duration(
                seconds: previousDelay.inSeconds < 5
                    ? previousDelay.inSeconds + 1
                    : 5));
      }
    } catch (error) {
      state = state.copyWith(errorMessage: error.toString());
      _schedulePoll(taskId, const Duration(seconds: 5));
    }
  }

  Future<void> cancel() async {
    final task = state.task;
    if (task == null || task.isTerminal) return;
    try {
      await _repository.cancel(task.id);
      _pollTimer?.cancel();
      state = state.copyWith(
          task: await _repository.get(task.id), clearError: true);
    } catch (error) {
      state = state.copyWith(errorMessage: error.toString());
    }
  }

  Future<void> retry() async {
    final task = state.task;
    if (task == null ||
        (task.status != 'FAILED' && task.status != 'CANCELED')) {
      return;
    }
    try {
      final replacement = await _repository.retry(task.id);
      state = state.copyWith(task: replacement, clearError: true);
      _schedulePoll(replacement.id, const Duration(seconds: 2));
    } catch (error) {
      state = state.copyWith(errorMessage: error.toString());
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
