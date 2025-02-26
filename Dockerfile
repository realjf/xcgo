# This neilotoole/xcgo Dockerfile builds a maximalist Go/Golang CGo-enabled
# cross-compiling image It can build CGo apps on macOS, Linux, and Windows.
# It also contains supporting tools such as docker and snapcraft.
# See https://github.com/neilotoole/xcgo
ARG OSX_SDK="MacOSX11.3.sdk"
ARG OSX_CODENAME="catalina"
ARG OSX_VERSION_MIN="10.9"
ARG OSX_SDK_BASEURL="https://github.com/neilotoole/xcgo/releases/download/v0.1"
ARG OSX_SDK_PATH="./MacOSX_SDKs/"
ARG OSX_SDK_SUM="d97054a0aaf60cb8e9224ec524315904f0309fbbbac763eb7736bdfbdad6efc8"
ARG OSX_CROSS_COMMIT="50e86ebca7d14372febd0af8cd098705049161b9"
ARG LIBTOOL_VERSION="2.4.6_1"
ARG LIBTOOL_BASEURL="https://github.com/neilotoole/xcgo/releases/download/v0.1"
ARG LIBTOOL_PATH="./libtool/"
ARG GOLANGCI_LINT_VERSION="1.42.1"
ARG GORELEASER_VERSION="0.182.1"
ARG GO_VERSION=""
ARG UBUNTU=bionic
ARG DISABLE_GIT_SSL="git config --global http.sslVerify false"
ARG GIT="git"
ARG TIMEZONE="Asia/Shanghai"



####################  snapbuilder ####################
FROM ubuntu:${UBUNTU} AS snapbuilder
ARG UBUNTU
# We build from ubuntu because we need snapcraft. It's difficult
# to build, say, a Debian-based image with snapcraft included. Note also that
# the snapcore/snapcraft images are based upon ubuntu:xenial, but we
# want ubuntu:bionic (some things we want, e.g. go1.14, don't have good
# packages for xenial at the time of writing).

# This section lifted from snapcore/snapcraft:stable
# Grab dependencies
RUN apt-get update && apt-get dist-upgrade -y && apt-get install -y \
    curl \
    jq \
    lsb-core \
    squashfs-tools


# Grab the core snap (for backwards compatibility) from the stable channel and
# unpack it in the proper place.
RUN curl -L $(curl -H 'X-Ubuntu-Series: 16' 'https://api.snapcraft.io/api/v1/snaps/details/core' | jq '.download_url' -r) --output core.snap
RUN mkdir -p /snap/core
RUN unsquashfs -d /snap/core/current core.snap

# Grab the core18 snap (which snapcraft uses as a base) from the stable channel
# and unpack it in the proper place.
RUN curl -L $(curl -H 'X-Ubuntu-Series: 16' 'https://api.snapcraft.io/api/v1/snaps/details/core18' | jq '.download_url' -r) --output core18.snap
RUN mkdir -p /snap/core18
RUN unsquashfs -d /snap/core18/current core18.snap

# Grab the snapcraft snap from the stable channel and unpack it in the proper
# place.
RUN curl -L $(curl -H 'X-Ubuntu-Series: 16' 'https://api.snapcraft.io/api/v1/snaps/details/snapcraft?channel=stable' | jq '.download_url' -r) --output snapcraft.snap
RUN mkdir -p /snap/snapcraft
RUN unsquashfs -d /snap/snapcraft/current snapcraft.snap

# Create a snapcraft runner
RUN mkdir -p /snap/bin
RUN echo "#!/bin/sh" > /snap/bin/snapcraft
RUN snap_version="$(awk '/^version:/{print $2}' /snap/snapcraft/current/meta/snap.yaml)" && echo "export SNAP_VERSION=\"$snap_version\"" >> /snap/bin/snapcraft
RUN echo 'exec "$SNAP/usr/bin/python3" "$SNAP/bin/snapcraft" "$@"' >> /snap/bin/snapcraft
RUN chmod +x /snap/bin/snapcraft

## Multi-stage build, only need the snaps from the builder. Copy them one at a
## time so they can be cached.
FROM ubuntu:$UBUNTU AS snapcore
COPY --from=snapbuilder /snap/core /snap/core
COPY --from=snapbuilder /snap/core18 /snap/core18
COPY --from=snapbuilder /snap/snapcraft /snap/snapcraft
COPY --from=snapbuilder /snap/bin/snapcraft /snap/bin/snapcraft

