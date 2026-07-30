# SmartMeter v2 Benutzerdokumentation

- **Zielgruppe:** LoxBerry-Nutzer, auch ohne Linux- oder vzLogger-Vorkenntnisse
- **Status:** Dokumentation der Repository- oder Pluginversion, über die diese Seite geöffnet wurde

## Überblick

SmartMeter v2 liest Zählerdaten über einen optischen I/R-Lesekopf mit vzLogger. vzLogger veröffentlicht Messwerte per MQTT. Die optionale SmartMeter-Bridge kann daraus MQTT-Zeitstempel, einen HTTP-Cache und UDP-Daten für Loxone erzeugen.

> **Sicherheit:** Verwende LoxBerry, den vzLogger-HTTP-Dienst, den SmartMeter-HTTP-Cache und den Recovery-Endpunkt nur in einem vertrauenswürdigen LAN. Gib diese Dienste niemals über den Router oder einen öffentlichen Reverse-Proxy ins Internet frei.

## Schnellstart

1. Prüfe die [Voraussetzungen und bekannten Einschränkungen](user/de/installation.md#voraussetzungen).
2. Lade das offizielle ZIP der gewünschten Version von [GitHub Releases](https://github.com/Miraculix2050/LoxBerry-Plugin-Smartmeter-v2/releases) und installiere es über die LoxBerry-Pluginverwaltung.
3. Schließe den Lesekopf an und öffne **SmartMeter v2**. Die Seite **vzLogger-Konfiguration** erscheint.
4. Schalte **vzLogger aktiv** ein und wähle **Nach I/R-Leseköpfen suchen**.
5. Öffne den Lesekopf, wähle SML, D0 oder OMS und initialisiere ihn bei Bedarf aus einer passenden Vorlage.
6. Wähle **Speichern und anwenden**. Erst danach darf die OBIS-Suche auf den Lesekopf zugreifen.
7. Starte **OBIS-Kanäle auslesen**, aktiviere die gewünschten Kanäle und wähle bei Bedarf **In SmartMeter ausgeben**.
8. Aktiviere die gewünschten Bridge-Ausgaben und wähle erneut **Speichern und anwenden**.
9. Öffne **Live-Daten als Webseite** und prüfe, ob aktuelle Werte erscheinen.

Eine ausführliche Erklärung steht unter [Konfiguration](user/de/configuration.md).

## Dokumentation nach Aufgabe

- [Installation, Update und Deinstallation](user/de/installation.md)
- [vzLogger konfigurieren](user/de/configuration.md)
- [Messwerte und Ausgaben verwenden](user/de/outputs.md)
- [Erweiterte Funktionen](user/de/advanced.md)
- [Fehler beheben](user/de/troubleshooting.md)
- [Technische Referenz](user/de/reference.md)
- [Bekannte Einschränkungen](known-limitations.de.md)
- [Geprüfte Supportmatrix](support-matrix.de.md)

## Kurz erklärt

- **I/R-Lesekopf:** Optischer Adapter am Zähler. LoxBerry stellt erkannte Geräte unter `/dev/serial/smartmeter/` bereit.
- **SML, D0, OMS:** Protokolle, mit denen unterschiedliche Zähler ihre Daten übertragen.
- **OBIS:** Standardisierte Kennung für einen Messwert, zum Beispiel `1-0:1.8.0` für bezogene Energie.
- **vzLogger:** Externes Programm, das den Zähler liest und Messwerte veröffentlicht.
- **SmartMeter-Bridge:** Optionaler Plugin-Dienst, der ausgewählte vzLogger-MQTT-Werte für MQTT-Zeitstempel, HTTP-Cache und UDP verarbeitet.
- **Channel/Kanal:** Konfiguration eines einzelnen Messwerts.
