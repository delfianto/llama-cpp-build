# Guides

Run commands from the repository root unless a guide says otherwise.

| Guide | What it covers |
| --- | --- |
| [Docker and Compose](docker.md) | Host setup, image builds, model mounts, vision, GPU selection, API checks, updates, troubleshooting |
| [Native builds and operation](build-and-run.md) | Build flags, package installation, source versions, systemd, build output, cleanup |
| [Experimental patch candidates](patch-candidates.md) | Research, applicability checks, workload restrictions, and a proposed test order |

Start with Docker if the server will run in a container. Start with native builds if it will run directly on the host. Both use the same Zen 5/CUDA package and the flags in [arch/build-config.sh](../arch/build-config.sh).

The verified baseline is recorded in the [main README](../README.md). The patch guide is research; its candidates are not enabled by default.
