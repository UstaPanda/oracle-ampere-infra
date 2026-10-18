FROM ghcr.io/pelican-eggs/yolks:debian

RUN apt-get update && apt-get install -y --no-install-recommends wget tar ca-certificates && \
    wget https://github.com/graalvm/graalvm-ce-builds/releases/download/jdk-25.0.0/graalvm-community-jdk-25.0.0_linux-aarch64_bin.tar.gz -O /tmp/graalvm.tar.gz && \
    mkdir -p /opt/graalvm && \
    tar -xzf /tmp/graalvm.tar.gz -C /opt/graalvm --strip-components=1 && \
    rm /tmp/graalvm.tar.gz && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/opt/graalvm \
    PATH="/opt/graalvm/bin:${PATH}"
