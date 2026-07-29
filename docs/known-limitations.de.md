# Bekannte Probleme und Kompatibilitätseinschränkungen

Dieses Dokument nennt bestätigte, für Nutzer sichtbare Einschränkungen. Es ist keine Entwicklungsaufgabenliste. Eine Einschränkung bleibt bestehen, bis passende Nachweise sie einschränken oder aufheben.

## Begrenzte Abdeckung der Zielplattform

Die zuletzt bestätigten Versionen und Browserfamilien stehen in der [getesteten Supportmatrix](support-matrix.de.md). `LB_MINIMUM` steuert nur, ob eine Installation zulässig ist; daraus folgt keine getestete oder zugesagte Unterstützung.

Andere LoxBerry-, Debian- oder Raspberry-Pi-OS-Versionen und andere CPU-Architekturen wurden nicht auf einem Zielgerät geprüft. Repository-Verfügbarkeit und Root-Hook-Verhalten außerhalb Debian 13/trixie arm64 sind nicht bestätigt. Anforderungen und Code-Review erhöhen die Portabilität, ersetzen aber keinen Gerätetest.

## Legacy-Websicherheit bleibt eingefroren

Die moderne vzLogger-Verwaltung verlangt POST mit nutzergebundenem CSRF-Token und maskiert gespeicherte Werte im jeweiligen HTML-Kontext. Die funktional eingefrorene Legacy-Verwaltung erhält diese übergreifende Nachrüstung nicht und behält ihr vorhandenes CSRF-Risiko. Betreibe die gesamte LoxBerry-Installation nur im vertrauenswürdigen LAN, exponiere ihre Weboberfläche nicht ins Internet und bevorzuge vzLogger für aktiv gepflegtes Sicherheitsverhalten.

## Meter-Vorlagen benötigen repräsentative Hardware

Bestätigt ist ein angeschlossenes ISK-Meter mit SML und 9600 Baud/8N1. Ein Vergleich mit 9600 Baud/7E1 lieferte nur sporadische Daten und ist deshalb nicht die Generic-SML-Vorgabe. Die dynamische Suche fand `1-0:1.8.0`, `1-0:2.8.0` und `1-0:16.7.0`.

Andere Metermodelle, als `limited` markierte Vorlagen, OMS und beliebige benutzerdefinierte OBIS-Identifier wurden nicht mit repräsentativer Hardware bestätigt. Vorlagennamen und eingetragene Werte beweisen keine Kompatibilität mit einer bestimmten Meter-Firmware oder einem bestimmten Lesekopf. Nicht geprüfte Vorlagen können manuelle serielle Werte oder Custom JSONC erfordern; `limited`-Vorlagen können von Legacy-Kommandos oder Parsern abhängen, die das vzLogger-Standardformular nicht ausdrücken kann.
