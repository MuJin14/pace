"""生成《校园跑 App 项目计划书》Word 文档。

数据来源（全部取自仓库实测，非估算）：
  · 后端 Java 代码行数   —— campus-run-backend 下 .java 文件统计
  · 前端 Dart 代码行数   —— campus-run-app/lib 下 .dart 文件统计
  · 端点 / 表 / 模块数   —— controller 注解、schema.sql、features 目录
  · 测试用例数           —— mvn test 与 flutter test 的实测输出
"""
from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

DESKTOP = r"C:\Users\沐瑾\Desktop"
OUT = DESKTOP + r"\校园跑App项目计划书.docx"

# ── 品牌配色（与 App 主题一致：主色橙 #FF8C42，深咖标题 #2E2419）──
C_PRIMARY = RGBColor(0xFF, 0x8C, 0x42)
C_TITLE = RGBColor(0x2E, 0x24, 0x19)
C_BODY = RGBColor(0x3A, 0x33, 0x2B)
C_MUTED = RGBColor(0x8C, 0x80, 0x75)

CN_FONT = "微软雅黑"

# ⚠️ 页面尺寸必须显式设成 A4 并收窄页边距。
# 默认是 Letter(21.59cm) + 左右各 3.17cm 页边距，可用宽度只有约 15.2cm ——
# 表格一旦按「整页宽度」设计就会被右侧裁掉（实际渲染验证时确实发生了）。
# A4 宽 21cm、左右各 2cm → 可用约 17cm。
PAGE_W = Cm(21.0)
MARGIN_X = Cm(2.0)
CONTENT_W = 17.0  # cm，表格列宽之和不得超过它


def a4(section):
    section.page_width = Cm(21.0)
    section.page_height = Cm(29.7)
    section.left_margin = MARGIN_X
    section.right_margin = MARGIN_X
    section.top_margin = Cm(2.5)
    section.bottom_margin = Cm(2.2)


def add_page_number(section):
    """页脚居中页码（PAGE 域）。"""
    p = section.footer.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run()
    set_cn(r, CN_FONT)
    r.font.size = Pt(9)
    r.font.color.rgb = C_MUTED
    fld = OxmlElement("w:fldSimple")
    fld.set(qn("w:instr"), "PAGE")
    r._element.addnext(fld)


def set_cn(run, name=CN_FONT):
    """中文字体必须显式设置 w:eastAsia，只设 font.name 不生效。"""
    run.font.name = name
    run._element.get_or_add_rPr().get_or_add_rFonts().set(qn("w:eastAsia"), name)


def style_doc(doc):
    """全局样式：正文中文可读性、标题层级颜色。"""
    normal = doc.styles["Normal"]
    normal.font.size = Pt(10.5)
    normal.font.color.rgb = C_BODY
    normal.font.name = CN_FONT
    # ⚠️ 不能直接用 normal.element.rPr —— 新建文档时它可能是 None，
    # 必须走 get_or_add_rPr() 才会真正建出来。
    normal.element.get_or_add_rPr().get_or_add_rFonts().set(qn("w:eastAsia"), CN_FONT)

    for lvl, size in ((1, 16), (2, 13), (3, 11.5)):
        st = doc.styles[f"Heading {lvl}"]
        st.font.name = CN_FONT
        st.font.size = Pt(size)
        st.font.bold = True
        st.font.color.rgb = C_TITLE if lvl > 1 else C_PRIMARY
        st.element.get_or_add_rPr().get_or_add_rFonts().set(
            qn("w:eastAsia"), CN_FONT)


def para(doc, text, size=10.5, bold=False, color=C_BODY, align=None,
         space_after=6, indent=None):
    p = doc.add_paragraph()
    if align is not None:
        p.alignment = align
    p.paragraph_format.space_after = Pt(space_after)
    if indent:
        p.paragraph_format.left_indent = Cm(indent)
    r = p.add_run(text)
    r.font.size = Pt(size)
    r.font.bold = bold
    r.font.color.rgb = color
    set_cn(r)
    return p


def bullet(doc, text, size=10.5):
    p = doc.add_paragraph(style="List Bullet")
    p.paragraph_format.space_after = Pt(3)
    r = p.add_run(text)
    r.font.size = Pt(size)
    r.font.color.rgb = C_BODY
    set_cn(r)
    return p


