package com.campusrun.server.util;

import com.campusrun.server.mapper.UserMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Arrays;
import java.util.List;
import java.util.regex.Pattern;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.when;

/**
 * 专属 ID 生成器：**递增**（不是随机）。
 *
 * <p><b>为什么这段逻辑值得单独测</b>：它决定每个新用户拿到什么编号。
 * 出错的表现是「编号重复」或「编号倒退」，而这两者都只会在**注册之后**
 * 才暴露 —— 那时用户已经拿到号、可能已经念给别人听了。
 *
 * <p>历史上这里是 8 位随机数，测试也在断言「随机、不重复」。
 * 改成递增后那段断言自然失效，但它守的意图（不重复、格式恒定、无前缀）
 * 仍然有效，所以这里重写成**递增语义**下的等价断言。
 */
@ExtendWith(MockitoExtension.class)
class UniqueIdGeneratorTest {

    /** 纯数字、恒定 8 位（左侧补零）。 */
    private static final Pattern PATTERN = Pattern.compile("^\\d{8}$");

    @Mock
    private UserMapper userMapper;

    private UniqueIdGenerator generator;

    @BeforeEach
    void setUp() {
        generator = new UniqueIdGenerator();
        // 默认没有任何唯一索引冲突（个别用例会覆盖）
        lenient().when(userMapper.selectCount(any())).thenReturn(0L);
    }

    /** 设定「现有 ID 列表」。 */
    private void existing(List<Object> ids) {
        when(userMapper.selectObjs(any())).thenReturn(ids);
    }

    @Test
    @DisplayName("空表 -> 第一个用户拿 00000000")
    void firstUser_getsZero() {
        existing(List.of());
        assertEquals("00000000", generator.generate(userMapper));
    }

    @Test
    @DisplayName("递增：取现有最大值 +1")
    void incrementsFromMax() {
        existing(List.of("00000000", "00000001", "00000002"));
        assertEquals("00000003", generator.generate(userMapper));
    }

    @Test
    @DisplayName("最大值在中间也要取到（不是取最后一条）")
    void incrementsFromActualMax_notLastRow() {
        // 查询不保证顺序，必须是「最大值 +1」而不是「最后一行 +1」
        existing(List.of("00000005", "00000002", "00000027", "00000003"));
        assertEquals("00000028", generator.generate(userMapper));
    }

    @Test
    @DisplayName("格式恒为 8 位纯数字（左侧补零）")
    void formatIsAlwaysEightDigits() {
        existing(List.of("00000007"));
        String id = generator.generate(userMapper);
        assertTrue(PATTERN.matcher(id).matches(), "格式应为 8 位纯数字，实际: " + id);
        assertEquals("00000008", id, "应当补零到 8 位");
    }

    @Test
    @DisplayName("不再带 CR- 前缀（历史格式，会让用户在搜索框里犹豫要不要输前缀）")
    void noLetterPrefix() {
        existing(List.of("00000000"));
        String id = generator.generate(userMapper);
        assertFalse(id.contains("CR"), "不应再带 CR 前缀，实际: " + id);
        assertFalse(id.contains("-"), "不应含连字符，实际: " + id);
    }

    @Test
    @DisplayName("兼容历史 CR- 数据：剥掉前缀参与递增，且不会崩")
    void toleratesLegacyPrefixedIds() {
        // 历史数据里可能残留 CR-XXXXXXXX。它们**要参与**最大值计算：
        // CR-00001234 已占用序号 1234，新号必须跳过它，
        // 否则会撞上那条历史记录的唯一索引。
        // null 与完全无法解析的值按「不参与」处理，不能让生成器崩掉。
        existing(Arrays.asList("CR-00001234", null, "00000009", "非法值"));
        assertEquals("00001235", generator.generate(userMapper),
                "应当跳到已占用序号之后，而不是只 +1 到 00000010");
    }

    @Test
    @DisplayName("撞号时重试并前进（并发注册的兜底）")
    void retriesOnCollision() {
        // 第一次生成的 00000011 已被占用（模拟并发插入），第二次才空闲
        when(userMapper.selectCount(any())).thenReturn(1L, 0L);
        when(userMapper.selectObjs(any()))
                .thenReturn(List.of("00000010"), List.of("00000010", "00000011"));

        String id = generator.generate(userMapper);
        assertEquals("00000012", id, "撞号后应当重新取最大值并前进");
    }

    @Test
    @DisplayName("ID 用尽时明确报错，而不是静默溢出成 9 位")
    void throwsWhenExhausted() {
        existing(List.of("99999999"));
        IllegalStateException e = assertThrows(IllegalStateException.class,
                () -> generator.generate(userMapper));
        assertTrue(e.getMessage().contains("用尽"), "应给出可定位的原因，实际: " + e.getMessage());
    }
}
