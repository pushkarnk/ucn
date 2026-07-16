package com.example.web;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.io.PrintWriter;
import java.io.StringWriter;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class GreetingServletTest {

    @Mock
    private HttpServletRequest request;

    @Mock
    private HttpServletResponse response;

    private GreetingServlet servlet;
    private StringWriter body;

    @BeforeEach
    void setUp() throws Exception {
        servlet = new GreetingServlet();
        body = new StringWriter();
        when(response.getWriter()).thenReturn(new PrintWriter(body));
    }

    @Test
    void defaultNameWhenQueryParamMissing() throws Exception {
        when(request.getParameter("name")).thenReturn(null);

        servlet.doGet(request, response);

        verify(response).setContentType("application/json");
        assertThat(body.toString()).contains("\"content\":\"Hello, World!\"");
        assertThat(body.toString()).contains("\"id\":1");
    }

    @Test
    void capitalizesProvidedName() throws Exception {
        when(request.getParameter("name")).thenReturn("ada");

        servlet.doGet(request, response);

        assertThat(body.toString()).contains("\"content\":\"Hello, Ada!\"");
    }
}
