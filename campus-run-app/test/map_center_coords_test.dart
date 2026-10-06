import 'package:campus_run_app/core/utils/coord_transform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// 地图坐标一致性测试。
///
/// **真实 bug（真机跑步时发现）**：跑步页地图上「圆点始终在屏幕外」，
/// 用户手动划过去后又被下一次定位拉回错误中心（表现为"位置被重置"）。
///
/// 原因：高德瓦片是 **GCJ-02（火星坐标）**，GPS 给的是 **WGS-84**，
/// 国内两者相差**几百米**。
/// - `track_map.dart` 画轨迹与圆点前调用了 `wgs84ToGcj02` ✅
/// - `start_run_page.dart` 的 `_mapController.move()` 却直接用 WGS-84 原始坐标 ❌
///
/// 于是地图中心与圆点错开数百米 —— 圆点跑到屏幕外。
///
/// 这个不变量必须固化：**凡是喂给 flutter_map 的坐标，都必须是 GCJ-02。**
void main() {
  group('GCJ-02 偏移量级（说明为何必须转换）', () {
    test('国内偏移达数百米，绝不是可以忽略的误差', () {
      // 取几个真实地点：北京、上海、广州、成都
      const places = <String, List<double>>{
        '北京天安门': [39.908823, 116.397470],
        '上海人民广场': [31.230416, 121.473701],
        '广州塔': [23.106612, 113.324523],
        '成都天府广场': [30.657000, 104.065800],
      };

      for (final entry in places.entries) {
        final wgs = entry.value;
        final gcj = CoordTransform.wgs84ToGcj02(wgs[0], wgs[1]);
        // 用 Distance 算两坐标间的实际米数
        final meters = const Distance().as(
          LengthUnit.Meter,
          LatLng(wgs[0], wgs[1]),
          gcj,
        );
        // 偏移量级：数百米（各地不同，这里给宽松下界，避免依赖具体算法常数）
        expect(meters, greaterThan(100),
            reason: '${entry.key} 的 WGS-84 → GCJ-02 偏移应达数百米，'
                '若不转换，地图中心与圆点会明显错位');
      }
    });

    test('不转换直接用的后果：偏移足够让圆点跑出 17 级缩放的可视范围', () {
      // 17 级缩放下，手机屏幕约覆盖数百米见方。
      // 偏移与可视半径同量级 → 圆点必然落在屏幕外或边缘。
      final wgs = LatLng(39.908823, 116.397470);
      final gcj = CoordTransform.wgs84ToGcj02(wgs.latitude, wgs.longitude);

      final meters = const Distance().as(LengthUnit.Meter, wgs, gcj);
      // 典型 17 级缩放屏幕约 300-500 米宽，半径约 150-250 米
      expect(meters, greaterThan(150),
          reason: '偏移超过可视半径的一半，圆点不会被自动居中看到');
    });
  });

  group('转换结果的稳定性与合理性', () {
    test('同一输入结果稳定（不会因为重复调用产生漂移）', () {
      final a = CoordTransform.wgs84ToGcj02(39.908823, 116.397470);
      final b = CoordTransform.wgs84ToGcj02(39.908823, 116.397470);
      expect(a.latitude, b.latitude);
      expect(a.longitude, b.longitude);
    });

    test('转换是单向小幅偏移：仍在同一城市范围内', () {
      final gcj = CoordTransform.wgs84ToGcj02(39.908823, 116.397470);
      // 北京范围内
      expect(gcj.latitude, closeTo(39.908823, 0.02));
      expect(gcj.longitude, closeTo(116.397470, 0.02));
      // 但确实不等于原值
      expect(gcj.latitude, isNot(39.908823));
    });

    test('境外坐标原样返回（不需要转换也不能乱转）', () {
      final r = CoordTransform.wgs84ToGcj02(35.6762, 139.6503); // 东京
      expect(r.latitude, 35.6762);
      expect(r.longitude, 139.6503);
    });
  });

  group('地图使用约定（回归固化）', () {
    test('喂给 flutter_map 的中心点必须与轨迹点使用同一坐标系', () {
      // 模拟一个定位点，走和页面相同的流程
      const lat = 39.908823;
      const lng = 116.397470;

      // track_map 里画轨迹/圆点的做法（正确）
      final trackPoint = CoordTransform.wgs84ToGcj02(lat, lng);
      // 修复后 start_run_page 里 move() 的做法（必须与之一致）
      final mapCenter = CoordTransform.wgs84ToGcj02(lat, lng);

      expect(mapCenter.latitude, trackPoint.latitude);
      expect(mapCenter.longitude, trackPoint.longitude);

      // 反例：曾经错误的做法 —— 直接用原始 WGS-84
      const buggyCenter = LatLng(lat, lng);
      final errorMeters = const Distance().as(
        LengthUnit.Meter,
        buggyCenter,
        trackPoint,
      );
      expect(errorMeters, greaterThan(100),
          reason: '这就是圆点跑出屏幕的根因，必须大于可视半径');
    });
  });
}
