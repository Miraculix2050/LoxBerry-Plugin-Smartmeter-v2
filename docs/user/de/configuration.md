# vzLogger konfigurieren

## Modus wählen

Die Tabs **Smartmeter Konfiguration (vzLogger)** und **Smartmeter Konfiguration (Legacy)** öffnen nur die jeweilige Seite. Sie wechseln nicht sofort die laufende Implementierung.

1. Öffne die vzLogger-Seite.
2. Schalte **Aktiv** ein.
3. Konfiguriere mindestens ein aktives Meter.
4. Übernimm den Zustand mit **Speichern und anwenden**.

Ein grünes Häkchen im Tab kennzeichnet den gespeicherten aktiven Modus. Legacy und vzLogger laufen niemals gleichzeitig; beide dürfen inaktiv sein. Beim Aktivieren von vzLogger entfernt das Plugin die Legacy-Cronjobs. Ein gültiges vorhandenes `vzlogger.conf` bleibt beim Wechsel zu Legacy oder `none` erhalten und wird bei der späteren Reaktivierung wiederverwendet.

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

Vorlagen beruhen auf Projekterfahrung. Prüfe die Werte gegen die Dokumentation deines Zählers. Mit `limited` gekennzeichnete Vorlagen können Legacy-Sondersequenzen benötigen, die das Standardformular nicht abbildet.

## Grundlegende Meter-Einstellungen

- **Meter aktiv:** Nimmt das Meter in die erzeugte Konfiguration auf.
- **Fehler überspringen (`allowskip`):** Empfohlen aktiv, damit ein nicht erreichbares Meter andere Meter nicht beendet.
- **Intervall:** Zugriffsabstand bei aktiv abgefragten Metern; `-1` ist üblich für selbstständig sendende Meter.
- **Aggregationszeit (`aggtime`):** `-1` deaktiviert Aggregation. Ein positiver Wert sammelt Messwerte für die Kanalauswertung.
- **Feste Aggregationsintervalle:** Wirksam nur bei positiver Aggregationszeit.

Leere optionale Felder werden nicht in `vzlogger.conf` geschrieben. Das Standardformular verwendet immer den erkannten lokalen Gerätepfad. Verwende für TCP-Meter den benutzerdefinierten JSONC-Modus.

## Erstmals speichern

Wähle **Speichern und anwenden**, bevor du die OBIS-Suche startest. Die Aktion speichert die Formwerte, erzeugt und validiert die Konfiguration und stellt den gewünschten Dienstzustand her:

- Ein aktiver vzLogger-Modus mit mindestens einem aktiven Meter installiert den Plugin-Override, aktiviert vzLogger und startet ihn neu.
- Eine aktive Bridge wird installiert, aktiviert und gestartet.
- Eine deaktivierte Bridge wird gestoppt und aus dem Autostart entfernt.
- Ein inaktiver oder meterloser Modus stoppt vzLogger und Bridge und entfernt den Plugin-Override.

Ein Fehler ersetzt niemals die letzte zusammengehörige gültige Laufzeitkonfiguration. Die eingegebenen Werte können zur Korrektur gespeichert bleiben.

## OBIS-Kanäle suchen

1. Öffne das gewünschte SML-, D0- oder OMS-Meter.
2. Wähle **OBIS-Kanäle lesen**.
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
