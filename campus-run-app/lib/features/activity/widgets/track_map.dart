import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/coord_transform.dart';
import '../../../core/widgets/app_empty_hint.dart';
import '../../../data/models/track_point.dart';

/// 通用轨迹地图：双层折线 + 起终点标记，只读浏览（禁旋转，允许缩放/拖动）。
///
/// [live] 为 false 时（回放）自动 fitBounds 到轨迹范围并标记「起/终」；
/// [live] 为 true 时（实时）跟随最后一点、显示当前位置圆点，父级通过
/// [controller] 与 [onMapReady] 控制相机。
/// 无轨迹时展示区块内空态：召唤语 [emptyText] + 可选动作
/// （[emptyActionLabel] + [onEmptyAction]）。
class TrackMap extends StatelessWidget {
  const TrackMap({
    super.key,
    required this.track,
    required this.color,
    this.live = false,
    this.controller,
    this.onMapReady,
    this.emptyText = '暂无轨迹数据',
    this.emptyDescription,
    this.emptyActionLabel,
    this.onEmptyAction,
    this.loading = false,
  });

  final List<TrackPoint> track;
  final Color color;
  final bool live;
  final MapController? controller;
  final VoidCallback? onMapReady;
  final String emptyText;
  final String? emptyDescription;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final bool loading;

  static const InteractionOptions _readOnly = InteractionOptions(
    flags: InteractiveFlag.drag |
        InteractiveFlag.flingAnimation |
        InteractiveFlag.pinchZoom |
        InteractiveFlag.doubleTapZoom |
        InteractiveFlag.scrollWheelZoom,
  );

  @override
  Widget build(BuildContext context) {
    if (track.isEmpty) {
      return Container(
        color: AppColors.surface,
        alignment: Alignment.center,
        child: loading
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: color),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    emptyText,
                    style: const TextStyle(
                      fontSize: AppFontSize.body,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              )
            : AppEmptyHint(
                title: emptyText,
                description: emptyDescription,
                actionLabel: emptyActionLabel,
                onAction: onEmptyAction,
                padding: const EdgeInsets.all(AppSpacing.md),
                iconGap: AppSpacing.sm,
                descriptionGap: AppSpacing.sm,
                actionGap: AppSpacing.md,
              ),
      );
    }

    final points = track
        .map((p) => CoordTransform.wgs84ToGcj02(p.latitude, p.longitude))
        .toList();
    final first = points.first;
    final last = points.last;

    final MapOptions options;
    if (live) {
      options = MapOptions(
        initialCenter: last,
        initialZoom: 17,
        onMapReady: onMapReady,
        interactionOptions: _readOnly,
      );
    } else if (points.length >= 2) {
      options = MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(AppSpacing.xxl),
        ),
        interactionOptions: _readOnly,
      );
    } else {
      options = MapOptions(
        initialCenter: last,
        initialZoom: 17,
        interactionOptions: _readOnly,
      );
    }

    return FlutterMap(
      mapController: controller,
      options: options,
      children: [
        // 高德瓦片（开发临时方案，上线前需换正式授权渠道）。
        TileLayer(
          urlTemplate:
              'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
          subdomains: const ['1', '2', '3', '4'],
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: points,
              strokeWidth: 8,
              color: color.withValues(alpha: 0.2),
            ),
            Polyline(points: points, strokeWidth: 4, color: color),
          ],
        ),
        MarkerLayer(
          markers: [
            _endpointMarker(first, AppColors.success, '起'),
            if (live)
              _currentMarker(last)
            else
              _endpointMarker(last, AppColors.danger, '终'),
          ],
        ),
      ],
    );
  }

  Marker _endpointMarker(LatLng point, Color dotColor, String label) {
    return Marker(
      point: point,
      width: 44,
      height: 20,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _dot(dotColor),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: const TextStyle(
              fontSize: AppFontSize.caption,
              fontWeight: AppFontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Marker _currentMarker(LatLng point) {
    return Marker(
      point: point,
      width: 20,
      height: 20,
      child: _dot(color),
    );
  }

  Widget _dot(Color dotColor) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: dotColor,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.onPrimary, width: 3),
      ),
    );
  }
}
