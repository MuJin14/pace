import 'package:campus_run_app/data/models/activity_detail.dart';
import 'package:campus_run_app/data/models/activity_summary.dart';
import 'package:campus_run_app/data/models/auth_result.dart';
import 'package:campus_run_app/data/models/badge.dart';
import 'package:campus_run_app/data/models/chat_message.dart';
import 'package:campus_run_app/data/models/friend_item.dart';
import 'package:campus_run_app/data/models/friend_request.dart';
import 'package:campus_run_app/data/models/goal.dart';
import 'package:campus_run_app/data/models/leaderboard_entry.dart';
import 'package:campus_run_app/data/models/my_rank.dart';
import 'package:campus_run_app/data/models/page_response.dart';
import 'package:campus_run_app/data/models/track_point.dart';
import 'package:campus_run_app/data/models/user.dart';
import 'package:campus_run_app/data/models/user_badge.dart';
import 'package:campus_run_app/data/models/user_brief.dart';
import 'package:flutter_test/flutter_test.dart';

/// 数据模型单元测试：fromJson 字段映射、缺失字段容错、非法类型、边界值。
void main() {
  group('ActivitySummary', () {
    const full = <String, dynamic>{
      'activityId': 12,
      'type': 1,
      'mode': 2,
      'invalid': 0,
      'distanceMeters': 5230,
      'durationSeconds': 2530,
      'avgSpeed': 7.4,
      'avgPace': 390,
      'startTime': '2026-09-22 20:00:00',
      'endTime': '2026-09-22 20:42:10',
      'createdAt': '2026-09-22 20:42:11',
    };

    test('完整字段映射', () {
      final m = ActivitySummary.fromJson(full);
      expect(m.activityId, 12);
      expect(m.type, 1);
      expect(m.mode, 2);
      expect(m.invalid, 0);
      expect(m.distanceMeters, 5230);
      expect(m.durationSeconds, 2530);
      expect(m.avgSpeed, 7.4);
      expect(m.avgPace, 390);
      expect(m.startTime, '2026-09-22 20:00:00');
      expect(m.endTime, '2026-09-22 20:42:10');
      expect(m.createdAt, '2026-09-22 20:42:11');
      expect(m.isRunning, isTrue);
    });

    test('type=2 为骑行', () {
      expect(ActivitySummary.fromJson({...full, 'type': 2}).isRunning, isFalse);
    });

    test('可选字段缺失时为 null', () {
      const minimal = <String, dynamic>{
        'activityId': 1,
        'type': 1,
        'distanceMeters': 0,
        'durationSeconds': 0,
        'startTime': '2026-09-22 20:00:00',
        'endTime': '2026-09-22 20:00:01',
        'createdAt': '2026-09-22 20:00:01',
      };
      final m = ActivitySummary.fromJson(minimal);
      expect(m.mode, isNull);
      expect(m.invalid, isNull);
      expect(m.avgSpeed, isNull);
      expect(m.avgPace, isNull);
      expect(m.distanceMeters, 0);
      expect(m.durationSeconds, 0);
    });

    test('数值以 double 下发时 toInt 取整', () {
      final m = ActivitySummary.fromJson({
        ...full,
        'activityId': 12.0,
        'distanceMeters': 5230.0,
        'avgPace': 390.0,
      });
      expect(m.activityId, 12);
      expect(m.distanceMeters, 5230);
      expect(m.avgPace, 390);
    });

    test('缺失必填字段抛 TypeError', () {
      expect(
        () => ActivitySummary.fromJson(
            Map<String, dynamic>.from(full)..remove('activityId')),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => ActivitySummary.fromJson(
            Map<String, dynamic>.from(full)..remove('distanceMeters')),
        throwsA(isA<TypeError>()),
      );
    });

    test('字段类型不合法抛 TypeError', () {
      expect(
        () => ActivitySummary.fromJson({...full, 'distanceMeters': '5230'}),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => ActivitySummary.fromJson({...full, 'startTime': 20260922}),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('ActivityDetail', () {
    const json = <String, dynamic>{
      'activityId': 7,
      'type': 1,
      'mode': 1,
      'invalid': 0,
      'distanceMeters': 1000,
      'durationSeconds': 300,
      'avgSpeed': 12.0,
      'avgPace': 300,
      'calories': 320.5,
      'startTime': '2026-09-22 20:00:00',
      'endTime': '2026-09-22 20:05:00',
      'createdAt': '2026-09-22 20:05:01',
      'track': [
        {'latitude': 39.9, 'longitude': 116.4, 'timestamp': 1, 'accuracy': 5.0},
        {'latitude': 39.91, 'longitude': 116.41, 'timestamp': 2},
      ],
    };

    test('完整字段与轨迹解析', () {
      final d = ActivityDetail.fromJson(json);
      expect(d.activityId, 7);
      expect(d.calories, 320.5);
      expect(d.track.length, 2);
      expect(d.track.first.latitude, 39.9);
      expect(d.track.first.accuracy, 5.0);
      expect(d.track[1].accuracy, isNull);
      expect(d.track[1].timestamp, 2);
      expect(d.isRunning, isTrue);
    });

    test('track 缺失 / 为 null / 为空数组都得到空轨迹', () {
      expect(ActivityDetail.fromJson({...json}..remove('track')).track, isEmpty);
      expect(ActivityDetail.fromJson({...json, 'track': null}).track, isEmpty);
      expect(
        ActivityDetail.fromJson({...json, 'track': <dynamic>[]}).track,
        isEmpty,
      );
    });

    test('可选字段缺失时为 null', () {
      final d = ActivityDetail.fromJson({
        ...json,
        'calories': null,
        'avgSpeed': null,
        'avgPace': null,
      });
      expect(d.calories, isNull);
      expect(d.avgSpeed, isNull);
      expect(d.avgPace, isNull);
    });

    test('缺失必填字段抛 TypeError', () {
      expect(
        () => ActivityDetail.fromJson({...json}..remove('durationSeconds')),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('Goal', () {
    test('fromJson 完整字段映射', () {
      final g = Goal.fromJson(const {
        'id': 3,
        'periodType': 'weekly',
        'targetDistanceMeters': 10000,
        'currentDistanceMeters': 4000,
        'startDate': '2026-09-21',
        'endDate': '2026-09-27',
        'status': 0,
        'createdAt': '2026-09-21 08:00:00',
      });
      expect(g.id, 3);
      expect(g.periodType, 'weekly');
      expect(g.targetDistanceMeters, 10000);
      expect(g.currentDistanceMeters, 4000);
      expect(g.startDate, '2026-09-21');
      expect(g.endDate, '2026-09-27');
      expect(g.status, 0);
      expect(g.createdAt, '2026-09-21 08:00:00');
      expect(g.isActive, isTrue);
      expect(g.progress, 0.4);
    });

    test('status / 日期 / createdAt 缺失时容错', () {
      final g = Goal.fromJson(const {
        'id': 1,
        'periodType': 'custom',
        'targetDistanceMeters': 5000,
        'currentDistanceMeters': 0,
      });
      expect(g.status, 0);
      expect(g.startDate, isNull);
      expect(g.endDate, isNull);
      expect(g.createdAt, isNull);
      expect(g.isActive, isTrue);
    });

    test('progress 在 0~1 之间截断', () {
      expect(_goal(target: 1000, current: 500).progress, 0.5);
      expect(_goal(target: 1000, current: 1500).progress, 1.0);
      expect(_goal(target: 1000, current: -5).progress, 0.0);
      expect(_goal(target: 1000, current: 0).progress, 0.0);
      expect(_goal(target: 1000, current: 1000).progress, 1.0);
    });

    test('目标距离为 0 或负数时 progress 为 0（不除零）', () {
      expect(_goal(target: 0, current: 100).progress, 0.0);
      expect(_goal(target: -100, current: 100).progress, 0.0);
    });

    test('statusLabel 覆盖全部状态与未知值', () {
      expect(_goal(status: 0).statusLabel, '进行中');
      expect(_goal(status: 1).statusLabel, '已完成');
      expect(_goal(status: 2).statusLabel, '已过期');
      expect(_goal(status: 3).statusLabel, '已取消');
      expect(_goal(status: 9).statusLabel, '进行中');
      expect(_goal(status: 1).isActive, isFalse);
      expect(_goal(status: 2).isActive, isFalse);
      expect(_goal(status: 3).isActive, isFalse);
    });
  });

  group('ChatMessage', () {
    const json = <String, dynamic>{
      'messageId': 88,
      'senderId': 1,
      'receiverId': 2,
      'content': 'hi',
      'type': 1,
      'delivered': 1,
      'readAt': 1695456000000,
      'timestamp': 1695455000000,
    };

    test('readAt 为毫秒时间戳', () {
      final m = ChatMessage.fromJson(json);
      expect(m.messageId, 88);
      expect(m.senderId, 1);
      expect(m.receiverId, 2);
      expect(m.content, 'hi');
      expect(m.readAt, 1695456000000);
      expect(m.timestamp, 1695455000000);
      expect(m.failed, isFalse);
    });

    test('readAt 缺失或为 null 表示未读', () {
      expect(ChatMessage.fromJson({...json}..remove('readAt')).readAt, isNull);
      expect(ChatMessage.fromJson({...json, 'readAt': null}).readAt, isNull);
    });

    test('type / delivered 缺失时取默认值', () {
      final m = ChatMessage.fromJson({
        'messageId': 1,
        'senderId': 1,
        'receiverId': 2,
        'content': '',
        'timestamp': 0,
      });
      expect(m.type, 1);
      expect(m.delivered, 0);
      expect(m.content, '');
      expect(m.readAt, isNull);
    });

    test('copyWith 只改指定字段，其余保持不变', () {
      final m = ChatMessage.fromJson(json);
      final updated = m.copyWith(messageId: 99, readAt: 1695456001000);
      expect(updated.messageId, 99);
      expect(updated.readAt, 1695456001000);
      expect(updated.senderId, m.senderId);
      expect(updated.receiverId, m.receiverId);
      expect(updated.content, m.content);
      expect(updated.type, m.type);
      expect(updated.delivered, m.delivered);
      expect(updated.timestamp, m.timestamp);
      expect(updated.failed, isFalse);
    });

    test('copyWith 可把 failed 标记为 true（乐观发送失败）', () {
      expect(ChatMessage.fromJson(json).copyWith(failed: true).failed, isTrue);
      expect(ChatMessage.fromJson(json).copyWith().readAt, 1695456000000);
    });

    test('缺失必填字段抛 TypeError', () {
      expect(
        () => ChatMessage.fromJson({...json}..remove('timestamp')),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('FriendItem / FriendRequest', () {
    test('FriendItem 完整与可选字段缺失', () {
      final f = FriendItem.fromJson(const {
        'friendshipId': 5,
        'userId': 2,
        'uniqueId': 'CR-00000002',
        'nickname': '小李',
        'avatarUrl': 'https://example.com/a.png',
        'createdAt': '2026-09-22 20:00:00',
      });
      expect(f.friendshipId, 5);
      expect(f.userId, 2);
      expect(f.uniqueId, 'CR-00000002');
      expect(f.nickname, '小李');
      expect(f.avatarUrl, 'https://example.com/a.png');

      final minimal = FriendItem.fromJson(const {
        'friendshipId': 5,
        'userId': 2,
        'uniqueId': 'CR-00000002',
        'nickname': '小李',
      });
      expect(minimal.avatarUrl, isNull);
      expect(minimal.createdAt, isNull);
    });

    test('FriendRequest 完整与可选字段缺失', () {
      final r = FriendRequest.fromJson(const {
        'requestId': 9,
        'userId': 3,
        'uniqueId': 'CR-00000003',
        'nickname': '小王',
        'avatarUrl': null,
        'createdAt': '2026-09-22 20:00:00',
      });
      expect(r.requestId, 9);
      expect(r.avatarUrl, isNull);
      expect(r.createdAt, '2026-09-22 20:00:00');
    });
  });

  group('LeaderboardEntry / MyRank', () {
    test('LeaderboardEntry 映射与缺失头像', () {
      final e = LeaderboardEntry.fromJson(const {
        'rank': 1,
        'userId': 2,
        'uniqueId': 'CR-00000002',
        'nickname': '小李',
        'distanceMeters': 12345,
      });
      expect(e.rank, 1);
      expect(e.userId, 2);
      expect(e.uniqueId, 'CR-00000002');
      expect(e.nickname, '小李');
      expect(e.avatarUrl, isNull);
      expect(e.distanceMeters, 12345);
    });

    test('MyRank：rank 可为 null（未上榜）', () {
      final r = MyRank.fromJson(const {'rank': null, 'distanceMeters': 0, 'total': 0});
      expect(r.rank, isNull);
      expect(r.distanceMeters, 0);
      expect(r.total, 0);
    });

    test('MyRank：rank 缺失视为未上榜，距离/总数缺失取 0', () {
      final r = MyRank.fromJson(const <String, dynamic>{});
      expect(r.rank, isNull);
      expect(r.distanceMeters, 0);
      expect(r.total, 0);
    });
  });

  group('PageResponse', () {
    test('list 正常解析（元素解析器注入）', () {
      final page = PageResponse<TrackPoint>.fromJson(
        const {
          'total': 2,
          'page': 1,
          'size': 20,
          'list': [
            {'latitude': 39.9, 'longitude': 116.4, 'timestamp': 1},
            {'latitude': 39.91, 'longitude': 116.41, 'timestamp': 2},
          ],
        },
        TrackPoint.fromJson,
      );
      expect(page.total, 2);
      expect(page.page, 1);
      expect(page.size, 20);
      expect(page.list.length, 2);
      expect(page.list[1].longitude, 116.41);
    });

    test('list 缺失或为 null 时得到空列表', () {
      final page = PageResponse<TrackPoint>.fromJson(
        const {'total': 0, 'page': 1, 'size': 20},
        TrackPoint.fromJson,
      );
      expect(page.list, isEmpty);
      final nullList = PageResponse<TrackPoint>.fromJson(
        const {'total': 0, 'page': 1, 'size': 20, 'list': null},
        TrackPoint.fromJson,
      );
      expect(nullList.list, isEmpty);
    });

    test('分页元数据缺失时抛 TypeError', () {
      expect(
        () => PageResponse<TrackPoint>.fromJson(
            const {'page': 1, 'size': 20}, TrackPoint.fromJson),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('TrackPoint', () {
    test('fromJson 完整与缺失 accuracy', () {
      final p = TrackPoint.fromJson(
          const {'latitude': 39.9, 'longitude': 116.4, 'timestamp': 1});
      expect(p.latitude, 39.9);
      expect(p.longitude, 116.4);
      expect(p.timestamp, 1);
      expect(p.accuracy, isNull);
    });

    test('toJson 保留 null accuracy 键', () {
      const p = TrackPoint(latitude: 1.5, longitude: 2.5, timestamp: 3);
      expect(p.toJson(), {
        'latitude': 1.5,
        'longitude': 2.5,
        'timestamp': 3,
        'accuracy': null,
      });
    });

    test('fromJson(toJson()) 往返一致', () {
      const origin = TrackPoint(
        latitude: 39.908823,
        longitude: 116.397470,
        timestamp: 1695456000000,
        accuracy: 5.5,
      );
      final back = TrackPoint.fromJson(origin.toJson());
      expect(back.latitude, origin.latitude);
      expect(back.longitude, origin.longitude);
      expect(back.timestamp, origin.timestamp);
      expect(back.accuracy, origin.accuracy);
    });

    test('整数经纬度也能解析为 double', () {
      final p = TrackPoint.fromJson(
          const {'latitude': 39, 'longitude': 116, 'timestamp': 1});
      expect(p.latitude, 39.0);
      expect(p.longitude, 116.0);
    });
  });

  group('Badge / UserBadge', () {
    test('Badge 完整字段与 earned=true', () {
      final b = Badge.fromJson(const {
        'id': 1,
        'code': 'FIRST_RUN',
        'name': '首次奔跑',
        'icon': 'run',
        'description': '完成第一次跑步',
        'ruleType': 'COUNT',
        'ruleValue': 1,
        'earned': true,
        'awardedAt': '2026-09-22 20:00:00',
      });
      expect(b.id, 1);
      expect(b.code, 'FIRST_RUN');
      expect(b.name, '首次奔跑');
      expect(b.icon, 'run');
      expect(b.description, '完成第一次跑步');
      expect(b.ruleType, 'COUNT');
      expect(b.ruleValue, 1);
      expect(b.earned, isTrue);
      expect(b.awardedAt, '2026-09-22 20:00:00');
    });

    test('Badge 可选字段缺失：earned 默认 false', () {
      final b = Badge.fromJson(
          const {'id': 2, 'code': 'X', 'name': '未知'});
      expect(b.earned, isFalse);
      expect(b.icon, isNull);
      expect(b.description, isNull);
      expect(b.ruleType, isNull);
      expect(b.ruleValue, isNull);
      expect(b.awardedAt, isNull);
    });

    test('Badge.earned 非 bool 类型抛 TypeError', () {
      expect(
        () => Badge.fromJson(
            const {'id': 2, 'code': 'X', 'name': '未知', 'earned': 1}),
        throwsA(isA<TypeError>()),
      );
    });

    test('UserBadge 映射', () {
      final b = UserBadge.fromJson(const {
        'badgeId': 4,
        'code': 'TEN_KM',
        'name': '十公里',
        'awardedAt': '2026-09-22 20:00:00',
      });
      expect(b.badgeId, 4);
      expect(b.code, 'TEN_KM');
      expect(b.name, '十公里');
      expect(b.icon, isNull);
      expect(b.description, isNull);
      expect(b.awardedAt, '2026-09-22 20:00:00');
    });
  });

  group('User / UserBrief / AuthResult', () {
    const flatUser = <String, dynamic>{
      'userId': 6,
      'uniqueId': 'CR-00000006',
      'nickname': '小张',
      'phone': '13800138000',
      'avatarUrl': null,
      'createdAt': '2026-09-01 10:00:00',
    };

    test('User 映射与可选字段缺失', () {
      final u = User.fromJson(flatUser);
      expect(u.userId, 6);
      expect(u.uniqueId, 'CR-00000006');
      expect(u.nickname, '小张');
      expect(u.phone, '13800138000');
      expect(u.avatarUrl, isNull);
      final minimal = User.fromJson(const {
        'userId': 6,
        'uniqueId': 'CR-00000006',
        'nickname': '小张',
        'phone': '13800138000',
      });
      expect(minimal.createdAt, isNull);
    });

    test('UserBrief 只取搜索结果需要的字段', () {
      final b = UserBrief.fromJson(const {
        'userId': 7,
        'uniqueId': 'CR-00000007',
        'nickname': '小赵',
        'avatarUrl': 'https://example.com/b.png',
      });
      expect(b.userId, 7);
      expect(b.uniqueId, 'CR-00000007');
      expect(b.avatarUrl, 'https://example.com/b.png');
    });

    test('AuthResult 从平铺的 data 中同时取 token 与用户', () {
      final r = AuthResult.fromJson({...flatUser, 'token': 'jwt-token'});
      expect(r.token, 'jwt-token');
      expect(r.user.userId, 6);
      expect(r.user.uniqueId, 'CR-00000006');
      expect(r.user.nickname, '小张');
    });

    test('AuthResult 缺 token 抛 TypeError', () {
      expect(
        () => AuthResult.fromJson(flatUser),
        throwsA(isA<TypeError>()),
      );
    });
  });
}

Goal _goal({
  int target = 1000,
  int current = 0,
  int status = 0,
}) =>
    Goal(
      id: 1,
      periodType: 'weekly',
      targetDistanceMeters: target,
      currentDistanceMeters: current,
      status: status,
    );
