FROM maven:3.9.9-eclipse-temurin-21 AS build
WORKDIR /build
COPY services/logistica-service/pom.xml .
COPY services/logistica-service/src src
RUN --mount=type=cache,id=alumvid-maven,target=/root/.m2,sharing=locked mvn -B -ntp -Dmaven.wagon.http.retryHandler.count=3 package -DskipTests
FROM eclipse-temurin:21-jre-alpine
RUN addgroup -S app && adduser -S app -G app
WORKDIR /app
COPY --from=build /build/target/logistica-service-1.0.0.jar app.jar
USER app
EXPOSE 8083
ENTRYPOINT ["java", "-jar", "app.jar"]
