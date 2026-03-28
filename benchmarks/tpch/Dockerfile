FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential ca-certificates git make gawk sed \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN git clone https://github.com/gregrahn/tpch-kit.git /opt/tpch-kit \
    && cd /opt/tpch-kit/dbgen \
    && make MACHINE=LINUX DATABASE=POSTGRESQL

ENTRYPOINT ["bash", "-lc"]
