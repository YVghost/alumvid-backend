FROM maven:3.9.9-eclipse-temurin-21 AS build
WORKDIR /build
COPY pom.xml .
COPY src src
RUN mvn -B -ntp package -DskipTests
FROM eclipse-temurin:21-jre-alpine
RUN addgroup -S app && adduser -S app -G app
WORKDIR /app
COPY --from=build /build/target/ubicaciones-service-1.0.0.jar app.jar
USER app
EXPOSE 8086
ENTRYPOINT ["java", "-jar", "app.jar"]
