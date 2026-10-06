import zipfile

APK = r"C:\Users\沐瑾\Desktop\campus-run.apk"

z = zipfile.ZipFile(APK)
app = b"".join(n and z.read(n) or b"" for n in z.namelist() if n.endswith("libapp.so"))


def has(s):
    """Dart AOT 字符串池是 UTF-16LE；emoji 为非 BMP，Python 会自动生成代理对。"""
    return s.encode("utf-16-le") in app


STRING_CHECKS = [
    ("P2.1  时间分隔条『昨天』", "\u6628\u5929"),
    ("P2.2  通知渠道名『聊天消息』", "\u804a\u5929\u6d88\u606f"),
    ("P2.2  渠道说明『好友发来的新消息提醒』", "\u597d\u53cb\u53d1\u6765\u7684\u65b0\u6d88\u606f\u63d0\u9192"),
    ("P2.2  通知标题兜底『新消息』", "\u65b0\u6d88\u606f"),
    ("P2.3  免打扰页标题", "\u6d88\u606f\u514d\u6253\u6270"),
    ("P2.4  emoji U+1F600", "\U0001F600"),
    ("P2.4  emoji U+1F44D", "\U0001F44D"),
    ("P2.4  emoji U+1F3C3", "\U0001F3C3"),
    ("P2.4  emoji 分组『常用』", "\u5e38\u7528"),
    ("P2.4  emoji 分组『运动』", "\u8fd0\u52a8"),
    ("P2.4  页签『表情包』", "\u8868\u60c5\u5305"),
    ("P2.4  预览占位『[图片]』", "[\u56fe\u7247]"),
    ("P2.4  加载失败文案", "\u56fe\u7247\u52a0\u8f7d\u5931\u8d25"),
    ("P2.5  修改密码页标题", "\u4fee\u6539\u5bc6\u7801"),
    ("P2.5  改密成功提示", "\u5bc6\u7801\u5df2\u4fee\u6539"),
    ("P2.6  资料页『性别』", "\u6027\u522b"),
    ("P2.6  资料页『年龄』", "\u5e74\u9f84"),
    ("P2.6  公开开关文案含『主页』", "\u5728\u4e3b\u9875\u516c\u5f00"),
]

SYMBOL_CHECKS = [
    "ChatNotificationService",
    "decideNotifyAction",
    "buildNotificationContent",
    "groupMessagesByTime",
    "formatChatSeparator",
    "ChatMuteSettingsPage",
    "ChangePasswordPage",
    "upload/chat-image",
    "campus_run_message",
    "asset:",
]

print("libapp.so bytes:", len(app))
print("")
print("-- 符号（ASCII）--")
sym_ok = 0
for s in SYMBOL_CHECKS:
    ok = s.encode() in app
    sym_ok += ok
    print(("  OK      " if ok else "  MISSING ") + s)

print("")
print("-- 界面文案 / emoji（UTF-16LE）--")
str_ok = 0
for desc, s in STRING_CHECKS:
    ok = has(s)
    str_ok += ok
    print(("  OK      " if ok else "  MISSING ") + desc)

print("")
print("符号 %d/%d 通过；文案 %d/%d 通过" % (sym_ok, len(SYMBOL_CHECKS), str_ok, len(STRING_CHECKS)))
z.close()
