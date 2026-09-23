import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/goal.dart';
import '../../../data/repositories/goal_repository.dart';

final goalListProvider = FutureProvider<List<Goal>>((ref) {
  return ref.read(goalRepositoryProvider).list();
});
