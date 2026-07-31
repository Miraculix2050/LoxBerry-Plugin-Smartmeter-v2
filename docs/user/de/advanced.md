# Erweiterte Funktionen

[← Messwerte und Ausgaben](outputs.md) · [Zurück zur Übersicht](../../User-Guide.de.md) · [Weiter: Fehlerbehebung →](troubleshooting.md)

## Benutzerdefiniertes Meter mit JSONC

Wähle **Benutzerdefiniert (JSON)** nur, wenn das Standardformular dein Protokoll oder Gerät nicht abbildet. Der Editor erwartet genau ein vollständiges vzLogger-Meter-Objekt:

```jsonc
{
  // Beispiel für ein von vzLogger unterstütztes Protokoll
  "protocol": "s0",
  "device": "/dev/serial/smartmeter/example",
  "channels": [
    { "uuid": "11111111-1111-4111-8111-111111111111", "api": "null" }
  ]
}
```

Root-Bereiche wie `meters`, `mqtt`, `local`, `push` oder `retry` sind hier nicht erlaubt. Kommentare sind zulässig; die Quelle wird bis 64 KiB unverändert gespeichert. Das Plugin ergänzt für die Laufzeit nur fehlende UUID-/`api`-Werte in vorhandenen Channels, ohne den JSONC-Text umzuschreiben.

Ein ungültiges Objekt bleibt zur Korrektur gespeichert und wird mit einer Warnung markiert. Es wird nicht in die neu erzeugte Laufzeitkonfiguration aufgenommen. Verwende den externen Link **Parameterdokumentation** für die aktuelle vzLogger-Syntax.

## Expert Mode

Expert Mode bearbeitet einen getrennten persistenten Entwurf `vzlogger_expert.conf`.

1. Erzeuge zunächst mindestens einmal eine gültige `vzlogger.conf`.
2. Aktiviere **Expert Mode**.
3. Öffne **vzLogger-Konfiguration bearbeiten**.
4. Bearbeite das vollständige JSON und wähle **Speichern & schließen**.

Der Editor zeigt unmaskierte Zugangsdaten und ist deshalb nur im authentifizierten Frontend erreichbar. Eine gültige Datei wird zur Laufzeitkonfiguration, ohne den Dienst automatisch neu zu starten. Ein ungültiger Entwurf bleibt erhalten; die letzte gültige Laufzeitdatei bleibt aktiv.

Während Expert Mode aktiv ist, sind die Standard-vzLogger-Felder schreibgeschützt. Bridge-Einstellungen sowie das native Debug-Log bleiben separat bearbeitbar. Neue oder unbekannte Channel-UUIDs werden nicht automatisch von der Bridge veröffentlicht.

Das Ausschalten löscht den Expert-Entwurf nicht. **Aus aktueller vzlogger.conf neu initialisieren** ist die einzige Aktion, die ihn nach Bestätigung bewusst überschreibt.

## Dienststeuerung

Die Seite zeigt getrennte Panels für `vzlogger` und `smartmeter-v2-vzlogger-bridge`.

- **Start** und **Neustart** prüfen und verwenden die gespeicherte gültige Konfiguration. Sie speichern keine anderen offenen Formwerte.
- **Stop** bleibt für einen laufenden Dienst auch bei Konfigurationsfehlern verfügbar.
- Der Status wird bei sichtbarer Seite alle zehn Sekunden aktualisiert.
- Dienstaktionen und Statusaktualisierungen verändern keine ungespeicherten Bridge-Einstellungen. Im Expert Mode bleibt insbesondere die Bridge-MQTT-Auswahl erhalten, solange die angewendete vzLogger-Konfiguration Quellzeitstempel unterstützt.
- Eine manuelle Stop-Aktion gilt bis zum nächsten Neustart. Für eine dauerhafte Deaktivierung schalte den zugehörigen Aktiv-Schalter in der Pluginoberfläche aus und verwende **Speichern und anwenden**.

## Loxone-Dienst-Recovery

Recovery ermöglicht einem Loxone Miniserver, einen erwarteten Dienst im Zustand `failed` zu starten oder einen noch aktiven, aber festhängenden Dienst neu zu starten. Es startet keinen absichtlich inaktiven, deaktivierten oder unkonfigurierten Dienst.

1. Öffne **Loxone-Dienst-Recovery**.
2. Erzeuge ein zufälliges Token und kopiere es sofort; es wird nur einmal angezeigt.
3. Aktiviere nach Möglichkeit die Absender-IP-Einschränkung.
4. Speichere die Recovery-Einstellungen.
5. Übernimm die angezeigte Basisadresse in einen virtuellen Ausgang und die Felder für `vzlogger`, `bridge` oder `all` in virtuelle Ausgangsbefehle.

Jeder Befehl verwendet `POST`, einen leeren Body und den Header `X-Smartmeter-Recovery-Token`. Trage keinen LoxBerry-Benutzer und kein Passwort in die URL ein. Bei Tokenverlust erzeuge ein neues Token und aktualisiere Loxone; das vorherige Token wird sofort ungültig.

Recovery ist kein Ersatz für Netzwerkzugriffsschutz. Nutze HTTPS, wenn der Miniserver es unterstützt, und halte den Endpunkt im vertrauenswürdigen LAN.

## Logs und Diagnose

Bridge, Dienststeuerung, Weboberfläche und Diagnose erscheinen unter **SmartMeter v2 (Plugin Log)** in der LoxBerry-Logverwaltung und verwenden deren gemeinsame Plugin-Logstufe.

Für ein Bridge-Problem:

1. Setze die Plugin-Logstufe vorübergehend auf **Debug**.
2. Reproduziere den Fehler.
3. Öffne **Log anzeigen** oder erstelle ein **Debug-Log**.
4. Setze die Logstufe anschließend wieder zurück.

Das Debug-Log enthält Paket-, Service-, Validierungs-, Mapping-, Cache- und begrenzte MQTT-Diagnosen. Passwörter und private Schlüssel werden maskiert. Das getrennte native vzLogger-Log `vzlogger-native.log` wird nur geschrieben, wenn die vzLogger-Debugoption aktiv ist.

[← Messwerte und Ausgaben](outputs.md) · [Zurück zur Übersicht](../../User-Guide.de.md) · [Weiter: Fehlerbehebung →](troubleshooting.md)
