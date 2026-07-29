# SmartMeter v2 for LoxBerry

SmartMeter v2 reads smart meters through optical I/R reading heads on LoxBerry. The standard implementation uses vzLogger; a separate Legacy implementation remains available for existing configurations.

SmartMeter v2 liest Smart Meter über optische I/R-Leseköpfe am LoxBerry aus. Standardmäßig kommt vzLogger zum Einsatz; für bestehende Konfigurationen bleibt eine getrennte Legacy-Implementierung verfügbar.

## User documentation / Benutzerdokumentation

- [English user guide](docs/User-Guide.en.md)
- [Deutsche Benutzerdokumentation](docs/User-Guide.de.md)
- [Documentation index / Dokumentationsübersicht](docs/Readme.md)
- [Known limitations / Bekannte Einschränkungen](docs/known-limitations.md)
- [Tested platforms / Geprüfte Plattformen](docs/support-matrix.md)

The documentation on `master` describes the current development tree. Use the documentation linked from an installed release for version-specific instructions.

Die Dokumentation auf `master` beschreibt den aktuellen Entwicklungsstand. Verwende für versionsgenaue Anweisungen die von der installierten Version verlinkte Dokumentation.

## Main features / Hauptfunktionen

- Detection of reading heads below `/dev/serial/smartmeter/`
- Guided SML, D0, and OMS configuration plus custom JSONC
- OBIS discovery and channel selection
- Live readings and browser-local charts
- MQTT, optional HTTP-cache, and UDP output
- Direct vzLogger targets for Volkszähler, InfluxDB, and MySmartGrid
- Reversible Legacy fallback

## Development

- [Developer documentation](docs/development/README.md)
- [Changelog](CHANGELOG.md)
