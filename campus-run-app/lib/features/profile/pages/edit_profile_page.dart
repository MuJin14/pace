import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../auth/providers/auth_provider.dart';

/// 编辑个人资料：昵称 + 头像 + 性别/年龄及其可见性。
///
/// 只能改昵称、头像、性别、年龄：手机号是账号标识（换绑要走短信验证），
/// 专属 ID 是别人加你的凭据（改了会让好友找不到你），都不在这里。
///
/// **可见性默认关闭**：新用户填了性别/年龄也不会自动公开，
/// 必须自己打开开关 —— 这是隐私默认安全的原则，不是「顺手帮用户公开」。
class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  late final TextEditingController _nicknameController;
  late final TextEditingController _avatarController;
  late final TextEditingController _ageController;

  /// 性别：0=保密 1=男 2=女（与后端一致）。
  int _gender = 0;
  bool _genderPublic = false;
  bool _agePublic = false;

  bool _submitting = false;
  bool _uploading = false;
  String? _nicknameError;
  String? _ageError;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).value;
    _nicknameController = TextEditingController(text: user?.nickname ?? '');
    _avatarController = TextEditingController(text: user?.avatarUrl ?? '');
    _ageController =
        TextEditingController(text: user?.age == null ? '' : '${user!.age}');
    _gender = user?.gender ?? 0;
    _genderPublic = user?.genderPublic ?? false;
    _agePublic = user?.agePublic ?? false;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _avatarController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  /// 从相册选一张图并上传，成功后把 URL 回填到输入框。
  ///
  /// 只回填、不直接保存：用户可以改主意（换一张/不换），
  /// 上传成功但名字改错了也不会连带把头像写进资料。
  Future<void> _pickAndUpload() async {
    if (_uploading) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null) return; // 用户取消

      setState(() => _uploading = true);
      final filename = picked.name.isEmpty ? 'avatar.jpg' : picked.name;
      // 读字节再上传：Web 上 XFile.path 是 blob URL，MultipartFile.fromFile 不可用
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      final url = await ref
          .read(authRepositoryProvider)
          .uploadAvatar(bytes, filename);
      if (!mounted) return;
      setState(() => _avatarController.text = url);
      messenger.showSnackBar(const SnackBar(content: Text('图片已上传，别忘了点「保存」')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '上传失败，请重试')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  bool _validate() {
    final nickname = _nicknameController.text.trim();
    String? nicknameError;
    if (nickname.isEmpty) {
      nicknameError = '昵称不能为空';
    } else if (nickname.length > 20) {
      nicknameError = '昵称最多 20 个字';
    }

    // 年龄可以留空（= 不填）；填了就必须是合法整数。
    // 用 int.tryParse 而不是 double：年龄没有小数。
    String? ageError;
    final ageText = _ageController.text.trim();
    if (ageText.isNotEmpty) {
      final parsed = int.tryParse(ageText);
      if (parsed == null) {
        ageError = '年龄需要是整数';
      } else if (parsed < 1 || parsed > 120) {
        ageError = '年龄需在 1-120 之间';
      }
    }

    setState(() {
      _nicknameError = nicknameError;
      _ageError = ageError;
    });
    return nicknameError == null && ageError == null;
  }

  Future<void> _submit() async {
    if (_submitting || !_validate()) return;
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final ageText = _ageController.text.trim();
      await ref.read(authProvider.notifier).updateProfile(
            nickname: _nicknameController.text.trim(),
            // 空串 = 清空头像，回到昵称首字兜底
            avatarUrl: _avatarController.text.trim(),
            gender: _gender,
            // 年龄留空 → 传 null = 不修改（PATCH 语义）。
            // 不传 0：0 是非法年龄，会被后端校验拒绝。
            age: ageText.isEmpty ? null : int.tryParse(ageText),
            genderPublic: _genderPublic,
            agePublic: _agePublic,
          );
      messenger.showSnackBar(const SnackBar(content: Text('资料已更新')));
      navigator.pop(true);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '保存失败，请稍后重试')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).value;
    final previewAvatar = _avatarController.text.trim();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('编辑资料')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageWide,
          AppSpacing.md,
          AppSpacing.pageWide,
          AppSpacing.xl,
        ),
        children: [
          // 实时预览：改头像地址立刻能看到效果，避免保存后才发现不对
          Center(
            child: Column(
              children: [
                Stack(
                  children: [
                    UserAvatar(
                      nickname: _nicknameController.text.trim().isEmpty
                          ? (user?.nickname ?? '')
                          : _nicknameController.text.trim(),
                      avatarUrl: previewAvatar.isEmpty ? null : previewAvatar,
                      size: 88,
                    ),
                    // 点右上角相机图标上传，比让用户去找输入框更直观
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Material(
                        color: AppColors.primary,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _uploading ? null : _pickAndUpload,
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            child: _uploading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.onPrimary,
                                    ),
                                  )
                                : const Icon(
                                    Icons.photo_camera,
                                    size: 16,
                                    color: AppColors.onPrimary,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton.icon(
                  onPressed: _uploading ? null : _pickAndUpload,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: Text(_uploading ? '上传中…' : '从相册选择'),
                ),
                Text(
                  Formatters.uniqueId(user?.uniqueId ?? ''),
                  style: const TextStyle(
                    fontSize: AppFontSize.caption,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '昵称',
                  style: TextStyle(
                    fontSize: AppFontSize.body,
                    fontWeight: AppFontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _nicknameController,
                  maxLength: 20,
                  onChanged: (_) => setState(() => _nicknameError = null),
                  decoration: InputDecoration(
                    hintText: '1-20 个字',
                    errorText: _nicknameError,
                    counterText: '',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  '头像图片地址',
                  style: TextStyle(
                    fontSize: AppFontSize.body,
                    fontWeight: AppFontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  '填一个图片链接（http/https）；留空则用昵称首字作为头像。',
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _avatarController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'https://example.com/avatar.png',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── 性别 / 年龄 + 可见性 ───────────────────────────────────
          //
          // 每个字段配一个独立的公开开关，而不是一个总的「公开资料」开关：
          // 用户可能愿意公开年龄但不愿公开性别（反之亦然）。
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '性别',
                  style: TextStyle(
                    fontSize: AppFontSize.body,
                    fontWeight: AppFontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    _GenderChip(
                      label: '保密',
                      selected: _gender == 0,
                      onTap: () => setState(() => _gender = 0),
                    ),
                    _GenderChip(
                      label: '男',
                      selected: _gender == 1,
                      onTap: () => setState(() => _gender = 1),
                    ),
                    _GenderChip(
                      label: '女',
                      selected: _gender == 2,
                      onTap: () => setState(() => _gender = 2),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                _PublicSwitch(
                  label: '在主页公开性别',
                  value: _genderPublic,
                  onChanged: (v) => setState(() => _genderPublic = v),
                ),
                const Divider(height: AppSpacing.lg),

                const Text(
                  '年龄',
                  style: TextStyle(
                    fontSize: AppFontSize.body,
                    fontWeight: AppFontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  '留空表示不填写。填了之后只有打开下面的开关，别人才能看到。',
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _ageController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() => _ageError = null),
                  decoration: InputDecoration(
                    hintText: '1-120',
                    errorText: _ageError,
                    suffixText: '岁',
                  ),
                ),
                _PublicSwitch(
                  label: '在主页公开年龄',
                  value: _agePublic,
                  onChanged: (v) => setState(() => _agePublic = v),
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  '未公开的信息在别人的主页上完全不会出现。',
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : const Text('保存'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 性别选项胶囊。选中态用主色填充，未选中为浅底描边。
class _GenderChip extends StatelessWidget {
  const _GenderChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gap14,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppFontSize.body,
            fontWeight: selected ? AppFontWeight.bold : AppFontWeight.regular,
            color: selected ? AppColors.onPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// 「在主页公开 XXX」开关。
///
/// 抽出来是为了让两个开关的文案排布、间距完全一致 ——
/// 隐私开关最忌讳两个位置长得不一样，用户会怀疑其中一个是别的东西。
class _PublicSwitch extends StatelessWidget {
  const _PublicSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: value,
      onChanged: onChanged,
      title: Text(
        label,
        style: const TextStyle(
          fontSize: AppFontSize.body,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}
