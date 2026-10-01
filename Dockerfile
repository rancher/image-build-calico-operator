ARG GO_IMAGE=rancher/hardened-build-base:v1.27.1b1
ARG BCI_IMAGE=registry.suse.com/bci/bci-nano:16.0

# Image that provides cross compilation tooling.
FROM --platform=$BUILDPLATFORM rancher/mirrored-tonistiigi-xx:1.6.1 AS xx

FROM --platform=$BUILDPLATFORM ${GO_IMAGE} AS builder
# copy xx scripts to the build stage
COPY --from=xx / /
RUN apk add --no-cache file make git clang llvm lld curl
ARG TARGETPLATFORM
ARG TARGETARCH
ARG BUILDARCH
RUN set -x && xx-apk --no-cache add musl-dev gcc lld

ARG PKG=github.com/tigera/operator
ARG TAG
RUN git clone --depth=1 https://${PKG}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
RUN go mod download

# Fetch the archives embedded by upstream. Read their versions from the checked-out
# Makefile so changing TAG also changes the required build inputs.
RUN set -eu; \
    istio_version="$(sed -nE 's/^ISTIO_VERSION[[:space:]]*\?=[[:space:]]*([^[:space:]#]+).*/\1/p' Makefile | head -n1)"; \
    gateway_version="$(sed -nE 's/^ENVOY_GATEWAY_VERSION[[:space:]]*\?=[[:space:]]*([^[:space:]#]+).*/\1/p' Makefile | head -n1)"; \
    helm_version="$(sed -nE 's/^HELM3_VERSION[[:space:]]*=[[:space:]]*([^[:space:]#]+).*/\1/p' Makefile | head -n1)"; \
    test -n "$istio_version" && test -n "$gateway_version" && test -n "$helm_version"; \
    for chart in base istiod cni ztunnel; do \
        curl -fsSL -o "pkg/render/istio/$chart.tgz" \
            "https://istio-release.storage.googleapis.com/charts/$chart-$istio_version.tgz"; \
    done; \
    curl -fsSL "https://get.helm.sh/helm-$helm_version-linux-$BUILDARCH.tar.gz" | \
        tar -xzOf - "linux-$BUILDARCH/helm" > /usr/local/bin/helm; \
    chmod +x /usr/local/bin/helm; \
    helm pull oci://docker.io/envoyproxy/gateway-helm \
        --version "$gateway_version" \
        --destination pkg/render/gatewayapi; \
    mv "pkg/render/gatewayapi/gateway-helm-$gateway_version.tgz" \
        pkg/render/gatewayapi/gateway-helm.tgz

# cross-compilation setup
ARG TARGETARCH
RUN set -eu; \
    build_version="$(git describe --tags --dirty --always --abbrev=12)"; \
    xx-go --wrap; \
    GO_LDFLAGS="-X github.com/tigera/operator/version.VERSION=$build_version" go-build-static.sh \
        -buildvcs=false \
        -tags=osusergo,netgo \
        -gcflags=-trimpath=${GOPATH}/src \
        -o /usr/local/bin/operator ./cmd; \
    if [ "$TARGETARCH" = "amd64" ]; then \
        go-assert-boring.sh /usr/local/bin/operator; \
    fi; \
    xx-verify --static /usr/local/bin/operator; \
    llvm-strip /usr/local/bin/operator

FROM ${BCI_IMAGE} AS hardened-calico-operator
LABEL org.opencontainers.image.description="Calico operator (Tigera operator)"
COPY --from=builder /usr/local/bin/operator /operator
ENTRYPOINT ["/operator"]