# Generate locale and install dependencies.
RUN apt-get update && apt-get dist-upgrade --yes && apt-get install --yes snapd sudo locales && locale-gen en_US.UTF-8

# dns server
COPY ./resolv.conf.override /etc/resolv.conf.override
RUN cp /etc/resolv.conf.override /etc/resolv.conf

# Set the proper environment.
ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"
ENV LC_ALL="en_US.UTF-8"
ENV PATH="/snap/bin:$PATH"
ENV SNAP="/snap/snapcraft/current"
ENV SNAP_NAME="snapcraft"
ENV SNAP_ARCH="amd64"

EXPOSE 1089/tcp
EXPOSE 8889/tcp


####################  golangcore  ####################
FROM snapcore AS golangcore
ARG GO_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    jq \
    lsb-core \
    software-properties-common

ENV GOPATH="/go"
ENV GIT_CURL_VERBOSE=1
ENV GIT_HTTP_MAX_REQUESTS=16
ENV GIT_TRACE=1
RUN git config --global http.postBuffer 524288000
RUN mkdir -p "${GOPATH}/src"

# As suggested here: https://github.com/golang/go/wiki/Ubuntu
RUN add-apt-repository -y ppa:longsleep/golang-backports
RUN if test -z "${GO_VERSION}"; then GO_VERSION=$(curl -k 'https://go.dev/VERSION?m=text'); fi && \
    curl -kL -o go.tar.gz https://go.dev/dl/${GO_VERSION}.linux-amd64.tar.gz && \
    rm -rf /usr/local/go && tar -C /usr/local -xzf go.tar.gz && \
    rm go.tar.gz
RUN ln -s /usr/local/go /usr/lib/go
RUN ln -s /usr/local/go/bin/go /usr/bin/go
RUN ln -s /usr/local/go/bin/gofmt /usr/bin/gofmt

RUN go version


####################  devtools  ####################
FROM golangcore AS devtools
# Dependencies for https://github.com/tpoechtrager/osxcross and some
# other stuff.
ARG TIMEZONE
RUN sed -i "s/# deb-src/deb-src/g" /etc/apt/sources.list
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    clang \
    cmake \
    file \
    gcc-mingw-w64 gcc-mingw-w64-i686 gcc-mingw-w64-x86-64 \
    less \
    libc6-dev \
    libc6-dev-i386 \
    libc++-dev  \
    libltdl-dev \
    libsqlite3-dev \
    libssl-dev \
    libxml2-dev \
    llvm \
    man \
    parallel \
    patch \
    sqlite3 \
    tree \
    vim \
    wget \
    xz-utils \
    zlib1g-dev  \
    zsh \
    fakeroot dpkg-dev debian-keyring

ENV TZ=${TIMEZONE}
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN mkdir ~/git-openssl
WORKDIR ~/git-openssl

RUN apt-get build-dep git --yes
RUN apt-get install libcurl4-openssl-dev --yes

RUN apt-get source git 

# We need to actually go into the git source directory
# find -type f -name "*.dsc" -exec dpkg-source -x \{\} \;
# This is where we actually change the library from one type to the other
# Compile time, itself, is long. Skips the tests. Do so at your own peril
# Build it.
# Install
RUN cd $(find -mindepth 1 -maxdepth 1 -type d -name "git-*") \
    && sed -i -- 's/libcurl4-gnutls-dev/libcurl4-openssl-dev/' ./debian/control \
    && sed -i -- '/TEST\s*=\s*test/d' ./debian/rules  \
    && dpkg-buildpackage -rfakeroot -b \
    && find .. -type f -name "git_*ubuntu*.deb" -exec sudo dpkg -i \{\} \;



####################  osx-cross  ####################
# See https://github.com/tpoechtrager/osxcross
FROM devtools AS osx-cross
ARG OSX_SDK
ARG OSX_CODENAME
ARG OSX_SDK_BASEURL
ARG OSX_SDK_PATH
ARG OSX_SDK_SUM
ARG OSX_CROSS_COMMIT
ARG OSX_VERSION_MIN
ARG LIBTOOL_VERSION
ARG LIBTOOL_BASEURL
ARG LIBTOOL_PATH
ARG GIT
ARG DISABLE_GIT_SSL
ENV OSX_CROSS_PATH=/osxcross