def table(doc, headers, rows, widths=None):
    t = doc.add_table(rows=1, cols=len(headers))
    t.style = "Table Grid"
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.autofit = False

    # ⚠️⚠️ 这里有两个必须一起处理的坑，缺一个表格就会超出页面被右侧裁掉：
    #
    #  1. python-docx 建表时写入 `tblW type="auto" w="0"` —— 意思是
    #     「按内容自适应」，**它会盖过我们在单元格上设的宽度**。
    #     必须改成 type="dxa" 并给出总宽，否则列宽设定形同虚设。
    #
    #  2. 光有固定总宽还不够，还要写 `w:tblLayout type="fixed"`，
    #     渲染器才真的按 tblGrid 的列宽走。
    #
    # 另外 OOXML 对 tblPr 的子元素**顺序有要求**（tblW 在 tblLayout 之前），
    # 顺序不对时 Word 会判定文档损坏。所以这里用 python-docx 的 `tblW`
    # 属性（内部会插到正确位置），tblLayout 则插在 jc 之后。
    if widths:
        total_twips = int(sum(widths) * 567)  # 1cm ≈ 567 twips
        tblPr = t._tbl.tblPr

        # 清掉重复节点：python-docx 已经建了一个 tblW(auto)，
        # 直接 append 会变成两个 tblW —— 渲染器取哪个不确定。
        for tag in ("w:tblW", "w:tblLayout", "w:tblCellMar", "w:tblInd"):
            for old in tblPr.findall(qn(tag)):
                tblPr.remove(old)

        # schema 顺序：tblStyle → tblW → jc → tblInd → tblLayout → tblCellMar
        tblW = OxmlElement("w:tblW")
        tblW.set(qn("w:type"), "dxa")
        tblW.set(qn("w:w"), str(total_twips))
        style_el = tblPr.find(qn("w:tblStyle"))
        if style_el is not None:
            style_el.addnext(tblW)
        else:
            tblPr.insert(0, tblW)

        layout = OxmlElement("w:tblLayout")
        layout.set(qn("w:type"), "fixed")
        jc = tblPr.find(qn("w:jc"))
        (jc.addnext(layout) if jc is not None else tblW.addnext(layout))

        # 单元格内边距：默认左右各约 0.19cm，多列累加会把表格撑宽。
        # 这里压到 0.10cm，既省宽度又不至于让文字贴边。
        mar = OxmlElement("w:tblCellMar")
        for side, twips in (("left", 57), ("right", 57), ("top", 28), ("bottom", 28)):
            e = OxmlElement("w:" + side)
            e.set(qn("w:w"), str(twips))
            e.set(qn("w:type"), "dxa")
            mar.append(e)
        tblPr.append(mar)
    for i, h in enumerate(headers):
        cell = t.rows[0].cells[i]
        cell.text = ""
        r = cell.paragraphs[0].add_run(h)
        r.font.bold = True
        r.font.size = Pt(9.5)
        r.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
        set_cn(r)
        # 表头底色：品牌橙
        shd = OxmlElement("w:shd")
        shd.set(qn("w:val"), "clear")
        shd.set(qn("w:fill"), "FF8C42")
        cell._tc.get_or_add_tcPr().append(shd)
    for row in rows:
        cells = t.add_row().cells
        for i, v in enumerate(row):
            cells[i].text = ""
            r = cells[i].paragraphs[0].add_run(str(v))
            r.font.size = Pt(9)
            r.font.color.rgb = C_BODY
            set_cn(r)
    if widths:
        # 同时设到 cell.width 与 w:gridCol，否则 Word 会忽略其一
        for row in t.rows:
            for i, w in enumerate(widths):
                row.cells[i].width = Cm(w)
        for i, w in enumerate(widths):
            t.columns[i].width = Cm(w)
    doc.add_paragraph().paragraph_format.space_after = Pt(2)
    return t


doc = Document()
style_doc(doc)
a4(doc.sections[0])
add_page_number(doc.sections[0])

