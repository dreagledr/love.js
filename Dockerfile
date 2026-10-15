# Build environment for the love.js engine: emsdk 2.0.0 + Ninja + a modern CMake,
# plus the engine sources — so a build needs nothing but this repo.
#
#   docker build -t lovejs-build .
#   docker run --rm -v "$PWD:/work" lovejs-build ./build_lovejs.sh
#
# See the "Building" section of readme.md.

FROM emscripten/emsdk:2.0.0

# The buster cmake (3.13) is too old for this tree.
ARG CMAKE_VERSION=3.31.8
# The image has no ninja at all.
ARG NINJA_VERSION=1.12.1

RUN curl -fsSL -o /tmp/ninja.zip \
      "https://github.com/ninja-build/ninja/releases/download/v${NINJA_VERSION}/ninja-linux.zip" \
 && unzip -q /tmp/ninja.zip -d /usr/local/bin \
 && chmod +x /usr/local/bin/ninja \
 && rm /tmp/ninja.zip \
 && ninja --version

RUN curl -fsSL -o /tmp/cmake.tar.gz \
      "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz" \
 && tar -xzf /tmp/cmake.tar.gz -C /opt \
 && ln -sf /opt/cmake-${CMAKE_VERSION}-linux-x86_64/bin/cmake /usr/local/bin/cmake \
 && ln -sf /opt/cmake-${CMAKE_VERSION}-linux-x86_64/bin/ctest /usr/local/bin/ctest \
 && ln -sf /opt/cmake-${CMAKE_VERSION}-linux-x86_64/bin/cpack /usr/local/bin/cpack \
 && rm /tmp/cmake.tar.gz \
 && cmake --version

# The engine sources, with libs/love as a submodule. The .git directories are
# dropped: LÖVE's version comes from src/common/version.h, not from git.
#   docker build --build-arg MEGASOURCE_REF=<branch|tag> -t lovejs-build .
ARG MEGASOURCE_REPO=https://github.com/dreagledr/megasource.git
ARG MEGASOURCE_REF=emscripten-fetch
RUN git clone --recursive --branch "${MEGASOURCE_REF}" "${MEGASOURCE_REPO}" /opt/megasource \
 && rm -rf /opt/megasource/.git /opt/megasource/libs/love/.git \
 && test -f /opt/megasource/libs/love/CMakeLists.txt

# build_lovejs.sh picks both of these up on its own. To build a local checkout
# instead, mount it and override MEGASOURCE.
ENV EMSDK=/emsdk \
    MEGASOURCE=/opt/megasource

WORKDIR /work
CMD ["bash"]
