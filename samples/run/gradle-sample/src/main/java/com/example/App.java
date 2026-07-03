package com.example;

import com.example.web.GreetingServlet;
import com.example.web.IndexServlet;
import org.eclipse.jetty.server.Server;
import org.eclipse.jetty.servlet.ServletContextHandler;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Application entry point. Starts an embedded Jetty server.
 *
 * Run with: gradle run   (override the port with -Dport=9090)
 */
public class App {

    private static final Logger LOG = LoggerFactory.getLogger(App.class);

    public static void main(String[] args) throws Exception {
        int port = Integer.getInteger("port", 8080);

        Server server = new Server(port);

        ServletContextHandler context = new ServletContextHandler(ServletContextHandler.SESSIONS);
        context.setContextPath("/");
        context.addServlet(IndexServlet.class, "/");
        context.addServlet(GreetingServlet.class, "/api/greeting");
        server.setHandler(context);

        server.start();
        LOG.info("Server started at http://localhost:{}/", port);
        server.join();
    }
}
