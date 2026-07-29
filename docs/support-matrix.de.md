# Getestete Supportmatrix

`LB_MINIMUM` und uneingeschränkte Architekturmetadaten sind Installationsgrenzen, aber kein Nachweis, dass jedes zulässige System getestet wurde. Diese Matrix enthält nur das jüngste reproduzierbare Ergebnis auf `LoxBerry-TEST`.

| Geprüft | Repository-Commit | Plugin | LoxBerry | Betriebssystem | Architektur | vzLogger | Browser |
|---|---|---|---|---|---|---|---|
| 2026-07-25 | `f2b410ce` | `2.0.0.32` | `4.0.0.13` | Debian 13/trixie | arm64 | `0.8.9` aus dem konfigurierten Cloudsmith-Repository | Firefox und Chrome; genaue Versionen nicht erfasst |

Der Zielgerätetest umfasste Update, Deaktivierung/Reaktivierung, Deinstallation, Neuinstallation, Dienstbetrieb, SML/MQTT-Datenfluss, berechnete Leistung, HTTP-Cache und UDP-Ausgabe. Die Tabelle wird nur nach einem passenden Zielgerätelauf aktualisiert. Tests eines nicht eingecheckten Arbeitsstands ersetzen den erfassten Commit nicht.

Andere LoxBerry- oder Betriebssystemversionen und andere CPU-Architekturen sind nicht gerätegetestet. Erwartete Kompatibilität beruht dort auf den dokumentierten LoxBerry-V4-, POSIX-Shell-, Abhängigkeits- und Portabilitätsverträgen sowie Code-Review und ist keine getestete Supportzusage. Repository-Verfügbarkeit und Root-Hook-Verhalten außerhalb der erfassten Plattform sind nicht bestätigt.
