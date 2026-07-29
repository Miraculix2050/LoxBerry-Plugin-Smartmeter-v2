# Legacy verwenden

## Wann Legacy sinnvoll ist

Legacy bleibt in SmartMeter v2 2.0.1.0 als funktional eingefrorener Rückfallweg für bestehende Installationen und Zählerkonfigurationen verfügbar, die vzLogger nicht abdeckt. Dies ist die letzte Version mit Legacy; für 2.1.0.0 ist die Entfernung vorgesehen. Verwende für neue Einrichtungen vzLogger.

Legacy und vzLogger besitzen getrennte gespeicherte Einstellungen. Ein Wechsel verändert die andere Konfiguration nicht. Wechsle vor einem späteren Upgrade auf 2.1.0.0 zu vzLogger und führe dort **Speichern/Anwenden** erfolgreich aus.

## Legacy aktivieren

1. Öffne **Smartmeter Konfiguration (Legacy)**.
2. Schalte **Aktiv** ein.
3. Wähle den erkannten Lesekopf und eine Zählervorlage oder **Manuelle Konfiguration**.
4. Aktiviere bei Bedarf **Zähler automatisch abfragen** und wähle das Intervall.
5. Wähle die gewünschten HTTP-, UDP- und MQTT-Ausgaben.
6. Speichere die Seite.

Das Speichern eines aktiven Legacy-Modus stoppt vzLogger und Bridge und stellt den Legacy-Cronjob wieder her. Das Ausschalten von Legacy aktiviert vzLogger nicht automatisch.

## Zähler konfigurieren

Bei einer Vorlage zeigt der gesperrte Bereich **Manuelle Einstellung** die tatsächlich verwendeten Werte. Deine getrennt gespeicherten manuellen Werte bleiben erhalten.

Für eine manuelle Konfiguration können Protokoll, Baudraten, Parität, Handshake, Daten-/Stoppbits, Timeout, Verzögerung und CRC gesetzt werden. Verwende die Vorgaben des Zählerherstellers. Ungültige allgemeine oder Meterwerte verwerfen den vollständigen Speichervorgang; es entstehen keine Teiländerungen.

## Manuell lesen und Cache löschen

**Zähler manuell abfragen** ist verfügbar, wenn Legacy bereits gespeichert aktiv ist und vzLogger gestoppt ist. Das zyklische Lesen darf dabei ausgeschaltet sein.

**Cache löschen** entfernt ausschließlich Legacy-Daten-, Dump- und Logdateien. Konfigurationssperren und vzLogger-Laufzeitstatus bleiben erhalten.

## Legacy-Ausgaben

- **HTTP:** Ist immer aktiv. Die angezeigte URL liefert die Legacy-Cachewerte.
- **UDP:** Sendet die Werte an alle in LoxBerry konfigurierten Miniserver; Portbereich `1–65535`.
- **MQTT:** Veröffentlicht über das LoxBerry MQTT Gateway.

Standard-Basistopic:

```text
smartmeter
```

Topic und Payload:

```text
<Basis-Topic>/<Zähler>/<Wertname>
smartmeter/ABC123/Consumption_Total_OBIS_1.8.0
1234.567
```

Legacy-MQTT-Nachrichten verwenden Retain. Das Basistopic muss 1–256 Zeichen lang sein und darf keine Steuerzeichen oder MQTT-Wildcards `+` und `#` enthalten.
