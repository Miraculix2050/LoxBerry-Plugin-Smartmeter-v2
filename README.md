# SmartMeter v2 for LoxBerry

SmartMeter v2 is a LoxBerry plugin for reading smart meters with optical I/R reading heads. It provides meter values through the plugin web frontend and can forward them by HTTP, UDP, and MQTT depending on the selected configuration.

The `master` branch and its documentation describe the currently implemented development state. For documentation matching an installed release, select that version under [Releases](https://github.com/Miraculix2050/LoxBerry-Plugin-Smartmeter-v2/releases) or [Tags](https://github.com/Miraculix2050/LoxBerry-Plugin-Smartmeter-v2/tags). Planned but unimplemented behavior is not documented as current.

The standard implementation uses the external `vzlogger` package. The plugin generates `vzlogger.conf`, consumes selected vzLogger MQTT channels, and maintains an in-process value set for optional HTTP-cache writes and UDP sends. Only enabled HTTP output writes the RAM-backed `.data` files read by the HTTP endpoint.

The legacy reader remains available for existing installations and meter setups that are not covered by vzLogger yet.

## Documentation

- [English user guide](docs/User-Guide.en.md)
- [Deutsche Benutzerdokumentation](docs/User-Guide.de.md)
- [User documentation](docs/Readme.md)
- [Developer documentation](https://github.com/Miraculix2050/LoxBerry-Plugin-Smartmeter-v2/blob/master/docs/development/README.md)

## Main Features

- Detects optical I/R reading heads below `/dev/serial/smartmeter/`.
- Generates and validates vzLogger configuration files.
- Supports vzLogger MQTT publishing with a local SmartMeter cache.
- Provides optional HTTP `.data` cache output and UDP output from the same ordered bridge value set.
- Includes a bridge service for MQTT-to-cache processing.
- Provides diagnostic logging for service state, generated config, channel mapping, bridge logs, cache files, and MQTT parser samples.

## Quick Links

- Standard source topics: `<base topic>/vzlogger/...`
- Optional standard bridge output: `<base topic>/bridge`
- Legacy output only: `<base topic>/<meter>/<value name>`
- Default base topic: `smartmeter`
- UDP sends the same value set to all configured Miniservers.
- HTTP access remains available through the plugin web frontend.
- vzLogger live readings can optionally be opened through the local vzLogger HTTP daemon.

## Release Notes

See [CHANGELOG.md](CHANGELOG.md) for notable changes and release notes.

## Known Issues

See [Known Issues](docs/known-limitations.md) for confirmed limitations, security exceptions, and compatibility follow-up work.
