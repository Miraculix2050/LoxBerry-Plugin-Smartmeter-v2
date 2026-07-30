# Installation, Update und Deinstallation

[Zurück zur Übersicht](../../User-Guide.de.md) · [Weiter: vzLogger konfigurieren →](configuration.md)

## Voraussetzungen

- LoxBerry 4.0.0 oder neuer. Dies ist die Installationsgrenze, kein Nachweis für jede neuere Plattform; prüfe die [Supportmatrix](../../support-matrix.de.md).
- Ein optischer I/R-Lesekopf, der auf dem Zielsystem unter `/dev/serial/smartmeter/` erkannt wird.
- Zugriff auf die LoxBerry-Pluginverwaltung und das Installationslog.
- Internetzugang für Download und Installation. Der Downloadweg muss GitHub erreichen; LoxBerry selbst muss auf das externe Cloudsmith-Paketrepository des Volkszähler-Projekts zugreifen können.
- Für vzLogger ein erreichbarer MQTT-Broker. Normalerweise werden die MQTT-Einstellungen von LoxBerry übernommen.

Das Plugin richtet die Volkszähler-Paketquelle ein und installiert `vzlogger`, `mosquitto-clients` und `libdevice-serialport-perl` über die normale LoxBerry-Paketverwaltung. Es bündelt diese Pakete nicht selbst. Schlägt der Zugriff auf die Paketquelle fehl, kann die Plugininstallation nicht vollständig abgeschlossen werden.

## Stable- und Prerelease-Versionen

Der Stable-Kanal ist die empfohlene Wahl für den normalen Betrieb. Prereleases enthalten neuere Änderungen zur Erprobung und können noch unbekannte Fehler besitzen. LoxBerry prüft den Prerelease-Kanal nur, wenn du Vorabversionen in der Pluginverwaltung ausdrücklich zugelassen hast.

Installiere in beiden Fällen nur das fertige `Smartmeter-V<Version>.zip` aus der zugehörigen GitHub-Veröffentlichung. Die auf einer GitHub-Seite zusätzlich angebotenen Quellcodearchive sind keine installierbaren LoxBerry-Pakete.

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

Eine Neuinstallation aktiviert den vzLogger-Sollzustand, enthält aber noch kein konfiguriertes Meter. Daher bleiben vzLogger und Bridge zunächst gestoppt. Die Bridge ist ausgeschaltet; ihre vorbereiteten Ausgabevorgaben sind MQTT-Zeitstempel an, HTTP-Cache aus und UDP aus.

Falls `udevadm` im Installationslog nicht ausgeführt werden konnte, trenne den USB-Lesekopf und verbinde ihn erneut. Starte LoxBerry nur neu, wenn der Gerätepfad danach weiterhin fehlt.

## Aktualisieren

Erstelle vor einem größeren Update eine aktuelle LoxBerry-Sicherung. Normale Updates bewahren die persistenten SmartMeter-Einstellungen und angewendeten vzLogger-Dateien, eine Sicherung bleibt aber der sicherste Rückweg bei einem Geräte-, Datenträger- oder Installationsfehler. Das Plugin besitzt keinen eigenen Sicherungs- oder Wiederherstellungsassistenten.

1. Öffne die LoxBerry-Pluginverwaltung und starte das angebotene SmartMeter-v2-Update beziehungsweise installiere das offizielle ZIP der Zielversion.
2. Prüfe nach Abschluss das Installationslog.
3. Öffne die Konfigurationsseite und kontrolliere die gespeicherten Sollzustände und aktuellen Dienstzustände.
4. Öffne die Live-Daten und bestätige aktuelle Messwerte.

Version 2.1.0.0 bewahrt eine gültige erzeugte vzLogger-Konfiguration, Kanal-UUIDs, Ausgabeschlüssel, den Expert-Entwurf, Bridge-Ausgaben und Recovery-Einstellungen. Die bisherigen Modi `vzlogger` und `none` werden in den entsprechenden aktivierten oder deaktivierten Sollzustand überführt; der bisherige Bridge-Schalter wird unabhängig migriert.

Ein Upgrade wird vor dem Dateiaustausch blockiert, wenn Legacy noch aktiv ist; dies gilt auch für ältere Installationen, die als aktives Legacy erkannt werden. Bleibe auf der neuesten unterstützten Legacy-Wartungsversion der Reihe 2.0.1.x (derzeit 2.0.1.1) oder installiere sie erneut. Aktiviere dort vzLogger und führe **Speichern und anwenden** erfolgreich aus, bevor du das Upgrade auf 2.1.0.0 erneut versuchst. Inaktive Legacy-Einstellungen werden bei einem erlaubten Upgrade gelöscht und nicht als Sicherung aufbewahrt. Ein Neustart ist nicht erforderlich.

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

[Zurück zur Übersicht](../../User-Guide.de.md) · [Weiter: vzLogger konfigurieren →](configuration.md)
