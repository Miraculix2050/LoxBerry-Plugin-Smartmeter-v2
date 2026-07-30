# vzLogger konfigurieren

[← Installation, Update und Deinstallation](installation.md) · [Zurück zur Übersicht](../../User-Guide.de.md) · [Weiter: Messwerte und Ausgaben →](outputs.md)

## Gewünschten Dienstzustand festlegen

1. Öffne die vzLogger-Seite.
2. Schalte **vzLogger aktiv** ein.
3. Konfiguriere mindestens ein aktives Meter.
4. Übernimm den Zustand mit **Speichern und anwenden**.

Der Schalter speichert den gewünschten vzLogger-Zustand erst mit **Speichern und anwenden**. Start, Stopp und Neustart sind temporäre Dienstaktionen und ändern ihn nicht. Während einer Dienstaktion sind die Bedienelemente beider Dienste gesperrt. Mit **Im Hintergrund weiterlaufen lassen** kann das Fortschrittsfenster geschlossen werden; ein Hinweis bleibt bis zum Abschluss der Aktion sichtbar. Eine gültige vorhandene `vzlogger.conf` bleibt bei deaktiviertem vzLogger erhalten und wird bei der späteren Reaktivierung wiederverwendet.

## Lesekopf hinzufügen

1. Schließe den Lesekopf an.
2. Wähle **Nach I/R-Leseköpfen suchen**.
3. Öffne den neu angelegten Bereich mit Gerätepfad und Serienkennung.
4. Vergib bei Bedarf einen verständlichen Namen.
5. Wähle das Protokoll:
   - **SML** für binäre SML-Telegramme.
   - **D0** für IEC-62056-21/D0-Telegramme.
   - **OMS** für OMS/M-Bus; die installierte vzLogger-Version muss OMS unterstützen.
   - **Benutzerdefiniert (JSON)** für andere vzLogger-Protokolle oder Netzwerkgeräte.

Ein neuer Lesekopf bleibt bis zum Anwenden als **Neu / ungespeichert** markiert. Ein Lesekopf ohne Protokoll erzeugt kein Meter.

## Vorlage verwenden

Für SML und D0 steht **Aus Vorlage initialisieren** zur Verfügung. Eine Vorlage setzt nur die bekannten seriellen Ausgangswerte und bei D0 das Lese-Timeout. Name, Aktivierung, Gerät, Intervalle, Sequenzen und Kanäle bleiben erhalten.

Vorlagen beruhen auf Projekterfahrung. Prüfe die Werte gegen die Dokumentation deines Zählers. Mit `limited` gekennzeichnete Vorlagen können Sequenzen benötigen, die das Standardformular nicht abbildet; verwende Custom JSONC, wenn vzLogger das erforderliche Verhalten unterstützt.

## Grundlegende Meter-Einstellungen

- **Zähler aktiv**: Nimmt das Meter in die erzeugte Konfiguration auf.
- **Fehler überspringen (`allowskip`):** Empfohlen aktiv, damit ein nicht erreichbares Meter andere Meter nicht beendet.
- **Intervall:** Zugriffsabstand bei aktiv abgefragten Metern; `-1` ist üblich für selbstständig sendende Meter.
- **Aggregationszeit (`aggtime`):** `-1` deaktiviert Aggregation. Ein positiver Wert sammelt Messwerte für die Kanalauswertung.
- **Feste Aggregationsintervalle:** Wirksam nur bei positiver Aggregationszeit.

Leere optionale Felder werden nicht in `vzlogger.conf` geschrieben. Das Standardformular verwendet immer den erkannten lokalen Gerätepfad. Verwende für TCP-Meter den benutzerdefinierten JSONC-Modus.

## MQTT für den ersten Betrieb einrichten

MQTT veröffentlicht die normalen Kanalmesswerte und liefert der optionalen SmartMeter-Bridge ihre Quelldaten. Die direkte Live-Datenansicht über den vzLogger-HTTP-Dienst kann unabhängig davon arbeiten. Gehe für eine übliche MQTT-Einrichtung so vor:

1. Schalte **MQTT aktiv** ein.
2. Lasse **MQTT-Broker**, **MQTT-Port** und **MQTT-Benutzer** leer, wenn der in LoxBerry konfigurierte Broker verwendet werden soll. Das Plugin übernimmt dann die LoxBerry-Systemwerte einschließlich des Systempassworts.
3. Trage eigene Werte nur ein, wenn vzLogger einen anderen Broker oder eigene Zugangsdaten verwenden soll. Ein leeres Passwortfeld behält das bereits gespeicherte Passwort bei.
4. Verwende ein einfaches **MQTT-Basis-Topic**, zum Beispiel `smartmeter`. vzLogger veröffentlicht darunter automatisch auf `<Basis-Topic>/vzlogger`.
5. Lasse **Zeitstempel** eingeschaltet, wenn die Bridge **Unix- und Loxone-Timestamp über MQTT veröffentlichen** soll. HTTP-Cache und UDP können auch ohne Quell-Zeitstempel arbeiten.
6. Verwende TLS-Zertifikatsfelder nur, wenn dein Broker TLS verlangt. Prüfe dann, ob CA-, Zertifikats- und Schlüsseldateien für den Dienst lesbar sind; deaktiviere die Zertifikatsprüfung nicht ohne begründeten Bedarf.