# ══════════════════════════════════════════════════════════════════════
# 封面
# ══════════════════════════════════════════════════════════════════════
for _ in range(3):
    doc.add_paragraph()

para(doc, "校 园 跑", size=36, bold=True, color=C_PRIMARY,
     align=WD_ALIGN_PARAGRAPH.CENTER, space_after=2)
para(doc, "Campus Run", size=15, color=C_MUTED,
     align=WD_ALIGN_PARAGRAPH.CENTER, space_after=4)
para(doc, "项目计划书", size=20, bold=True, color=C_TITLE,
     align=WD_ALIGN_PARAGRAPH.CENTER, space_after=30)
para(doc, "面向高校学生的运动记录与社交应用", size=12, color=C_MUTED,
     align=WD_ALIGN_PARAGRAPH.CENTER, space_after=6)
para(doc, "记录你的每一段行程", size=11, color=C_MUTED,
     align=WD_ALIGN_PARAGRAPH.CENTER, space_after=48)

table(doc, ["项目名称", "校园跑 Campus Run"],
      [["文档类型", "项目计划书"],
       ["当前版本", "App 1.10.1"],
       ["项目状态", "核心功能全部上线，处于迭代优化阶段"],
       ["编制日期", "2026 年 10 月 6 日"]],
      widths=[3.9, 8.6])

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════
doc.add_heading("一、项目概述", level=1)

doc.add_heading("1.1 项目背景", level=2)
para(doc, "高校学生日常跑步锻炼普遍存在三个问题：缺少记录工具、缺少持续动力、"
          "缺少同伴互动。市面上的跑步应用多为成人马拉松设计，功能繁杂、社交链路长，"
          "与学生「课间跑一圈」「操场刷圈」的实际场景并不吻合。")
para(doc, "校园跑（Campus Run）针对这一场景设计：以「轻量记录 + 校园社交」为核心，"
          "把跑步记录、排行榜、好友互动、校园围栏打卡整合在一个应用内，"
          "让学生打开即用、跑完即分享。")

doc.add_heading("1.2 项目目标", level=2)
para(doc, "总体目标：成为面向高校场景的、可独立运维的运动记录与社交应用。")
bullet(doc, "功能目标：完整覆盖「记录 — 排行 — 社交 — 激励」闭环，"
            "核心链路不依赖第三方服务。")
bullet(doc, "质量目标：关键业务逻辑有自动化测试保护，后端与前端测试用例数均超过 400。")
bullet(doc, "交付目标：具备自建分发能力，用户可直接从官网下载安装包并在线更新。")
bullet(doc, "成本目标：以最小服务器规格支撑校园规模用户，年运营成本控制在百元级别。")

doc.add_heading("1.3 目标用户", level=2)
table(doc, ["用户类型", "特征", "核心诉求"],
      [["在校学生（主要）", "有跑步习惯或课程要求，手机为中端 Android 机型",
        "快速记录、看排名、和同学互动"],
       ["学生管理员", "负责同学账号问题的处理", "重置密码、查看用户、处理申诉"]],
      widths=[3.4, 5.1, 4.0])

doc.add_heading("1.4 当前状态", level=2)
para(doc, "项目已完成四个阶段的全部开发，线上稳定运行，进入迭代优化阶段。")
table(doc, ["指标", "现状"],
      [["代码规模", "后端 223 个 Java 文件 / 19,319 行；前端 130 个 Dart 文件 / 19,709 行"],
       ["接口数量", "53 个 REST 端点 + 1 个 WebSocket 长连接"],
       ["数据表", "14 张业务表"],
       ["功能模块", "前端 11 个业务模块"],
       ["自动化测试", "后端 412 个用例、前端 447 个用例，全部通过"],
       ["线上版本", "App 1.10.1，安装包 54.2 MB"],
       ["注册用户", "27 人（当前为小范围试用阶段）"]],
      widths=[3.2, 9.3])

# ══════════════════════════════════════════════════════════════════════
doc.add_heading("二、功能规划", level=1)

para(doc, "功能按四个阶段推进，目前**均已实现并通过线上验证**。")

doc.add_heading("2.1 第一阶段：账号与运动记录", level=2)
bullet(doc, "注册 / 登录 / 令牌刷新：手机号注册，双令牌机制（访问令牌 2 小时、"
            "刷新令牌 30 天），支持单设备登录——新设备登录会顶掉旧设备，避免账号共用。")
