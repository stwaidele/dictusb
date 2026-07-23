# Sicherheitshinweise / Security Policy

**English:** Please report vulnerabilities privately — either via
GitHub's "Report a vulnerability" (Security tab) or by e-mail to
stefan@waidele.info. Only the latest release is supported.

## Lücken melden

Bitte **nicht** als öffentliches Issue, sondern vertraulich:

- über GitHub: Security-Tab → „Report a vulnerability", oder
- per E-Mail an **stefan@waidele.info**.

Unterstützt wird jeweils nur das **neueste Release**.

## Sicherheitsmodell (Kurzfassung)

Der Kanal zwischen Sender und Gerät ist mit **DICTUSB2** verschlüsselt
und integritätsgeschützt (HMAC-SHA256, frisches Salt pro Verbindung,
Token wird nie übertragen, Downgrade-Schutz). Details, Grenzen und
Threat-Model: [PROTOCOL.md](PROTOCOL.md). Wichtigste Betriebsregel:
`DICTUSB_TOKEN` setzen — ohne Token tippt das Gerät, was ihm jeder im
WLAN schickt.
