package com.example;

import java.io.File;

import com.example.web.GreetingServlet;
import com.example.web.HealthServlet;
import com.example.web.IndexServlet;
import org.apache.catalina.Context;
import org.apache.catalina.startup.Tomcat;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Application entry point. Starts an embedded Tomcat server.
 *
 * Run with: java -cp target/maven-sample.jar com.example.App
 * (override the port with -Dport=9090)
 */
public class App {

    private static final Logger LOG = LoggerFactory.getLogger(App.class);

    public static void main(String[] args) throws Exception {
        int port = Integer.getInteger("port", 8080);

        Tomcat tomcat = new Tomcat();
        tomcat.setBaseDir(System.getProperty("java.io.tmpdir"));
        tomcat.setPort(port);
        tomcat.getConnector(); // create the default HTTP connector on the configured port

        Context context = tomcat.addContext("", new File(".").getAbsolutePath());

        Tomcat.addServlet(context, "index", new IndexServlet());
        context.addServletMappingDecoded("/", "index");

        Tomcat.addServlet(context, "greeting", new GreetingServlet());
        context.addServletMappingDecoded("/api/greeting", "greeting");

        Tomcat.addServlet(context, "health", new HealthServlet());
        context.addServletMappingDecoded("/health", "health");

        tomcat.start();
        LOG.info("Server started at http://localhost:{}/", port);
        tomcat.getServer().await();
    }
}