bullet(doc, "跑步与骑行记录：实时定位打点、距离与配速计算、轨迹保存与回放。")
bullet(doc, "运动数据统计：累计里程、次数、连续天数、周目标完成度。")

doc.add_heading("2.2 第二阶段：排行榜与校园围栏", level=2)
bullet(doc, "排行榜：按日 / 周 / 月 / 滚动 30 天四个周期，区分跑步与骑行。"
            "完全基于 MySQL 聚合，不引入 Redis 等额外中间件。")
bullet(doc, "校园围栏：管理员可划定电子围栏区域，并设置围栏内运动记录是否计入排行，"
            "防止骑车刷榜等作弊行为。")

doc.add_heading("2.3 第三阶段：好友与聊天", level=2)
bullet(doc, "好友体系：按专属 ID、昵称或手机号搜索并添加；支持申请、接受、拒绝、删除。")
bullet(doc, "即时聊天：基于 WebSocket 的长连接，支持文本、图片、表情包三类消息，"
            "含离线消息补发与已读回执。")
bullet(doc, "消息提醒：系统通知栏推送 + 应用内红点；支持按会话设置免打扰。")
bullet(doc, "未读状态：服务端维护未读计数，重新登录或回到前台时自动重建，"
            "确保离线期间的消息不会被遗漏。")

doc.add_heading("2.4 第四阶段：目标、勋章与个人档案", level=2)
bullet(doc, "运动目标：按周 / 月 / 自定义周期设定里程目标，进度实时更新并自动结算。")
bullet(doc, "勋章体系：管理员配置勋章规则，达成后自动授予，个人主页展示勋章墙。")
bullet(doc, "个人档案：头像、昵称、专属 ID；性别与年龄可选填，并可单独设置是否公开。")

doc.add_heading("2.5 管理端能力", level=2)
bullet(doc, "用户管理：查看用户列表，为忘记密码的同学重置密码。")
bullet(doc, "密码申诉：学生提交申诉后，管理员在后台处理，避免线下沟通成本。")
bullet(doc, "围栏维护：增删改查校园围栏区域。")
bullet(doc, "数据修复：提供里程重算工具，用于修正历史异常数据。")

# ══════════════════════════════════════════════════════════════════════
doc.add_heading("三、技术架构", level=1)

doc.add_heading("3.1 技术选型", level=2)
table(doc, ["层次", "技术栈", "选型说明"],
      [["移动端", "Flutter 3.29 / Dart 3.7", "一套代码覆盖 Android，界面一致性好"],
       ["状态管理", "Riverpod 3", "编译期安全，依赖关系显式"],
       ["路由", "go_router 17", "声明式路由，便于深链与重定向"],
       ["网络", "Dio 5", "拦截器机制适合统一处理鉴权与重试"],
       ["后端", "Java 17 / Spring Boot 3.2.5", "生态成熟，招聘与维护成本低"],
       ["持久层", "MyBatis-Plus 3.5.7", "SQL 可控，便于性能调优"],
       ["数据库", "MySQL 8", "免费、稳定，满足校园规模"],
       ["鉴权", "Spring Security + JWT", "无状态鉴权，便于水平扩展"],
       ["实时通信", "原生 WebSocket", "聊天场景需求明确，无需额外中间件"]],
      widths=[2.4, 4.3, 5.8])

doc.add_heading("3.2 架构特点", level=2)
bullet(doc, "零额外中间件：不使用 Redis、消息队列或搜索引擎，排行榜等聚合能力"
            "全部落在 MySQL。降低运维复杂度与成本，是本项目的核心取舍。")
bullet(doc, "前后端分离：后端提供纯 REST + WebSocket 接口，前端完全独立，"
            "便于后续接入 Web 端或小程序。")
bullet(doc, "幂等设计：所有影响数据的操作均考虑重复执行的安全性，"
            "数据库迁移脚本可重复运行。")

