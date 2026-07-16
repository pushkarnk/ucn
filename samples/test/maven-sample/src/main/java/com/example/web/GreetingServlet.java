package com.example.web;

import java.io.IOException;
import java.util.concurrent.atomic.AtomicLong;

import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import com.example.model.Greeting;
import com.google.gson.Gson;
import org.apache.commons.lang3.StringUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Returns a JSON greeting. Try:
 *   GET /api/greeting
 *   GET /api/greeting?name=Ada
 */
public class GreetingServlet extends HttpServlet {

    private static final Logger LOG = LoggerFactory.getLogger(GreetingServlet.class);
    private static final String DEFAULT_NAME = "World";

    private final AtomicLong counter = new AtomicLong();
    private final Gson gson = new Gson();

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        String name = StringUtils.defaultIfBlank(req.getParameter("name"), DEFAULT_NAME);
        Greeting greeting = new Greeting(counter.incrementAndGet(), "Hello, " + StringUtils.capitalize(name) + "!");

        LOG.info("Serving greeting #{} for name='{}'", greeting.getId(), name);

        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");
        resp.getWriter().write(gson.toJson(greeting));
    }
}
