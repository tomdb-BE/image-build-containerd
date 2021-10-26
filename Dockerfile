ARG UBI_IMAGE
ARG GO_IMAGE
FROM ${UBI_IMAGE} as ubi
FROM ${GO_IMAGE} as builder
ARG PROTOC_VERSION=1.17.3
ARG ARCH=amd64
# setup required packages
RUN set -x \
 && apk --no-cache add \
    btrfs-progs-dev \
    btrfs-progs-static \
    file \
    gcc \
    git \
    libselinux-dev \
    libseccomp-dev \
    libseccomp-static \
    make \
    mercurial \
    subversion \
    unzip
RUN archurl=x86_64; if [[ "$ARCH" == "arm64" ]]; then archurl=aarch_64; fi; wget https://github.com/google/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-$archurl.zip
RUN archurl=x86_64; if [[ "$ARCH" == "arm64" ]]; then archurl=aarch_64; fi; unzip protoc-${PROTOC_VERSION}-linux-$archurl.zip -d /usr
# setup containerd build
ARG SRC="github.com/k3s-io/containerd"
ARG PKG="github.com/containerd/containerd"
ARG TAG="v1.4.9-k3s1"
RUN git clone --depth=1 https://${SRC}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
ENV GO_BUILDTAGS="apparmor,seccomp,selinux,static_build,netgo,osusergo"
ENV GO_BUILDFLAGS="-gcflags=-trimpath=${GOPATH}/src -tags=${GO_BUILDTAGS}"
RUN go mod edit --replace google.golang.org/grpc=google.golang.org/grpc@v1.27.1 && go mod tidy && test -d vendor && go mod vendor || true
RUN export GO_LDFLAGS="-linkmode=external \
    -X ${PKG}/version.Version=${TAG} \
    -X ${PKG}/version.Package=${SRC} \
    -X ${PKG}/version.Revision=$(git rev-parse HEAD) \
    " \
 && go-build-static.sh ${GO_BUILDFLAGS} -o bin/ctr                      ./cmd/ctr \
 && go-build-static.sh ${GO_BUILDFLAGS} -o bin/containerd               ./cmd/containerd \
 && go-build-static.sh ${GO_BUILDFLAGS} -o bin/containerd-stress        ./cmd/containerd-stress \
 && go-build-static.sh ${GO_BUILDFLAGS} -o bin/containerd-shim          ./cmd/containerd-shim \
 && go-build-static.sh ${GO_BUILDFLAGS} -o bin/containerd-shim-runc-v1  ./cmd/containerd-shim-runc-v1 \
 && go-build-static.sh ${GO_BUILDFLAGS} -o bin/containerd-shim-runc-v2  ./cmd/containerd-shim-runc-v2
RUN go-assert-static.sh bin/*
RUN go-assert-boring.sh \
    bin/ctr \
    bin/containerd
RUN install -s bin/* /usr/local/bin
RUN containerd --version

FROM ubi
COPY --from=builder /usr/local/bin/ /usr/local/bin/
