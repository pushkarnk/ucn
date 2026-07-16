package com.example.model;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

class GreetingTest {

    @Test
    void exposesIdAndContent() {
        Greeting greeting = new Greeting(1L, "Hello, World!");

        assertThat(greeting.getId()).isEqualTo(1L);
        assertThat(greeting.getContent()).isEqualTo("Hello, World!");
    }

    @ParameterizedTest
    @CsvSource({
            "1, 'Hello, Ada!'",
            "42, 'Hello, World!'",
            "100, 'Bonjour, Guest!'"
    })
    void preservesAssignedValues(long id, String content) {
        Greeting greeting = new Greeting(id, content);

        assertThat(greeting.getId()).isEqualTo(id);
        assertThat(greeting.getContent()).isEqualTo(content);
    }
}
