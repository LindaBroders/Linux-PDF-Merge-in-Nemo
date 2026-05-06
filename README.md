# PDF Merge in Nemo

![Platform](https://img.shields.io/badge/platform-Linux-blue)
![Shell](https://img.shields.io/badge/shell-bash-green)
![File Manager](https://img.shields.io/badge/file--manager-Nemo-orange)
![License](https://img.shields.io/badge/license-GPL%20v3-blue)
![Stars](https://img.shields.io/github/stars/robitschmatthias-ui/Linux-PDF-Merge-in-Nemo?style=social)

Bash-Skripte zum Zusammenfügen von Dateien zu PDF direkt aus dem Nemo-Dateimanager (Linux Mint / Ubuntu).

---

## Features

- **Zwei Merge-Modi per Rechtsklick:**
  - **PDF Quick Merge** – sofort zusammenfügen, keine weiteren Fragen
  - **PDF Advanced Merge** – Reihenfolge per Drag & Drop festlegen, Seitengröße und Ausrichtung wählen
- **Unterstützte Formate:** PDF, Bilder (JPG, PNG, TIFF, BMP, WebP, GIF), Office-Dokumente (ODT, ODS, ODP, DOCX, XLSX, PPTX, DOC), Text (TXT, RTF)
- **A4-Anpassung** (Advanced) – große Seiten werden auf A4 verkleinert (300 DPI), kleine Bilder unter 200 DPI bleiben in Originalgröße und werden zentriert
- **Ausrichtung** (Advanced) – Original beibehalten, Hochformat oder Querformat erzwingen
- **PDF nach Merge öffnen** (Advanced) – optionale Checkbox um das Ergebnis direkt im Standard-PDF-Programm zu bearbeiten
- **Eigenes Icon** – blaues PDF-Merge-Icon im Kontextmenü
- **Automatischer Installer** – prüft und installiert alle Abhängigkeiten

## Voraussetzungen

Das Installationsskript kümmert sich um alles. Folgende Pakete werden automatisch installiert:

| Paket | Zweck |
|---|---|
| `libreoffice` | Konvertierung von Office-Dokumenten |
| `pdftk` | Zusammenfügen der PDF-Dateien |
| `img2pdf` | Konvertierung von Bildern |
| `zenity` | GUI-Dialoge |
| `yad` | Erweiterte Dialoge |
| `ghostscript` | Seitengrößen-Anpassung und Ausrichtung |

Python 3 mit GTK3 (vorinstalliert auf Ubuntu/Linux Mint) wird für den Advanced-Dialog verwendet.

### Schriftarten für DOCX-Konvertierung (empfohlen)

Word-Dokumente verwenden häufig Schriftarten die unter Linux nicht vorinstalliert sind (Calibri, Cambria, Verdana, Georgia u.a.). Fehlen diese Schriften, ersetzt LibreOffice sie durch ähnliche Alternativen mit leicht abweichenden Zeichenabständen – das kann bei engen Seitenrändern dazu führen, dass Inhalte auf eine zusätzliche Seite umbrechen.

Mit diesen drei Paketen wird das Problem für praktisch alle gängigen Word-Dokumente behoben:

| Paket | Schriftarten |
|---|---|
| `fonts-crosextra-carlito` | Calibri-kompatibler Ersatz (metrisch identisch) |
| `fonts-crosextra-caladea` | Cambria-kompatibler Ersatz (metrisch identisch) |
| `ttf-mscorefonts-installer` | Echte MS-Fonts: Arial, Times New Roman, Verdana, Georgia, Trebuchet MS, Tahoma, Impact u.a. |

```bash
sudo apt install fonts-crosextra-carlito fonts-crosextra-caladea ttf-mscorefonts-installer
sudo fc-cache -fv
```

> Hinweis: Bei `ttf-mscorefonts-installer` erscheint ein EULA-Dialog (Microsoft-Lizenz) – mit **OK** bestätigen.

## Installation

```bash
git clone https://github.com/robitschmatthias-ui/Linux-PDF-Merge-in-Nemo.git
cd Linux-PDF-Merge-in-Nemo
sudo bash install.sh
nemo -q && nemo &
```

Der Installer prüft welche Abhängigkeiten bereits vorhanden sind und installiert nur die fehlenden Pakete. Nach der Installation und dem Nemo-Neustart erscheinen zwei Einträge im Rechtsklick-Menü.

## Verwendung

### PDF Quick Merge

1. Dateien in Nemo markieren
2. Rechtsklick → **PDF Quick Merge**
3. Speicherort wählen
4. Fertig

### PDF Advanced Merge

1. Dateien in Nemo markieren
2. Rechtsklick → **PDF Advanced Merge**
3. Im Dialog:
   - Dateien per **Drag & Drop** in die gewünschte Reihenfolge ziehen
   - **Seitengröße** wählen (Original oder A4-Anpassung)
   - **Ausrichtung** wählen (Original, Hochformat, Querformat)
   - Optional: **PDF nach Merge öffnen** ankreuzen
4. Speicherort wählen
5. Fertig

> Tipp: Mit „PDF Arranger" (separat installierbar) können einzelne Seiten nachträglich gedreht oder verschoben werden.

## Bekannte Einschränkungen

### Digitale Signaturen in PDF-Dateien

Beim Zusammenfügen von PDFs, die digitale Signaturen enthalten, bleiben die Signatur-Objekte physisch in der Ausgabedatei erhalten. Da der Merge-Vorgang den Dateiinhalt verändert, ist der kryptografische Hash der ursprünglichen Signatur jedoch nicht mehr gültig. PDF-Viewer wie Adobe Acrobat werden eine solche Signatur als **ungültig** oder **verändert** kennzeichnen. Wer die Gültigkeit einer digitalen Signatur benötigt, sollte die betreffende PDF nicht zusammenführen.

### Word-Dokumente (DOCX, DOC)

Word-Dokumente werden intern über LibreOffice im Headless-Modus in PDF konvertiert, bevor sie zusammengeführt werden. Dabei können **Seitenumbrüche, Schriftarten, Spalten-Layouts und komplexe Tabellen** vom Original abweichen.

Der häufigste Fehler – Inhalt bricht unerwartet auf eine zusätzliche Seite um – wird durch fehlende Schriftarten verursacht: LibreOffice ersetzt nicht installierte Fonts durch Alternativen mit leicht abweichenden Zeichenbreiten, was bei engen Seitenrändern zum Überlauf führt. **Lösung: die empfohlenen Schriftartenpakete installieren** (siehe [Schriftarten für DOCX-Konvertierung](#schriftarten-für-docx-konvertierung-empfohlen)).

Für Dokumente mit sehr komplexem Layout (Spalten, spezielle Tabellen) empfiehlt es sich, diese vorab manuell in PDF zu exportieren und die fertige PDF anschließend mit diesem Tool zusammenzufügen.

## Deinstallation

```bash
rm ~/.local/bin/"PDF zusammenfügen.sh"
rm ~/.local/bin/advanced_dialog.py
rm ~/.local/share/icons/pdf-merge-icon.svg
rm ~/.local/share/nemo/actions/pdf-quick-merge.nemo_action
rm ~/.local/share/nemo/actions/pdf-advanced-merge.nemo_action
nemo -q && nemo &
```

---

## Lizenz

Dieses Projekt steht unter der [GNU General Public License v3.0](LICENSE) – Änderungen müssen ebenfalls Open Source bleiben.

## Hinweis

Der Code wurde vollständig mit KI generiert. Es funktioniert bei mir im Test wunderbar. Das ist mein erstes Projekt in GitHub. Nennt es gerne VibeCoding, aber seid bitte freundlich.
