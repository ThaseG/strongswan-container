# StrongSwan Server Container Image

A production-ready StrongSwan server running in Docker with built-in monitoring and metrics export capabilities. Tests in pipelines are testing the versions of StrongSwan, exporter, and IPtables rules.

## Used Exporter

Exporter used in this project is from a dedicated [repository here.](https://github.com/ThaseG/strongswan-exporter)

## Features

- 🔒 StrongSwan 6.0.3 - Built from source for latest security features
- 🐳 Docker-based - Easy deployment and management
- 📊 Prometheus Metrics - Built-in StrongSwan exporter for monitoring
- 🔄 Dual Protocol Support - Run TCP and UDP instances simultaneously
- 🛡️ Security First - Runs as non-root user with minimal privileges
- 📝 Flexible Configuration - Easy to customize via mounted configs
- 🔧 iptables Support - Custom firewall rules support

## Configuration
### Required Files



### Configuration Structure

```

```

## License
MIT License - feel free to use and modify as needed.

## For more information:

 - the [CONTRIBUTING](./CONTRIBUTING.md) document describes how to contribute to the repository
 - in case of need, please contact owner group : [ThaseG](mailto:andrej@hyben.net)
 - see [Changelog](./CHANGELOG.md) for release information.
 - check [Upgrade procedure](./UPGRADE.md) to see how to create new openvpn container image.
 - check [Tests](./Tests.md) to see how automated tests works within this repository to verify version.
