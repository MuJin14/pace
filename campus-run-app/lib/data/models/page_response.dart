/// 后端分页返回结构，对应 `PageResponse<T>`：`{ total, page, size, list }`。
class PageResponse<T> {
  const PageResponse({
    required this.total,
    required this.page,
    required this.size,
    required this.list,
  });

  final int total;
  final int page;
  final int size;
  final List<T> list;

  factory PageResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) itemParser,
  ) {
    final rawList = json['list'] as List<dynamic>? ?? const [];
    return PageResponse<T>(
      total: (json['total'] as num).toInt(),
      page: (json['page'] as num).toInt(),
      size: (json['size'] as num).toInt(),
      list: rawList.map((e) => itemParser(e as Map<String, dynamic>)).toList(),
    );
  }
}
