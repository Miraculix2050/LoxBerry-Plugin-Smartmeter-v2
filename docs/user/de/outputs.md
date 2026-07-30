# Messwerte und Ausgaben verwenden

[← vzLogger konfigurieren](configuration.md) · [Zurück zur Übersicht](../../User-Guide.de.md) · [Weiter: Erweiterte Funktionen →](advanced.md)

## Datenfluss verstehen

vzLogger liest Meter und veröffentlicht die Messwerte per MQTT unter:

```text
<Basis-Topic>/vzlogger
```

Für jeden über **In SmartMeter ausgeben** freigegebenen Kanal abonniert die Bridge genau einen angewendeten Pfad:

```text
<Basis-Topic>/vzlogger/chnN/agg   bei wirksamer Aggregation
<Basis-Topic>/vzlogger/chnN/raw   sonst
```

Die Bridge liest niemals selbst das serielle Gerät. MQTT-Zeitstempel werden sofort veröffentlicht; HTTP-Cache und UDP verwenden das gemeinsame Aktualisierungsintervall.

## Live-Daten anzeigen

**Live-Daten (JSON) öffnen** zeigt den vzLogger-HTTP-Endpunkt. **Live-Daten als Webseite** zeigt eine lokalisierte Tabelle und einen Chart.

Die Webseite aktualisiert standardmäßig alle zwei Sekunden. Wählbar sind außerdem 10 oder 30 Sekunden sowie 1, 2 oder 5 Minuten. Bei einem verborgenen Tab pausiert die Erfassung standardmäßig.

Der Verlauf liegt ausschließlich im aktuellen Browserprofil in IndexedDB, nicht auf LoxBerry. Rohwerte bleiben 15 Minuten erhalten; verdichtete Werte reichen bis zu sieben Tage. Andere Browser oder Profile besitzen einen getrennten Verlauf. **Gespeicherten Verlauf löschen** betrifft nur diesen Browser.

Elektrische SML-Energiezähler werden für die Anzeige von Wh nach kWh umgerechnet. Der vzLogger-Rohwert bleibt im Tooltip sichtbar.

## Bridge-MQTT

Aktiviere **Bridge-Service aktiv** und **Unix- und Loxone-Timestamp über MQTT veröffentlichen**. Die Bridge übernimmt Broker, Authentifizierung, TLS, QoS und Retain aus der angewendeten vzLogger-Konfiguration und veröffentlicht auf:

```text
<Basis-Topic>/bridge
```

Beispiel:

```json
{"A106Q3RX":{"Last_UpdateUnix":1785264660,"Last_UpdateLoxEpoche":554503860}}
```

`Last_UpdateUnix` ist UTC. `Last_UpdateLoxEpoche` ist für die lokale Loxone-Anzeige `<v.u>` umgerechnet und kann beim Wechsel auf Winterzeit zurückspringen. Die Ausgabe benötigt aktivierte vzLogger-Quellzeitstempel. Sie enthält Zeitstempel, nicht alle Kanalwerte; Kanalwerte liefert vzLogger weiterhin unter seinen `chnN`-Topics.

Das LoxBerry MQTT Gateway kann das JSON in einzelne virtuelle Eingänge auflösen. Verwende dafür das Topic `<Basis-Topic>/bridge` und die JSON-Pfade der gewünschten Seriennummer und Eigenschaft.

## HTTP-Cache

Aktiviere Bridge und **HTTP-Cache aktualisieren**. Der direkte Link **HTTP-Cache öffnen** führt zu:

```text
http://<loxberry>/plugins/<plugin-ordner>/index.php
```

Beispielantwort:

```text
A106Q3RX:Last_Update:2026-07-29 12:34:56
A106Q3RX:Last_UpdateLoxEpoche:554503860
A106Q3RX:Consumption_Total_OBIS_1.8.0:1234.567
#EOF
```

Der Endpunkt liest RAM-basierte `.data`-Dateien unter `/var/run/shm/<plugin-ordner>/`. Ist der Cache aus, entfernt die Bridge diese Dateien und der Endpunkt antwortet mit `# HTTP cache disabled` und `#EOF`.

Der Cache ist nicht authentifiziert. Verwende ihn ausschließlich im vertrauenswürdigen LAN.

## UDP an Loxone

Aktiviere Bridge und **UDP senden**, trage einen Zielport von `1` bis `65535` ein und konfiguriere mindestens einen Miniserver in LoxBerry. Die Bridge sendet im gewählten Aktualisierungsintervall ein Datagramm je Meter an alle konfigurierten Miniserver.

Beispiel:

```text
A106Q3RX:Last_Update:2026-07-29 12:34:56; A106Q3RX:Last_UpdateLoxEpoche:554503860; A106Q3RX:Consumption_Total_OBIS_1.8.0:1234.567
```

Lege in Loxone Config einen virtuellen UDP-Eingang mit demselben Port an und werte die benötigten `Seriennummer:Ausgabeschlüssel:Wert`-Segmente aus. HTTP und UDP verwenden dieselben Werte und dieselbe Reihenfolge, aber UDP liest keine Cachedateien.

## Direkte vzLogger-Ziele

Ein Kanal kann unabhängig von der SmartMeter-Bridge direkt an eine von vzLogger unterstützte API gesendet werden. Wähle im erweiterten Kanalbereich das Ziel und fülle dessen Pflichtfelder aus. Verwende Zugangsdaten mit minimalen Rechten und nach Möglichkeit HTTPS.

### Volkszähler

Minimale Auswahl:

```text
API: volkszaehler
middleware: https://vz.example.lan/middleware.php
```

Die Kanal-UUID identifiziert den Volkszähler-Kanal. `duplicates` kann gleiche Wiederholungswerte zeitweise unterdrücken.

### InfluxDB

Minimale InfluxDB-2-Auswahl:

```text
API: influxdb
version: 2
host: https://influx.example.lan:8086
database/bucket: smartmeter
organization: home
token: <Token mit Schreibrecht für diesen Bucket>
```

Zusätzlich können Messreihe, Tags, Batch/Puffer und TLS-Prüfung eingestellt werden. Deaktiviere die Zertifikatsprüfung nur, wenn dies im vertrauenswürdigen LAN ausdrücklich erforderlich ist.

### MySmartGrid

Minimale Auswahl:

```text
API: mysmartgrid
middleware: https://api.example.lan/
secretKey: <Registrierungsschlüssel>
device: <Gerätekennung>
type: device oder sensor
```

Das Feld `name` ist der MySmartGrid-Registrierungsname und kein allgemeiner Anzeigename.

## Reihenfolge und berechnete Werte

HTTP und UDP beginnen mit `Last_Update` und `Last_UpdateLoxEpoche`. Danach folgen aktive Ausgabeschlüssel nach `chnN`, anschließend Zusatzwerte alphabetisch.

Fehlt eine passende Momentanleistung, kann die Bridge aus zwei unterschiedlichen Energiezählerständen berechnete Bezugs- oder Lieferleistung erzeugen. Vorhandene richtungsbezogene Leistungswerte unterdrücken jeweils die passende Berechnung; eine vorzeichenbehaftete Gesamtleistung unterdrückt beide.

[← vzLogger konfigurieren](configuration.md) · [Zurück zur Übersicht](../../User-Guide.de.md) · [Weiter: Erweiterte Funktionen →](advanced.md)
