ARG BCI_IMAGE=registry.suse.com/bci/bci-base:15.3.17.20.12
ARG GO_IMAGE=rancher/hardened-build-base:v1.20.3b1
FROM ${BCI_IMAGE} as bci
FROM ${GO_IMAGE} as builder
ARG ARCH="amd64"
ARG GOOS="linux"
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
RUN if [ "${ARCH}" == "s390x" ]; then \
        curl -LO https://github.com/google/protobuf/releases/download/v3.17.3/protoc-3.17.3-linux-s390_64.zip; \
        unzip protoc-3.17.3-linux-s390_64.zip -d /usr; \
    else \
        curl -LO https://github.com/google/protobuf/releases/download/v3.17.3/protoc-3.17.3-linux-x86_64.zip; \
        unzip protoc-3.17.3-linux-x86_64.zip -d /usr; \
    fi
# setup containerd build
ARG SRC="github.com/k3s-io/containerd"
ARG PKG="github.com/containerd/containerd"
ARG TAG="v1.6.19-k3s1"
RUN git clone --depth=1 https://${SRC}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git fetch --tags --depth=1 origin ${TAG}
RUN git checkout tags/${TAG} -b ${TAG}
RUN export GO_LDFLAGS="-linkmode=external \
    -X ${PKG}/version.Version=${TAG} \
    -X ${PKG}/version.Package=${SRC} \
    -X ${PKG}/version.Revision=$(git rev-parse HEAD) \
    " \
 && export GO_BUILDTAGS="apparmor,seccomp,selinux,static_build,netgo,osusergo" \
 && export GO_BUILDFLAGS="-gcflags=-trimpath=${GOPATH}/src -tags=${GO_BUILDTAGS}" \
 && go-build-static.sh ${GO_BUILDFLAGS} -o bin/ctr                      ./cmd/ctr \
 && go-build-static.sh ${GO_BUILDFLAGS} -o bin/containerd               ./cmd/containerd \
 && go-build-static.sh ${GO_BUILDFLAGS} -o bin/containerd-stress        ./cmd/containerd-stress \
 && go-build-static.sh ${GO_BUILDFLAGS} -o bin/containerd-shim          ./cmd/containerd-shim \
 && go-build-static.sh ${GO_BUILDFLAGS} -o bin/containerd-shim-runc-v1  ./cmd/containerd-shim-runc-v1 \
 && go-build-static.sh ${GO_BUILDFLAGS} -o bin/containerd-shim-runc-v2  ./cmd/containerd-shim-runc-v2
RUN go-assert-static.sh bin/*
RUN if [ "${ARCH}" != "s390x" ]; then \
        go-assert-boring.sh \
        bin/ctr \
        bin/containerd; \
    fi
RUN install -s bin/* /usr/local/bin
RUN containerd --version

FROM bci
COPY --from=builder /usr/local/bin/ /usr/local/bin/