WORKDIR "${OSX_CROSS_PATH}"
RUN ${DISABLE_GIT_SSL}
RUN ${GIT} clone https://github.com/tpoechtrager/osxcross.git .  --verbose
RUN ${GIT} checkout -q "${OSX_CROSS_COMMIT}" 
RUN rm -rf ./.git

RUN mkdir -p "${OSX_CROSS_PATH}/tarballs"
# RUN  curl -fsSviL "${OSX_SDK_BASEURL}/${OSX_SDK}.tar.xz" -o "${OSX_CROSS_PATH}/tarballs/${OSX_SDK}.tar.xz"
COPY "${OSX_SDK_PATH}${OSX_SDK}.tar.xz" "${OSX_CROSS_PATH}/tarballs/${OSX_SDK}.tar.xz"
#RUN xz -d -k "${OSX_CROSS_PATH}/tarballs/${OSX_SDK}.tar.xz"
# RUN echo "${OSX_SDK_SUM}"  "${OSX_CROSS_PATH}/tarballs/${OSX_SDK}.tar.xz" | sha256sum -c -
RUN git config --global core.compression 0
RUN UNATTENDED=yes OSX_VERSION_MIN=${OSX_VERSION_MIN} OCDEBUG=1 ./build.sh

RUN mkdir -p "${OSX_CROSS_PATH}/target/SDK/${OSX_SDK}/usr/"
# RUN  curl -fsSviL "${LIBTOOL_BASEURL}/libtool-${LIBTOOL_VERSION}.${OSX_CODENAME}.bottle.tar.gz"
COPY "${LIBTOOL_PATH}/libtool-${LIBTOOL_VERSION}.${OSX_CODENAME}.bottle.tar.gz" "${OSX_CROSS_PATH}/tarballs/libtool-${LIBTOOL_VERSION}.${OSX_CODENAME}.bottle.tar.gz"
RUN gzip -dc "${OSX_CROSS_PATH}/tarballs/libtool-${LIBTOOL_VERSION}.${OSX_CODENAME}.bottle.tar.gz" | tar xf - \
    -C "${OSX_CROSS_PATH}/target/SDK/${OSX_SDK}/usr/" \
    --strip-components=2 \
    "libtool/${LIBTOOL_VERSION}/include/" \
    "libtool/${LIBTOOL_VERSION}/lib/"

WORKDIR /root



####################  docker  ####################
FROM osx-cross AS docker

RUN apt-get update -y && apt-get install -y --no-install-recommends \
    apt-transport-https \
    ca-certificates \
    gnupg-agent


RUN  curl -fSvL "https://download.docker.com/linux/ubuntu/gpg" | apt-key add - && \
    add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) \
    stable"

RUN apt-get update && apt-get install -y docker-ce docker-ce-cli



####################  gotools  ####################
FROM docker AS gotools
# This section descended from https://github.com/mailchain/goreleaser-xcgo
# Much gratitude to the mailchain team.
ARG GORELEASER_VERSION
ARG GORELEASER_DOWNLOAD_FILE="goreleaser_Linux_x86_64.tar.gz"
ARG GORELEASER_DOWNLOAD_URL="https://github.com/goreleaser/goreleaser/releases/download/v${GORELEASER_VERSION}/${GORELEASER_DOWNLOAD_FILE}"
ARG GOLANGCI_LINT_VERSION
ARG GIT
ARG DISABLE_GIT_SSL

RUN  wget "${GORELEASER_DOWNLOAD_URL}"; \
    tar -xzf $GORELEASER_DOWNLOAD_FILE -C /usr/bin/ goreleaser; \
    rm $GORELEASER_DOWNLOAD_FILE;

# Add mage - https://magefile.org
RUN ${DISABLE_GIT_SSL}
RUN cd /tmp &&  ${GIT} clone https://github.com/magefile/mage.git  --verbose && cd mage && go run bootstrap.go && rm -rf /tmp/mage

# https://github.com/golangci/golangci-lint
RUN  curl -SfvL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(go env GOPATH)/bin "v${GOLANGCI_LINT_VERSION}"



####################  xcgo-final  ####################
FROM gotools AS xcgo-final
LABEL maintainer="neilotoole@apache.org"
ENV PATH=${OSX_CROSS_PATH}/target/bin:$PATH:${GOPATH}/bin
ENV CGO_ENABLED=1
ENV GOPROXY="https://goproxy.cn,direct"

WORKDIR /root
COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
