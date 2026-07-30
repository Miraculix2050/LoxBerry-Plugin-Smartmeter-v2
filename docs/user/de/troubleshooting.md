# Fehlerbehebung

[← Erweiterte Funktionen](advanced.md) · [Zurück zur Übersicht](../../User-Guide.de.md) · [Weiter: Technische Referenz →](reference.md)

Arbeite die Hinweise zum sichtbaren Symptom durch. Ändere nicht mehrere Einstellungen gleichzeitig. Prüfe nach jedem Schritt erneut.

## Installation oder Update schlägt fehl

1. Öffne in der LoxBerry-Pluginverwaltung das Installationslog.
2. Suche zuerst nach dem abschließenden Erfolgs- oder Fehlerstatus des Plugins. Allgemeine LoxBerry-Warnungen sind nicht automatisch ein Pluginfehler.
3. Prüfe Internetzugang, freie Speicherkapazität und die Paketquellen des LoxBerry.
4. Schlägt die Installation von `vzlogger`, `mosquitto-clients` oder `libdevice-serialport-perl` fehl, prüfe die Internetverbindung und den Zugriff auf das Cloudsmith-Repository des Volkszähler-Projekts. Behebe zuerst den Paketfehler und starte die Installation erneut.

## Lesekopf oder Gerätepfad fehlt

1. Prüfe Stromversorgung, Sitz und Ausrichtung des Lesekopfs.
2. Trenne den Lesekopf kurz und verbinde ihn erneut.
3. Lade die SmartMeter-Seite neu und wähle **Nach I/R-Leseköpfen suchen**.
4. Prüfe, ob der erwartete stabile Pluginpfad unter `/dev/serial/smartmeter/` erscheint. Verwende ihn und nicht `/dev/ttyUSB0`.

Wird kein Gerät erkannt, prüfe den Lesekopf zunächst an einem anderen USB-Anschluss. Die Anzeige eines Gerätepfads bestätigt nur das USB-Gerät, nicht das richtige Protokoll oder die korrekte Montage am Zähler.

## OBIS-Suche findet keine Werte

Prüfe Protokoll, Baudrate, Parität und Lesekopfposition. Manche Zähler senden Werte erst nach einer Aktivierung am Zähler. Die OBIS-Suche unterstützt OMS nur, wenn die installierte vzLogger-Version OMS bereitstellt. Zeigt die Oberfläche den Hinweis, dass OMS nicht unterstützt wird, sind Suche, Prüfung und Anwenden für dieses Meter gesperrt.

Die Suche läuft im Hintergrund. Warte auf ihren Abschluss und öffne das Ergebnis erneut. Gefundene Identifier sind dann gespeichert, aber erst **Speichern und anwenden** übernimmt ausgewählte Kanäle in die aktive Konfiguration.

## Speichern und anwenden scheitert

- **Konfiguration ungültig:** Korrigiere das markierte Feld. Ports dürfen `1–65535`, QoS nur `0` oder `1` sein.
- **Aktion läuft bereits:** Warte, bis Suche, Apply oder eine Dienstaktion beendet ist. Änderungen werden durch eine gemeinsame Sperre geschützt.
- **Zeitüberschreitung oder sudo-Fehler:** Öffne **Logs**, suche nach der zugehörigen Aktion und wiederhole sie nicht fortlaufend.
- **Dienst bleibt gestoppt:** Gespeicherte Aktivierung, mindestens ein aktives Meter und eine gültige Konfiguration sind nötig. Bei deaktiviertem vzLogger oder ohne Meter stoppt Apply die Dienste absichtlich.

## vzLogger oder Bridge läuft nicht

Öffne **Dienste** und anschließend **Logs**. Prüfe zuerst die letzte Statusmeldung und dann `vzlogger-native.log`, falls das native Debug-Log bewusst eingeschaltet wurde.

