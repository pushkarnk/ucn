# maven-sample

A minimal Maven-based Java web application that runs on an **embedded Tomcat** server
and ships with **extra test-only dependencies** (AssertJ, Mockito, JUnit 5) that are
not needed at runtime.

## Stack

- **Java 17**, Jakarta Servlet API
- **Embedded Tomcat 10** — HTTP server (runtime)
- **Gson**, **Commons Lang3**, **Commons IO**, **SLF4J** — runtime libraries
- **JUnit 5**, **AssertJ**, **Mockito** — test-only libraries

## Layout

```
src/main/java/com/example/App.java                  starts embedded Tomcat
src/main/java/com/example/model/Greeting.java       value object
src/main/java/com/example/web/GreetingServlet.java  /api/greeting endpoint
src/main/java/com/example/web/HealthServlet.java    /health endpoint
src/main/java/com/example/web/IndexServlet.java     serves index.html
src/main/resources/static/index.html                tiny HTML/JS front end
src/test/java/...                                   unit tests (test-only deps)
```

## Test

```bash
mvn test
```

## Run

```bash
mvn -B package -DskipTests
java -cp target/maven-sample.jar com.example.App    # override the port with: -Dport=9090
```

Then open <http://localhost:8080/> or:

```bash
curl 'http://localhost:8080/api/greeting?name=ada'
# {"id":1,"content":"Hello, Ada!"}

curl 'http://localhost:8080/health'
# {"status":"healthy"}
```
