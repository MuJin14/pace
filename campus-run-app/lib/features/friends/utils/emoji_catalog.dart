/// 内置 emoji 与表情包目录。
///
/// **为什么不引第三方 emoji 库**：
/// 1. 常用 emoji 就是那么几十个，内置一个列表比拉一个几 MB 的包划算；
/// 2. 多数 emoji 包会带整套 Unicode 数据 + 搜索 + 皮肤色，功能远超需求；
/// 3. 包体每多 1MB，安装与更新成本都会上升。
///
/// emoji 走**文本消息**（它们是 Unicode 字符），
/// 只有下方 [stickerAssets] 里的贴图才走 `type=3` 的表情包消息。
library;

/// 常用 emoji，按语义分组（分组让面板更容易扫视，而不是一坨网格）。
const Map<String, List<String>> emojiGroups = {
  '常用': ['😀', '😄', '😁', '😊', '🙂', '😉', '😍', '🥰', '😘', '😜', '🤔', '😅'],
  '情绪': ['😂', '🤣', '😭', '😢', '😡', '😱', '😴', '🥱', '😷', '🤒', '😎', '🥳'],
  '手势': ['👍', '👎', '👏', '🙏', '💪', '✌️', '🤝', '👌', '🫡', '🤙', '👋', '🖐️'],
  '运动': ['🏃', '🏃‍♂️', '🏃‍♀️', '🚴', '🚴‍♂️', '🏅', '🥇', '🥈', '🥉', '🏆', '⚽', '🏀'],
  '其他': ['❤️', '🔥', '✨', '🎉', '🎊', '💯', '⭐', '🌈', '☀️', '🌙', '🍀', '🎯'],
};

/// 内置表情包贴图（相对 `assets/stickers/` 的文件名）。
///
/// ⚠️ 这些文件必须真实存在于 `assets/stickers/` 并在 pubspec 的 assets 中声明，
/// 否则渲染时会抛 `Unable to load asset`。
/// 项目当前**未附带贴图文件**，因此这个列表默认为空 ——
/// 面板会自动隐藏「表情包」分组，而不是显示一堆加载失败的破图。
///
/// 要启用：把 PNG/GIF 放进 `campus-run-app/assets/stickers/`，
/// 在 pubspec.yaml 的 `flutter: assets:` 下加 `- assets/stickers/`，
/// 然后在这里填入文件名即可（无需改 UI 代码）。
const List<String> stickerAssets = <String>[];

/// 是否已配置贴图（用于决定面板是否显示贴图分组）。
bool get hasStickers => stickerAssets.isNotEmpty;
