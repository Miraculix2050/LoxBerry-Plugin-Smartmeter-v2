# Installation, Update und Deinstallation

## Voraussetzungen

- LoxBerry 4.0.0 oder neuer. Dies ist die Installationsgrenze, kein Nachweis für jede neuere Plattform; prüfe die [Supportmatrix](../../support-matrix.de.md).
- Ein optischer I/R-Lesekopf, der auf dem Zielsystem unter `/dev/serial/smartmeter/` erkannt wird.
- Zugriff auf die LoxBerry-Pluginverwaltung und das Installationslog.
- Für vzLogger ein erreichbarer MQTT-Broker. Normalerweise werden die MQTT-Einstellungen von LoxBerry übernommen.

Das Plugin installiert `vzlogger` und `mosquitto-clients` über die normale LoxBerry-Paketliste. Es bündelt vzLogger nicht selbst.

## Lesekopf und Zähler vorbereiten

1. Prüfe in der Anleitung des Zählers, ob er SML, D0 oder OMS ausgibt.
2. Montiere den Lesekopf entsprechend der Herstellerangabe über der optischen Schnittstelle. Eine falsche Ausrichtung kann zu leeren oder unvollständigen Telegrammen führen.
3. Verbinde den Lesekopf mit LoxBerry.
4. Nach der Installation muss sein stabiler Gerätepfad unter `/dev/serial/smartmeter/` erscheinen. Die Plugin-Oberfläche zeigt die erkannten Pfade an.

Die Vorlagen sind bewährte Ausgangswerte, aber kein Kompatibilitätsversprechen. Die aktuell nachgewiesene Hardwareabdeckung steht unter [Bekannte Einschränkungen](../../known-limitations.de.md).

## Neu installieren

1. Öffne die gewünschte Version unter [GitHub Releases](https://github.com/Miraculix2050/LoxBerry-Plugin-Smartmeter-v2/releases).
2. Lade das offizielle `Smartmeter-V<Version>.zip`. Verwende kein automatisches GitHub-Quellcodearchiv.
3. Öffne die LoxBerry-Pluginverwaltung und installiere dieses ZIP als Plugin.
4. Warte, bis Installation und zusätzliche Paketinstallation abgeschlossen sind.
5. Prüfe im Installationslog die abschließenden Erfolgsmeldungen. Allgemeine LoxBerry-Warnungen sind nicht automatisch ein Pluginfehler.
6. Öffne SmartMeter v2. Ein Neustart ist normalerweise nicht erforderlich.

Eine Neuinstallation startet mit ausgewähltem vzLogger-Modus, aber ohne konfiguriertes Meter. Daher bleiben vzLogger und Bridge zunächst gestoppt. Die Bridge ist ausgeschaltet; ihre vorbereiteten Ausgabevorgaben sind MQTT-Zeitstempel an, HTTP-Cache aus und UDP aus.

Falls `udevadm` im Installationslog nicht ausgeführt werden konnte, trenne den USB-Lesekopf und verbinde ihn erneut. Starte LoxBerry nur neu, wenn der Gerätepfad danach weiterhin fehlt.

## Aktualisieren

1. Öffne die LoxBerry-Pluginverwaltung und starte das angebotene SmartMeter-v2-Update beziehungsweise installiere das offizielle ZIP der Zielversion.
2. Prüfe nach Abschluss das Installationslog.
3. Öffne beide Konfigurationsseiten und kontrolliere den aktiven Modus und die Dienstzustände.
4. Öffne die Live-Daten beziehungsweise führe bei Legacy eine manuelle Abfrage aus.

Ein Update bewahrt den gespeicherten Modus `vzlogger`, `legacy` oder `none`, die erzeugte gültige vzLogger-Konfiguration, den Expert-Entwurf, Legacy-Einstellungen und vorhandene Ausgabeauswahl. Ältere Installationen behalten ihr bisheriges Bridge-Verhalten: Bridge-MQTT bleibt zunächst aus und der HTTP-Cache an, bis du es änderst.

Ein Neustart ist nicht erforderlich. Beim Legacy-Intervall **Beim Systemstart** wird nach einem erfolgreichen Update sofort eine Messung gestartet.

Für das Update auf 2.0.1.0 ist keine manuelle Konfigurationsmigration erforderlich. 2.0.1.0 ist die letzte Version mit Legacy; wechsle vor einem späteren Upgrade auf 2.1.0.0 zu vzLogger und führe **Speichern/Anwenden** erfolgreich aus.

## Deinstallieren

Deinstalliere SmartMeter v2 über die LoxBerry-Pluginverwaltung. Dabei werden Plugin-eigene Konfigurationen, Dienste, Drop-ins, Udev-Regeln, Laufzeit-/Cachedateien und Pluginverzeichnisse entfernt.

Das Plugin entfernt `vzlogger`, die apt-Quelle und den Schlüssel nur, wenn seine Eigentumsmarker belegen, dass sie durch SmartMeter v2 eingeführt wurden. Bereits vor der Plugininstallation vorhandene Installationen ohne diese Marker bleiben erhalten.

Sichere benötigte Konfigurationswerte vor der Deinstallation manuell. Nach der Deinstallation gibt es keine Wiederherstellungsfunktion des Plugins.

## Netzwerksicherheit

LoxBerry und SmartMeter v2 sind ausschließlich für ein vertrauenswürdiges LAN vorgesehen. Folgende Endpunkte sind nicht für das öffentliche Internet bestimmt:

- LoxBerry-Weboberfläche
- vzLogger-HTTP-Dienst, standardmäßig Port `18080`
- SmartMeter-HTTP-Cache
- Loxone-Recovery-Endpunkt

Der vzLogger-Dienst und der HTTP-Cache sind nicht authentifiziert. Ein deaktivierter Index ersetzt keine Zugriffskontrolle. Messwerte können Anwesenheit und Aktivitäten erkennen lassen. Nutze für Recovery nach Möglichkeit HTTPS und eine Absender-IP-Liste; veröffentliche keinen der Endpunkte über Portfreigaben oder öffentliche Reverse-Proxys.