doc.add_heading("3.3 部署架构", level=2)
table(doc, ["组件", "说明"],
      [["服务器", "腾讯云轻量应用服务器，2 核 2G / 50GB，上海地域"],
       ["应用服务", "Spring Boot 以 Docker 容器运行，源码在服务器构建"],
       ["数据库", "MySQL 8 容器，与应用同机部署"],
       ["官网与分发", "静态站点托管于 Cloudflare Workers，安装包经独立域名分发"],
       ["应用访问地址", "IP 直连方式，规避域名备案限制"]],
      widths=[3.2, 9.3])

# ══════════════════════════════════════════════════════════════════════
doc.add_heading("四、实施计划", level=1)

para(doc, "项目自 2026 年 9 月 22 日启动，采用「先跑通闭环、再打磨体验」的推进策略。"
          "四个阶段的开发已完成，当前处于持续迭代阶段。")

doc.add_heading("4.1 已完成阶段", level=2)
table(doc, ["阶段", "内容", "状态"],
      [["第一阶段", "账号体系与运动记录", "已完成"],
       ["第二阶段", "排行榜与校园围栏", "已完成"],
       ["第三阶段", "好友与即时聊天", "已完成"],
       ["第四阶段", "目标、勋章与个人档案", "已完成"],
       ["上线运营", "官网上线、自建分发、在线更新机制", "已完成"]],
      widths=[2.8, 7.0, 2.7])

doc.add_heading("4.2 迭代阶段的工作方式", level=2)
para(doc, "上线后的迭代以「用户反馈驱动」为主，每轮围绕一个具体问题做完整闭环：")
bullet(doc, "定位根因：不接受「看起来能用」，必须先解释清楚现象背后的机制。")
bullet(doc, "修复加测试：每个修复都需附带回归用例，避免同类问题重复出现。")
bullet(doc, "全链路验证：改动后跑通全部自动化测试，并做端到端的线上验证。")
bullet(doc, "记录沉淀：把根因与取舍写进项目文档，避免重复讨论。")

doc.add_heading("4.3 后续规划", level=2)
table(doc, ["优先级", "事项", "说明"],
      [["高", "提升安装包分发速度", "当前受服务器出口带宽限制，正在评估独立分发渠道"],
       ["高", "系统级消息推送", "解决应用被系统回收后无法收到消息的问题，"
                                "需接入手机厂商推送通道"],
       ["中", "完善后台管理界面", "当前管理功能以接口为主，可补充可视化操作界面"],
       ["中", "界面细节打磨", "根据实际使用反馈优化交互与视觉"],
       ["低", "多端支持", "在现有接口基础上扩展 Web 端"]],
      widths=[2.0, 4.1, 6.4])

# ══════════════════════════════════════════════════════════════════════
doc.add_heading("五、质量保障", level=1)

doc.add_heading("5.1 测试策略", level=2)
para(doc, "项目采用分层测试，覆盖后端业务逻辑、接口契约与前端组件行为。"
          "测试用例数随功能迭代持续增长，作为改动安全性的主要保障。")
table(doc, ["测试层", "用例数", "覆盖重点"],
      [["后端单元与集成测试", "412", "业务规则、鉴权、并发、数据一致性"],
       ["前端组件与逻辑测试", "447", "状态管理、界面渲染、边界条件"],
       ["端到端链路测试", "持续补充", "启动流程、更新检查、消息提醒等跨模块链路"]],
      widths=[3.8, 2.4, 6.3])

doc.add_heading("5.2 质量红线", level=2)
bullet(doc, "禁止静默失败：任何「失败但用户无感」的逻辑必须留下可诊断的日志，"
            "否则问题会长期潜伏。")
bullet(doc, "禁止测试绕过故障点：如果测试把唯一可能出错的环节替换成了模拟实现，"
            "该测试即视为无效，必须补一条真实路径的用例。")
bullet(doc, "数据变更必须先备份：任何涉及生产数据的操作，执行前必须完成备份并验证备份可用。")
bullet(doc, "上线前跑通全部测试：静态检查与全部自动化测试通过方可发布。")

doc.add_heading("5.3 版本管理", level=2)
para(doc, "采用语义化版本号。每次发布包含三件事：更新版本号、打包安装包、"
          "在服务端登记版本信息（版本号、更新说明、安装包校验值）。"
          "客户端启动时比对版本，发现新版本后在应用内提醒用户更新。")

