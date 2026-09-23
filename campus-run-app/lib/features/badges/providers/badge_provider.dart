import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/badge.dart';
import '../../../data/models/user_badge.dart';
import '../../../data/repositories/badge_repository.dart';

final badgeAllProvider = FutureProvider<List<Badge>>((ref) {
  return ref.read(badgeRepositoryProvider).all();
});

final badgeMineProvider = FutureProvider<List<UserBadge>>((ref) {
  return ref.read(badgeRepositoryProvider).mine();
});
