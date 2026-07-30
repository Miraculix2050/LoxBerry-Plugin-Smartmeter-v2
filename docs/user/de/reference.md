# Technische Referenz

[← Fehlerbehebung](troubleshooting.md) · [Zurück zur Übersicht](../../User-Guide.de.md)

Diese Seite bündelt Details für Diagnose, Sicherung und fortgeschrittene Integration. Für die normale Einrichtung genügen [Konfiguration](configuration.md) und [Ausgaben](outputs.md).

## Dienste und Sollzustände

| Bestandteil | Aufgabe | Wann aktiv |
|---|---|---|
| `vzlogger` | Liest Meter und veröffentlicht Messwerte per MQTT | `VZLOGGER.ENABLED=1`, gültige Konfiguration, mindestens ein aktives Meter |
| `smartmeter-v2-vzlogger-bridge` | Erzeugt Bridge-MQTT, HTTP-Cache und UDP | Bridge aktiviert und nutzbare angewendete Ausgabe vorhanden |

Ein deaktivierter oder meterloser Zustand stoppt die zugehörigen Dienste, ohne eine gültige erzeugte Konfiguration zu löschen. Manuelle Aktionen Start, Stopp und Neustart ändern die gespeicherten Sollzustände nicht.

## Konfigurations- und Laufzeitpfade

`<plugin-folder>` ist der installierte Pluginordner und kann von einem Repositorynamen abweichen.

| Pfad | Bedeutung | Art |
|---|---|---|
| LoxBerry-Pluginkonfiguration `smartmeter.cfg` | Sollzustände, Meter-Einstellungen und Ausgabevorgaben | maßgebliche Benutzereinstellung |
| LoxBerry-Pluginkonfiguration `vzlogger.conf` | Angewendete vzLogger-Laufzeitkonfiguration | erzeugt, bei Updates erhalten |
| `vzlogger_expert.conf` im Plugin-Konfigurationsordner | Getrennter Expert-Mode-Entwurf | maßgebliche Benutzereinstellung im Expert Mode |
| `vzlogger_meter_<serial>.jsonc` | Benutzerdefiniertes Meterobjekt eines Lesekopfs | maßgebliche Benutzereinstellung |
| `vzlogger_channel_definitions.json` | Vollständiges UI-Modell aktiver und inaktiver Kanäle | maßgebliches Kanalmodell |
| `vzlogger_channels.json` | Aktive, von der Bridge verwendete Ausgabekanäle | aus der angewendeten Konfiguration erzeugt |
| `vzlogger_user_channel_uuids_<serial>.json` | Stabile UUID-Zuordnung benutzerdefinierter Kanäle | persistente Identitätszuordnung |
| `obis_channels_<serial>.cache` | Zuletzt gefundene OBIS-Identifier | persistenter, erneut erzeugbarer Suchstand |
| `smartmeter_recovery.json` | Recovery-Einstellungen und gehashter Token | maßgebliche Benutzereinstellung |
| `/var/run/shm/<plugin-folder>/` | Flüchtige Logs, laufende Discovery-Aufträge, Live-Cache und HTTP-Cache | Laufzeitdaten |
| `/var/run/shm/<plugin-folder>/vzlogger_config.lock` | Gemeinsame Sperre für ändernde Aktionen | Laufzeitdatei |

Dateien im RAM-Verzeichnis verschwinden bei einem Neustart. Persistente Konfiguration liegt im LoxBerry-Konfigurationsordner und bleibt bei normalen Updates erhalten.

## MQTT-Topics

vzLogger veröffentlicht aktive Kanäle unter `<Basis-Topic>/vzlogger`. Die Bridge abonniert pro aktivierter Ausgabe genau `chnN/raw` oder bei wirksamer Aggregation `chnN/agg`.

Die optionale Bridge-Ausgabe veröffentlicht ein gemeinsames Zeitstempelobjekt unter `<Basis-Topic>/bridge`. QoS darf `0` oder `1` sein; Retain wird aus der angewendeten vzLogger-Konfiguration übernommen. Topicnamen sind 1–256 Zeichen lang und enthalten keine Steuerzeichen oder Wildcards `+` und `#`.

