package com.example.model;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class GreetingTest {

    @Test
    void exposesIdAndContent() {
        Greeting greeting = new Greeting(1L, "Hello, World!");
        assertEquals(1L, greeting.getId());
        assertEquals("Hello, World!", greeting.getContent());
    }
}
