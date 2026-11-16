# Cloud Agent base image for Tashil Data Sharing.
# Heavy, version-pinned toolchains live here so environment builds snapshot them.
# Lockfile sync (pub get, go mod download, npm ci) stays in .cursor/install.sh.
#
# Pins match CI: Flutter 3.41.2 (.github/workflows), Go 1.26.0 (backend-go/go.mod),
# Node 22.23.4 (Playwright smoke uses Node 22), Playwright 1.65.0 (e2e/package-lock.json).

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    HOME=/home/ubuntu \
    FLUTTER_VERSION=3.41.2 \
    FLUTTER_SHA256=4a04f8a6152986d14fc137ffaf98106ca743c0f9ab66f1bc2f20ee84eb573e5c \
    GO_VERSION=1.26.0 \
    GO_SHA256=aac1b08a0fb0c4e0a7c1555beb7b59180b05dfc5a3d62e40e9de90cd42f88235 \
    NODE_VERSION=22.23.4 \
    NODE_SHA256=1805bcd35e6815559bd2eb97db438d3fdb0eb3a5e6a977b7c1badca76337e9ce \
    PLAYWRIGHT_VERSION=1.65.0 \
    GOTOOLCHAIN=local \
    PUB_CACHE=/home/ubuntu/.pub-cache \
    PATH=/opt/flutter/bin:/usr/local/go/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        unzip \
        xz-utils \
        zip \
        python3 \
        build-essential \
        pkg-config \
        openjdk-21-jre-headless \
        sudo \
        libglu1-mesa \
        xvfb \
        fonts-noto-color-emoji \
        fonts-unifont \
        libfontconfig1 \
        libfreetype6 \
        xfonts-cyrillic \
        xfonts-scalable \
        fonts-liberation \
        fonts-ipafont-gothic \
        fonts-wqy-zenhei \
        fonts-tlwg-loma-otf \
        fonts-freefont-ttf \
        libasound2t64 \
        libatk-bridge2.0-0t64 \
        libatk1.0-0t64 \
        libatspi2.0-0t64 \
        libcairo2 \
        libcups2t64 \
        libdbus-1-3 \
        libdrm2 \
        libgbm1 \
        libglib2.0-0t64 \
        libnspr4 \
        libnss3 \
        libpango-1.0-0 \
        libx11-6 \
        libxcb1 \
        libxcomposite1 \
        libxdamage1 \
        libxext6 \
        libxfixes3 \
        libxkbcommon0 \
        libxrandr2 \
    && rm -rf /var/lib/apt/lists/* \
    && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu \
    && chmod 440 /etc/sudoers.d/ubuntu

RUN curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" -o /tmp/node.tar.xz \
    && echo "${NODE_SHA256}  /tmp/node.tar.xz" | sha256sum -c - \
    && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 --no-same-owner \
    && rm /tmp/node.tar.xz \
    && node --version \
    && npm --version

RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tgz \
    && echo "${GO_SHA256}  /tmp/go.tgz" | sha256sum -c - \
    && rm -rf /usr/local/go \
    && tar -xzf /tmp/go.tgz -C /usr/local --no-same-owner \
    && rm /tmp/go.tgz \
    && ln -sf /usr/local/go/bin/go /usr/local/bin/go \
    && ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt \
    && go version

RUN curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o /tmp/flutter.tar.xz \
    && echo "${FLUTTER_SHA256}  /tmp/flutter.tar.xz" | sha256sum -c - \
    && rm -rf /opt/flutter \
    && tar -xJf /tmp/flutter.tar.xz -C /opt --no-same-owner \
    && rm /tmp/flutter.tar.xz \
    && ln -sf /opt/flutter/bin/flutter /usr/local/bin/flutter \
    && ln -sf /opt/flutter/bin/dart /usr/local/bin/dart \
    && git config --system --add safe.directory /opt/flutter \
    && chown -R ubuntu:ubuntu /opt/flutter /home/ubuntu

USER ubuntu

# Precache web (the stable tarball also carries the host flutter_tester) so
# later `flutter analyze` / `flutter test` do not download the SDK again.
# Flutter 3.41 records the opt-out in ~/.dart-tool/dart-flutter-telemetry.config.
RUN flutter config --no-analytics --no-cli-animations \
    && flutter --disable-analytics \
    && flutter precache --web \
    && flutter --version \
    && grep -q '^reporting=0$' "$HOME/.dart-tool/dart-flutter-telemetry.config"