Wähle anschließend **Speichern und anwenden** und prüfe unter **Live-Daten als Webseite**, ob Werte erscheinen. Bei Problemen helfen die Abschnitte [MQTT oder TLS funktioniert nicht](troubleshooting.md#mqtt-oder-tls-funktioniert-nicht) und [Datenfluss verstehen](outputs.md#datenfluss-verstehen).

## Erstmals speichern

Wähle **Speichern und anwenden**, bevor du die OBIS-Suche startest. Die Aktion speichert die Formwerte, erzeugt und validiert die Konfiguration und stellt den gewünschten Dienstzustand her:

- Aktivierter vzLogger mit mindestens einem aktiven Meter installiert den Plugin-Override, aktiviert vzLogger und startet ihn neu.
- Eine aktive Bridge wird installiert, aktiviert und gestartet.
- Eine deaktivierte Bridge wird gestoppt und aus dem Autostart entfernt.
- Eine deaktivierte oder meterlose Konfiguration stoppt vzLogger und Bridge und entfernt den Plugin-Override.

Ein Fehler ersetzt niemals die letzte zusammengehörige gültige Laufzeitkonfiguration. Die eingegebenen Werte können zur Korrektur gespeichert bleiben.

## OBIS-Kanäle suchen

1. Öffne das gewünschte SML-, D0- oder OMS-Meter.
2. Wähle **OBIS-Kanäle auslesen**.
3. Warte auf das Ergebnis oder verwende **Suche abbrechen**.
4. Prüfe die neu gefundenen Kanäle.

Die Suche verwendet die aktuell im Browser eingestellten Meterwerte, stoppt vzLogger vorübergehend und stellt den vorherigen Dienstzustand anschließend wieder her. Sie läuft im Hintergrund weiter, wenn du die Seite neu lädst oder verlässt. Erkannte Identifier werden vom Auftrag gespeichert. Welche Kanäle aktiv in `vzlogger.conf` und in die Bridge übernommen werden, entscheidest du anschließend mit **Speichern und anwenden**.

Findet die Suche nichts, prüfe Protokoll, Ausrichtung des Lesekopfs, Baudrate/seriellen Modus und das Discovery-Log.

## Kanäle auswählen

Jeder Kanal besitzt eine UUID und einen OBIS-Identifier. Du kannst:

- den Kanal aktivieren oder deaktivieren;
- einen verständlichen Anzeigenamen vergeben;
- bei SML/D0 einen vom Zähler gelieferten Speicherindex `0–254` wählen;
- bei aktiver Meter-Aggregation `none`, `avg`, `max` oder `sum` wählen;
- ein direktes vzLogger-API-Ziel konfigurieren;
- **In SmartMeter ausgeben** aktivieren.

**In SmartMeter ausgeben** stellt den Kanal den aktivierten Bridge-Ausgaben bereit. HTTP-Cache und UDP können unabhängig voneinander eingeschaltet werden. Der Ausgabeschlüssel ist der einzige über Cache und UDP verwendete Name und muss pro Lesekopf ohne Beachtung der Groß-/Kleinschreibung eindeutig sein.

Manuell angelegte Kanäle können zum Löschen vorgemerkt werden. Gefundene Kanäle werden normalerweise deaktiviert, damit eine spätere Suche sie wiedererkennt. Vorgemerkte Änderungen werden erst mit **Speichern und anwenden** dauerhaft.

## Prüfen oder anwenden

- **Konfiguration prüfen** erzeugt einen temporären Entwurf. Gespeicherte Dateien und Dienste bleiben unverändert.
- **Speichern und anwenden** speichert, erzeugt, prüft und übernimmt die Konfiguration.

Beide Aktionen besitzen ein Zeitlimit von 60 Sekunden. Ist eine andere Konfigurations- oder Dienstaktion aktiv, wird die neue Aktion ohne Teiländerungen abgewiesen. Start und Neustart verwenden nur die bereits gespeicherte gültige Konfiguration; Stop bleibt für einen laufenden Dienst verfügbar.

## Meter entfernen

**Meter-Konfiguration entfernen** blendet ein Meter zunächst nur im aktuellen Browserentwurf aus. Erst **Speichern und anwenden** löscht seine gespeicherten Einstellungen und zugehörigen Plugin-Artefakte. Ein weiterhin angeschlossener entfernter Lesekopf bleibt bei normalen Seitenaufrufen verborgen; eine neue Lesekopfsuche legt ihn mit Standardeinstellungen wieder an.

[← Installation, Update und Deinstallation](installation.md) · [Zurück zur Übersicht](../../User-Guide.de.md) · [Weiter: Messwerte und Ausgaben →](outputs.md)