# ══════════════════════════════════════════════════════════════════════
doc.add_heading("六、成本与资源", level=1)

doc.add_heading("6.1 成本构成", level=2)
table(doc, ["项目", "说明", "成本"],
      [["云服务器", "2 核 2G 轻量应用服务器", "约 100 元 / 年（学生优惠）"],
       ["数据库", "与应用同机部署的 MySQL", "0 元"],
       ["官网托管", "Cloudflare Workers 静态托管", "0 元（免费额度内）"],
       ["软件开发", "自研", "0 元"],
       ["应用分发", "自建下载服务", "0 元"]],
      widths=[2.8, 6.2, 3.5])
para(doc, "除服务器外无固定支出，整体运营成本控制在百元级别，"
          "符合校园项目的可持续性要求。", color=C_MUTED, size=10)

doc.add_heading("6.2 资源需求", level=2)
bullet(doc, "开发：1 人，全栈（后端 + 移动端 + 运维）。")
bullet(doc, "测试：以自动化测试为主，真机验证为辅。")
bullet(doc, "推广：依靠校园内口碑传播与同学推荐，暂无付费推广计划。")

# ══════════════════════════════════════════════════════════════════════
doc.add_heading("七、风险与应对", level=1)

table(doc, ["风险", "影响", "应对措施"],
      [["服务器出口带宽有限", "安装包下载速度慢，影响新用户安装体验",
        "评估独立分发渠道；优化安装包体积"],
       ["应用被系统回收", "后台无法收到消息提醒",
        "已实现重新打开时补推未读；后续接入厂商推送通道"],
       ["国产系统省电策略", "后台长连接被限制",
        "提供各机型设置指引，由用户自主选择是否放宽限制"],
       ["单点部署", "服务器故障会导致服务不可用",
        "定期备份数据库；关键操作前强制备份"],
       ["用户规模增长", "单机数据库可能成为瓶颈",
        "当前架构预留了扩展空间，可在需要时拆分数据库"],
       ["分发渠道合规", "自建分发存在渠道风险",
        "已评估官方分发渠道方案，待条件成熟后迁移"]],
      widths=[3.2, 4.3, 5.0])

# ══════════════════════════════════════════════════════════════════════
doc.add_heading("八、预期成果", level=1)

doc.add_heading("8.1 已交付成果", level=2)
bullet(doc, "一套完整可用的校园运动社交应用（Android）。")
bullet(doc, "一套独立可维护的服务端系统，含 53 个接口与完整管理能力。")
bullet(doc, "859 个自动化测试用例构成的质量保障体系。")
bullet(doc, "自建官网与分发渠道，具备完整的发布与更新能力。")
bullet(doc, "完整的项目文档体系，覆盖架构、领域约定、部署与运维。")

doc.add_heading("8.2 后续目标", level=2)
bullet(doc, "短期：解决安装包分发速度与后台消息可达性两个体验短板。")
bullet(doc, "中期：完善管理端界面，降低运营门槛。")
bullet(doc, "长期：在校园内形成稳定的用户规模，验证产品价值。")

# ══════════════════════════════════════════════════════════════════════
# 附：数据口径说明
# ══════════════════════════════════════════════════════════════════════
doc.add_page_break()
doc.add_heading("附：数据口径说明", level=1)
para(doc, "本计划书中的所有量化数据均取自项目仓库的实测结果，采集方式如下：", size=10)
table(doc, ["数据", "采集方式"],
      [["代码行数", "统计对应目录下源文件的行数（不含构建产物）"],
       ["接口数量", "统计后端控制器中的路由注解数量"],
       ["数据表数量", "统计数据库建表脚本中的建表语句"],
       ["测试用例数", "执行完整测试套件后读取的实际结果"],
       ["安装包体积", "对发布产物直接测量"],
       ["用户数量", "读取线上数据库的实际记录数"]],
      widths=[3.2, 9.3])
para(doc, "文档中的功能描述与架构说明与实际代码保持一致；"
          "后续规划部分为计划性内容，可能随实际情况调整。",
     size=10, color=C_MUTED)

doc.save(OUT)
print("已生成：%s" % OUT)
