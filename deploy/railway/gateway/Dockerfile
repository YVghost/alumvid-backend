FROM maven:3.9.9-eclipse-temurin-21 AS build
WORKDIR /build
COPY services/gateway-service/pom.xml .
COPY services/gateway-service/src src
RUN --mount=type=cache,id=alumvid-maven,target=/root/.m2,sharing=locked mvn -B -ntp -Dmaven.wagon.http.retryHandler.count=3 package -DskipTests
FROM eclipse-temurin:21-jre-alpine
RUN apk add --no-cache nginx gettext && addgroup -S app && adduser -S app -G app
WORKDIR /app
COPY --from=build /build/target/gateway-service-1.0.0.jar app.jar
COPY deploy/railway/gateway/nginx.conf.template /app/nginx.conf.template
COPY deploy/railway/gateway/start.sh /app/start.sh
RUN chmod +x /app/start.sh
USER app
EXPOSE 8080
ENTRYPOINT ["/app/start.sh"]
