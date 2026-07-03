# maven-sample

A minimal Maven-based Java web application that runs on an **embedded Tomcat** server
(no external servlet container required).

## Stack

- **Java 17**, Jakarta Servlet API
- **Embedded Tomcat 10** — HTTP server
- **Gson** — JSON serialization
- **Apache Commons Lang3** + **Commons IO** — string / stream utilities
- **SLF4J** — logging
- **JUnit 5** — tests

## Layout

```
src/main/java/com/example/App.java                  starts embedded Tomcat
src/main/java/com/example/model/Greeting.java       value object
src/main/java/com/example/web/GreetingServlet.java  /api/greeting endpoint
src/main/java/com/example/web/IndexServlet.java      serves index.html
src/main/resources/static/index.html                 tiny HTML/JS front end
src/test/java/...                                    unit test
```

## Build & test

```bash
mvn clean package
```

Produces a runnable fat JAR at `target/maven-sample.jar`.

## Run locally

```bash
java -cp target/maven-sample.jar com.example.App    # override the port with: -Dport=9090
```

Then open <http://localhost:8080/> and click **Greet**, or call the API directly:

```bash
curl 'http://localhost:8080/api/greeting?name=ada'
# {"id":1,"content":"Hello, Ada!"}
```