Die Bridge ist optional. Sie bleibt gestoppt, wenn sie ausgeschaltet ist, kein aktiver SmartMeter-Ausgabekanal vorhanden ist oder die angewendete Quelle nicht nutzbar ist. Nutze zum Deaktivieren den Schalter in der SmartMeter-Oberfläche; deaktiviere die Units nicht manuell mit `systemctl`.

## MQTT oder TLS funktioniert nicht

Prüfe Brokername, Port, Zugangsdaten und das Basistopic. Das Topic darf weder `+` noch `#` enthalten. Bei TLS müssen CA-Datei, Zertifikat und Schlüssel zueinander passen und für den Dienst lesbar sein. Geheimnisse werden in Oberfläche und Logs maskiert.

Teste zuerst ohne Bridge-Ausgabe, ob vzLogger Werte unter `<Basis-Topic>/vzlogger` veröffentlicht. Die Bridge-Zeitstempel erscheinen getrennt unter `<Basis-Topic>/bridge`.

## Live-Daten bleiben leer oder langsam

Live-Daten benötigen eine laufende, gültig konfigurierte vzLogger-Instanz. Das Standardintervall beträgt zwei Sekunden; in den lokalen Diagrammeinstellungen sind bis zu fünf Minuten möglich. Nach Fehlern verlängert die Seite das Intervall vorübergehend.

Prüfe, ob der gewählte Kanal aktiv ist und MQTT-Daten ankommen. Ein ausgeblendeter Browsertab kann durch den Browser zusätzlich gedrosselt werden.

## HTTP-Cache oder UDP liefert nichts

Aktiviere zuerst die Bridge und dann die gewünschte Ausgabe. Aktiviere bei mindestens einem Kanal **In SmartMeter ausgeben**. HTTP-Cache und UDP sind unabhängig; ein aktiver Cache schaltet UDP nicht automatisch ein.

Für UDP müssen Zieladresse und Port erreichbar sein. Der Port darf `1–65535` sein. Der HTTP-Endpunkt meldet ausdrücklich, wenn der Cache deaktiviert ist.

## Expert Mode lässt sich nicht anwenden

Der Entwurf muss gültiges JSONC enthalten und das vollständige Schema erfüllen. Prüfe die eingeblendete Validierung und die Logs. **Aus aktueller vzlogger.conf neu initialisieren** überschreibt den Entwurf nur nach Bestätigung; verwende diese Funktion nur, wenn du den bisherigen Entwurf nicht mehr brauchst.

## Recovery-Aufruf wird abgewiesen

Der Recovery-Endpunkt akzeptiert nur `POST` mit dem angezeigten Token. Er startet nur einen konfigurierten, aktiven oder aktivierbaren Dienst und installiert oder aktiviert keine Units. Prüfe Methode, Token-Header, leeren Body und Zielpfad. Sende Token niemals über das öffentliche Internet.

## Upgrade auf 2.1.0.0 wird blockiert

Das Upgrade stoppt vor dem Dateiaustausch, wenn Legacy noch aktiv ist oder eine ältere Konfiguration als aktives Legacy erkannt wird. Bleibe auf der neuesten unterstützten Legacy-Wartungsversion der Reihe 2.0.1.x (derzeit 2.0.1.1) oder installiere sie erneut. Aktiviere vzLogger und führe **Speichern und anwenden** erfolgreich aus. Versuche danach das Upgrade erneut.

Hilft das nicht, öffne eine Anfrage unter [GitHub Issues](https://github.com/Miraculix2050/LoxBerry-Plugin-Smartmeter-v2/issues). Ergänze Pluginversion, LoxBerry-Version, Zählermodell, Lesekopf, gewähltes Protokoll und die relevante Logmeldung. Entferne vorher MQTT-Passwörter, Recovery-Token, private Schlüssel, vollständige Zertifikate und andere private Gerätedaten.

[← Erweiterte Funktionen](advanced.md) · [Zurück zur Übersicht](../../User-Guide.de.md) · [Weiter: Technische Referenz →](reference.md)
