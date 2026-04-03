FROM docker.1ms.run/eclipse-temurin:21-jdk AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    gcc \
    make \
    automake \
    libtool \
    pkg-config \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone https://github.com/akopytov/sysbench.git
WORKDIR /src/sysbench
RUN ./autogen.sh && \
    ./configure --without-mysql --with-pgsql && \
    make -j$(nproc) && \
    make install

FROM docker.1ms.run/eclipse-temurin:21-jre

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bin/sysbench /usr/local/bin/
COPY --from=builder /usr/local/share/sysbench /usr/local/share/sysbench

WORKDIR /workspace
ENTRYPOINT ["sysbench"]
