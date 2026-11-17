FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /build
COPY pom.xml .
COPY src src
RUN mvn -q -B package dependency:copy-dependencies -DoutputDirectory=target/lib

FROM eclipse-temurin:21-jre
RUN apt-get update && apt-get install -y --no-install-recommends curl
COPY --from=build /build/target/lib /app/lib
COPY --from=build /build/target/classes /app/classes
CMD ["java", "-cp", "/app/classes:/app/lib/*", "interop.Server"]
