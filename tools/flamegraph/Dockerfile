FROM registry.cn-hangzhou.aliyuncs.com/library/ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      bash \
      git \
      linux-tools-common \
      linux-tools-generic \
      perl \
      wget \
    && rm -rf /var/lib/apt/lists/*

# 克隆FlameGraph工具
RUN git clone https://github.com/brendangregg/FlameGraph.git /opt/flamegraph

# 添加到PATH
RUN ln -sf /opt/flamegraph/stackcollapse-perf.pl /usr/local/bin/ \
    && ln -sf /opt/flamegraph/flamegraph.pl /usr/local/bin/ \
    && ln -sf /opt/flamegraph/stackcollapse-pgprof.pl /usr/local/bin/

WORKDIR /workspace

CMD ["bash"]
