# The image uses the package built on this machine, including its shared libraries.
FROM archlinux:latest
ARG LLAMA_SHA
LABEL org.opencontainers.image.source="https://github.com/delfianto/llama-cpp-build" \
      org.opencontainers.image.revision="$LLAMA_SHA"
RUN pacman -Syu --noconfirm cuda nccl openssl && pacman -Scc --noconfirm
COPY .cache/docker/llama.cpp-cuda-git-*.pkg.tar.zst /tmp/packages/
RUN pacman -U --noconfirm /tmp/packages/*.pkg.tar.zst && rm -rf /tmp/packages
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
