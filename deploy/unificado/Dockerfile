# syntax=docker/dockerfile:1
FROM maven:3.9.9-eclipse-temurin-21 AS build
WORKDIR /build
COPY services/backend-unificado/pom.xml services/backend-unificado/pom.xml
COPY services/usuarios-service/src/main/java services/usuarios-service/src/main/java
COPY services/inventario-service/src/main/java services/inventario-service/src/main/java
COPY services/retazos-service/src/main/java services/retazos-service/src/main/java
COPY services/pedidos-service/src/main/java services/pedidos-service/src/main/java
COPY services/ubicaciones-service/src/main/java services/ubicaciones-service/src/main/java
COPY services/logistica-service/src/main/java services/logistica-service/src/main/java
COPY services/usuarios-service/src/main/resources/db services/usuarios-service/src/main/resources/db
COPY services/inventario-service/src/main/resources/db services/inventario-service/src/main/resources/db
COPY services/retazos-service/src/main/resources/db services/retazos-service/src/main/resources/db
COPY services/pedidos-service/src/main/resources/db services/pedidos-service/src/main/resources/db
COPY services/ubicaciones-service/src/main/resources/db services/ubicaciones-service/src/main/resources/db
COPY services/backend-unificado/src services/backend-unificado/src
COPY init.sql init.sql
RUN --mount=type=cache,id=alumvid-maven,target=/root/.m2,sharing=locked mvn -B -ntp -f services/backend-unificado/pom.xml package -DskipTests
FROM eclipse-temurin:21-jre-alpine
RUN addgroup -S app && adduser -S app -G app
WORKDIR /app
COPY --from=build /build/services/backend-unificado/target/backend-unificado-1.0.0.jar app.jar
ENV JAVA_TOOL_OPTIONS="-Xms64m -Xmx192m -Xss384k -XX:MaxMetaspaceSize=160m -XX:ReservedCodeCacheSize=48m -XX:MaxDirectMemorySize=32m -XX:+UseSerialGC -XX:ActiveProcessorCount=2 -XX:+ExitOnOutOfMemoryError"
USER app
EXPOSE 8080
ENTRYPOINT ["java","-jar","/app/app.jar"]
