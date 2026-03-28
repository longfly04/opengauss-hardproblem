FROM maven:3.9-eclipse-temurin-21 AS build

RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src/benchbase
RUN git clone https://github.com/cmu-db/benchbase.git .
RUN ./mvnw -q clean package -P postgres
RUN archive="$(find target -maxdepth 1 -type f -name 'benchbase-*.tgz' | head -n1)" \
    && test -n "$archive" \
    && mkdir -p /opt/benchbase \
    && tar -xzf "$archive" -C /opt/benchbase --strip-components=1
RUN mvn -q dependency:get -Dartifact=org.opengauss:opengauss-jdbc:6.0.3 \
    && cp /root/.m2/repository/org/opengauss/opengauss-jdbc/6.0.3/opengauss-jdbc-6.0.3.jar /opt/benchbase/lib/

FROM eclipse-temurin:21-jre
WORKDIR /opt/benchbase
COPY --from=build /opt/benchbase /opt/benchbase
ENTRYPOINT ["bash", "-lc"]
