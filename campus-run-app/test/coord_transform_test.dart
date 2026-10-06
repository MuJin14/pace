import 'package:campus_run_app/core/utils/coord_transform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// `CoordTransform`（WGS-84 → GCJ-02）单元测试。
///
/// 参考值取自公开实现 eviltransform / coordtransform 的标准测试向量。
void main() {
  group('CoordTransform.wgs84ToGcj02 境外与边界', () {
    test('中国境外坐标原样返回', () {
      const overseas = <List<double>>[
        [0, 0], // 几内亚湾
        [-33.8688, 151.2093], // 悉尼
        [40.7128, -74.0060], // 纽约
        [35.6762, 139.6503], // 东京
      ];
      for (final p in overseas) {
        final r = CoordTransform.wgs84ToGcj02(p[0], p[1]);
        expect(r.latitude, p[0]);
        expect(r.longitude, p[1]);
      }
    });

    test('经度 < 72.004 或 > 137.8347 视为境外', () {
      expect(CoordTransform.wgs84ToGcj02(40.0, 71.999).longitude, 71.999);
      expect(CoordTransform.wgs84ToGcj02(40.0, 137.8348).longitude, 137.8348);
    });

    test('纬度 < 0.8293 或 > 55.8271 视为境外', () {
      expect(CoordTransform.wgs84ToGcj02(0.8292, 100.0).latitude, 0.8292);
      expect(CoordTransform.wgs84ToGcj02(55.8272, 100.0).latitude, 55.8272);
    });

    test('边界值（含等于）按境内处理，会产生偏移', () {
      final lower = CoordTransform.wgs84ToGcj02(0.8293, 72.004);
      expect(lower.latitude, isNot(0.8293));
      expect(lower.longitude, isNot(72.004));

      final upper = CoordTransform.wgs84ToGcj02(55.8271, 137.8347);
      expect(upper.latitude, isNot(55.8271));
      expect(upper.longitude, isNot(137.8347));
    });
  });

  group('CoordTransform.wgs84ToGcj02 境内偏移', () {
    test('返回 LatLng，且同一输入结果稳定', () {
      final a = CoordTransform.wgs84ToGcj02(39.908823, 116.397470);
      final b = CoordTransform.wgs84ToGcj02(39.908823, 116.397470);
      expect(a, isA<LatLng>());
      expect(a.latitude, b.latitude);
      expect(a.longitude, b.longitude);
    });

    test('标准测试向量（eviltransform）：上海坐标与公开参考值一致', () {
      final r = CoordTransform.wgs84ToGcj02(31.1774276, 121.5272106);
      expect(r.latitude, closeTo(31.17530398364597, 1e-9));
      expect(r.longitude, closeTo(121.531541859215, 1e-9));
    });

    test('北京坐标偏移量在 300~700 米量级（0.001~0.01 度）', () {
      const lat = 39.908823;
      const lng = 116.397470;
      final r = CoordTransform.wgs84ToGcj02(lat, lng);
      final dLat = (r.latitude - lat).abs();
      final dLng = (r.longitude - lng).abs();
      expect(dLat, greaterThan(0.0005));
      expect(dLat, lessThan(0.01));
      expect(dLng, greaterThan(0.0005));
      expect(dLng, lessThan(0.01));
    });

    test('广州坐标偏移与公开参考值一致', () {
      final r = CoordTransform.wgs84ToGcj02(22.530501, 113.927865);
      expect(r.latitude, closeTo(22.52746201161666, 1e-9));
      expect(r.longitude, closeTo(113.93272721487466, 1e-9));
    });

    test('境外坐标不做二次偏移（不会因为调用两次而继续漂移）', () {
      final once = CoordTransform.wgs84ToGcj02(-33.8688, 151.2093);
      final twice = CoordTransform.wgs84ToGcj02(once.latitude, once.longitude);
      expect(twice.latitude, once.latitude);
      expect(twice.longitude, once.longitude);
    });
  });
}
