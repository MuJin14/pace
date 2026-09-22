package com.campusrun.server.util;

import com.campusrun.server.mapper.UserMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.HashSet;
import java.util.Set;
import java.util.regex.Pattern;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class UniqueIdGeneratorTest {

    private static final Pattern PATTERN = Pattern.compile("^CR-\\d{8}$");

    @Mock
    private UserMapper userMapper;

    private UniqueIdGenerator generator;

    @BeforeEach
    void setUp() {
        generator = new UniqueIdGenerator();
        when(userMapper.selectCount(any())).thenReturn(0L);
    }

    @Test
    void generate_returnsCorrectFormat() {
        String uniqueId = generator.generate(userMapper);
        assertTrue(PATTERN.matcher(uniqueId).matches(), "格式应为 CR-XXXXXXXX，实际: " + uniqueId);
    }

    @Test
    void generate_producesUniqueIds() {
        Set<String> ids = new HashSet<>();
        for (int i = 0; i < 1000; i++) {
            ids.add(generator.generate(userMapper));
        }
        assertTrue(ids.size() == 1000, "1000 次生成应无重复");
    }
}