## Datenformate

HTTP liefert eine Zeile je Wert und endet mit `#EOF`:

```text
meter-1:Power:431.2
meter-1:Energy Import:12345.678
#EOF
```

UDP sendet dieselben Einträge in derselben Reihenfolge, getrennt durch `; `:

```text
meter-1:Power:431.2; meter-1:Energy Import:12345.678
```

Bridge-MQTT enthält je Seriennummer `Last_UpdateUnix` und `Last_UpdateLoxEpoche`. Unix-Zeit bleibt UTC. Die Loxone-Epoche berücksichtigt die lokale Zeitzone zum Messzeitpunkt und kann beim Wechsel von Sommer- auf Winterzeit rückwärts springen.

Ausgabeschlüssel dürfen 1–64 Zeichen lang sein. `:` und `;` sind reservierte Trennzeichen. Die Schlüssel müssen je Lesekopf ohne Beachtung der Groß-/Kleinschreibung eindeutig sein.

## Grenzwerte und Standardwerte

| Einstellung | Vertrag |
|---|---|
| MQTT-Broker-, vzLogger-HTTP- und UDP-Zielports | `1–65535` |
| MQTT-QoS | `0` oder `1` |
| MQTT-Topic | 1–256 Zeichen, ohne Steuerzeichen, `+` oder `#` |
| Live-Datenintervall | Standard 2 Sekunden; wählbar bis 5 Minuten |
| Bridge-Aktualisierungsintervall für HTTP-Cache und UDP | 5, 10 oder 30 Sekunden; 1, 3, 5, 10, 15, 30 oder 60 Minuten |
| Recovery | nur POST, Token erforderlich, optional IP-Filter und Cooldown |

Eine Neuinstallation bereitet Bridge-MQTT als an, HTTP-Cache und UDP als aus vor; wirksam werden sie erst nach Aktivierung der Bridge. Upgrades bewahren vorhandene Auswahl.

## Speichern, Staging und Wiederherstellung

Die Oberfläche hält Änderungen zunächst im Browser. **Speichern und anwenden** validiert den vollständigen Entwurf, erzeugt zusammengehörige Dateien in einem geschützten Staging-Verzeichnis und übernimmt sie atomar. Bei einem Fehler bleibt die letzte gültige Laufzeitkonfiguration erhalten.

Die OBIS-Suche speichert ihre gefundenen Identifier unabhängig davon, ob die Seite offen bleibt. Erst ein späteres Apply bestimmt daraus aktive Kanäle. Das Entfernen eines Meters wird ebenfalls erst durch Apply dauerhaft und entfernt nur die diesem Meter gehörenden Zuordnungen und Laufzeitartefakte.

Nimm für eine manuelle Sicherung bevorzugt die LoxBerry-Sicherungsfunktion und schließe die SmartMeter-Pluginkonfiguration ein. Wer einzelne Dateien sichert, muss die oben als maßgeblich oder persistent gekennzeichneten Dateien gemeinsam erfassen. Kopiere keine Dateien aus `/var/run/shm` als Konfigurationssicherung. Das Zurückkopieren einzelner Dateien ist kein unterstützter Wiederherstellungsablauf des Plugins; verwende dafür eine vollständige, zur Installation passende LoxBerry-Sicherung.

## Logs und Datenschutz

Pluginaktionen verwenden LoxBerry-Logs. Wiederholte identische Bridge-Warnungen werden begrenzt; das native vzLogger-Log ist separat zuschaltbar. Passwörter, private Schlüssel und Token dürfen nicht in Supportanhänge übernommen werden.

Der lokale vzLogger-HTTP-Dienst, der HTTP-Cache und der Recovery-Endpunkt sind nicht für öffentliche Netze vorgesehen. Ein ausgeschalteter `local.index` ist keine Zugriffskontrolle. Verwende keine Router-Portweiterleitung und keinen öffentlichen Reverse Proxy.

[← Fehlerbehebung](troubleshooting.md) · [Zurück zur Übersicht](../../User-Guide.de.md)
