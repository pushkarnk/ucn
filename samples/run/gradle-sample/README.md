# gradle-sample

A minimal Gradle-based Java web application that runs on an **embedded Jetty** server
(no external servlet container required).

## Stack

- **Java 17** (toolchain), Jakarta Servlet API
- **Embedded Jetty 11** — HTTP server
- **Gson** — JSON serialization
- **Apache Commons Lang3** + **Commons IO** — string / stream utilities
- **SLF4J** — logging
- **JUnit 5** — tests

## Layout

```
src/main/java/com/example/App.java                  starts embedded Jetty
src/main/java/com/example/model/Greeting.java       value object
src/main/java/com/example/web/GreetingServlet.java  /api/greeting endpoint
src/main/java/com/example/web/IndexServlet.java      serves index.html
src/main/resources/static/index.html                 tiny HTML/JS front end
src/test/java/...                                    unit test
```

## Build & test

```bash
gradle build
```

## Run locally

```bash
gradle run            # override the port with: gradle run -Dport=9090
```

Then open <http://localhost:8080/> and click **Greet**, or call the API directly:

```bash
curl 'http://localhost:8080/api/greeting?name=ada'
# {"id":1,"content":"Hello, Ada!"}
```
