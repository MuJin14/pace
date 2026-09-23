import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/activity_detail.dart';
import '../../../data/repositories/activity_repository.dart';

/// 单条运动记录详情。
final activityDetailProvider =
    FutureProvider.family<ActivityDetail, int>((ref, id) {
  return ref.read(activityRepositoryProvider).detail(id);
});
