ARG GOLANG_VERSION=1.17
FROM golang:${GOLANG_VERSION}-bullseye as builder

ARG IMAGINARY_VERSION=dev
ARG LIBVIPS_VERSION=8.12.2
ARG GOLANGCILINT_VERSION=1.29.0

# Installs libvips + required libraries
RUN sed -i s/deb.debian.org/mirrors.aliyun.com/g /etc/apt/sources.list && \
  sed -i s/security.debian.org/mirrors.aliyun.com/g /etc/apt/sources.list && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get update && \
  apt-get install --no-install-recommends -y \
  ca-certificates \
  automake build-essential curl \
  gobject-introspection gtk-doc-tools libglib2.0-dev libjpeg62-turbo-dev libpng-dev \
  libwebp-dev libtiff5-dev libgif-dev libexif-dev libxml2-dev libpoppler-glib-dev \
  swig libmagickwand-dev libpango1.0-dev libmatio-dev libopenslide-dev libcfitsio-dev \
  libgsf-1-dev fftw3-dev liborc-0.4-dev librsvg2-dev libimagequant-dev libheif-dev && \
  cd /tmp && \
  curl -fsSLO https://gh-proxy.com/github.com/libvips/libvips/releases/download/v${LIBVIPS_VERSION}/vips-${LIBVIPS_VERSION}.tar.gz && \
  tar zvxf vips-${LIBVIPS_VERSION}.tar.gz && \
  cd /tmp/vips-${LIBVIPS_VERSION} && \
        CFLAGS="-g -O3" CXXFLAGS="-D_GLIBCXX_USE_CXX11_ABI=0 -g -O3" \
    ./configure \
    --disable-debug \
    --disable-dependency-tracking \
    --disable-introspection \
    --disable-static \
    --enable-gtk-doc-html=no \
    --enable-gtk-doc=no \
    --enable-pyvips8=no && \
  make && \
  make install && \
  ldconfig

# Installing golangci-lint
WORKDIR /tmp

RUN curl -fsSL https://raw.githubusercontent.com/zhanghao1949/golangci-lint/master/install.sh | sh -s -- -b "${GOPATH}/bin" v${GOLANGCILINT_VERSION}

WORKDIR ${GOPATH}/src/github.com/h2non/imaginary

# Cache go modules
ENV GO111MODULE=on

COPY go.mod .
COPY go.sum .
RUN go env -w GOPROXY=https://goproxy.cn && \
    go mod download && \
    go get -u github.com/throttled/throttled/v2
# Copy imaginary sources
COPY . .

# Run quality control
# RUN go test ./... -test.v -race -test.coverprofile=atomic .
# RUN golangci-lint run .

# Compile imaginary
RUN go env -w GOPROXY=https://goproxy.cn && \
    go get -u github.com/throttled/throttled/v2 && \
    go get -u github.com/throttled/throttled/v2/store/memstore && \
    go build -a \
    -o ${GOPATH}/bin/imaginary \
    -ldflags="-s -w -h -X main.Version=${IMAGINARY_VERSION}" \
    github.com/h2non/imaginary

FROM debian:bullseye-slim

ARG IMAGINARY_VERSION

LABEL maintainer="tomas@aparicio.me" \
      org.label-schema.description="Fast, simple, scalable HTTP microservice for high-level image processing with first-class Docker support" \
      org.label-schema.schema-version="1.0" \
      org.label-schema.url="https://github.com/h2non/imaginary" \
      org.label-schema.vcs-url="https://github.com/h2non/imaginary" \
      org.label-schema.version="${IMAGINARY_VERSION}"

COPY --from=builder /usr/local/lib /usr/local/lib
COPY --from=builder /go/bin/imaginary /usr/local/bin/imaginary
COPY --from=builder /etc/ssl/certs /etc/ssl/certs

# Install runtime dependencies
RUN sed -i s/deb.debian.org/mirrors.aliyun.com/g /etc/apt/sources.list && \
  sed -i s/security.debian.org/mirrors.aliyun.com/g /etc/apt/sources.list && \
  DEBIAN_FRONTEND=noninteractive \
  apt update && \
  apt upgrade -y && \
  # apt install -y locales && \
  # sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
  # locale-gen && \
  apt -y install xfonts-utils fontconfig fonts-wqy-zenhei && \
  cd /usr/share/fonts && mkfontscale && mkfontdir && fc-cache && \
  apt-get install --no-install-recommends -y \
  procps libglib2.0-0 libjpeg62-turbo libpng16-16 libopenexr25 \
  libwebp6 libwebpmux3 libwebpdemux2 libtiff5 libgif7 libexif12 libxml2 libpoppler-glib8 \
  libmagickwand-6.q16-6 libpango1.0-0 libmatio11 libopenslide0 libjemalloc2 \
  libgsf-1-114 fftw3 liborc-0.4-0 librsvg2-2 libcfitsio9 libimagequant0 libheif1 && \
  ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
  apt-get autoremove -y && \
  apt-get autoclean && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ENV LC_ALL=en_US.utf8
# ENV LANG=en_US.utf8
# ENV LANGUAGE=en_US.utf8

ENV LD_PRELOAD=/usr/local/lib/libjemalloc.so

# Server port to listen
ENV PORT 9000

# Drop privileges for non-UID mapped environments
USER nobody

# Run the entrypoint command by default when the container starts.
ENTRYPOINT ["/usr/local/bin/imaginary"]

# Expose the server TCP port
EXPOSE ${PORT}
