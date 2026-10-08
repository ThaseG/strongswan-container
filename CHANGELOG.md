# Change Log
All notable changes to this project will be documented in this file.

| Version | Release Date | Release Notes | Fixed | Known bugs |
| ------- | ------------ | ------------- | ----- | ---------- |
| v0.0.3  | 2026-10-07   | **StrongSwan Version**: 6.1.0 </br> **StrongSwan-exporter Version**: v1.0.0 </br> **Golang Version**: 1.25 </br> **Ubuntu Version**: 26.04 </br> StrongSwan is built from the SHA-256 verified release tarball; build and runtime stages share the same Ubuntu base. Entrypoint loads swanctl connections, handles shutdown signals and survives container restarts. New e2e test suite (bats) with per-test results published in GitHub, run against Debian 12/13 and Ubuntu 22.04/24.04/26.04 clients. Trivy runs from the latest official container image. | StrongSwan 6.1.0 fixes multiple CVEs present in 6.0.x. VICI socket path and exporter config are consistent. Removed unused build dependencies, the `VOLUME` declaration and the unused `strongswan` user. Debian 11 (bullseye) test client removed after its end of life. | E2E suite not yet confirmed passing in CI. |
| v0.0.1  | 2025-12-10   | **StrongSwan Version**: 6.0.3 </br> **Ubuntu Version**: 24.04 </br> This is a first release of this container, we are still working on improvements and tests. | Nothing | No |
