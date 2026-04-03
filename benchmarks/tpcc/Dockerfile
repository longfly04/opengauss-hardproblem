FROM docker.1ms.run/maven:3.9-eclipse-temurin-21 AS build

RUN if command -v apt-get >/dev/null 2>&1; then \
        apt-get update && apt-get install -y --no-install-recommends git && rm -rf /var/lib/apt/lists/*; \
    elif command -v apk >/dev/null 2>&1; then \
        apk add --no-cache git; \
    elif command -v yum >/dev/null 2>&1; then \
        yum install -y git && yum clean all; \
    fi

WORKDIR /src/benchbase
RUN git clone https://github.com/cmu-db/benchbase.git .
# 修改pom.xml中的Java版本为21，并添加openGauss JDBC依赖
RUN sed -i 's/<maven.compiler.source>23<\/maven.compiler.source>/<maven.compiler.source>21<\/maven.compiler.source>/g' pom.xml && \
    sed -i 's/<maven.compiler.target>23<\/maven.compiler.target>/<maven.compiler.target>21<\/maven.compiler.target>/g' pom.xml
# 在postgresql依赖后添加openGauss依赖 - 使用多行文本替换
RUN apt-get update && apt-get install -y --no-install-recommends patch && rm -rf /var/lib/apt/lists/*
COPY add-opengauss-dep.patch /tmp/
RUN patch -p0 < /tmp/add-opengauss-dep.patch
RUN cat pom.xml | grep -A 15 "postgresql"
RUN mvn -q clean package -P postgres -DskipTests
RUN archive="$(find target -maxdepth 1 -type f -name 'benchbase-*.tgz' | head -n1)" \
    && test -n "$archive" \
    && mkdir -p /opt/benchbase \
    && tar -xzf "$archive" -C /opt/benchbase --strip-components=1

FROM docker.1ms.run/maven:3.9-eclipse-temurin-21
WORKDIR /opt/benchbase
COPY --from=build /opt/benchbase /opt/benchbase
# 创建运行脚本，确保在正确的目录下运行
RUN echo '#!/bin/bash\ncd /opt/benchbase && java -jar benchbase.jar "$@"' > /usr/local/bin/benchbase && \
    chmod +x /usr/local/bin/benchbase
ENTRYPOINT ["bash", "-lc"]
