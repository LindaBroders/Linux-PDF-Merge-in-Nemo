#!/bin/bash
# install.sh – Installiert "PDF zusammenfügen" und alle Abhängigkeiten

SCRIPT_NAME="PDF zusammenfügen.sh"
ICON_NAME="pdf-merge-icon.svg"
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
INSTALL_DIR="$REAL_HOME/.local/bin"
ICON_DIR="$REAL_HOME/.local/share/icons"
NEMO_ACTIONS_DIR="$REAL_HOME/.local/share/nemo/actions"

echo ""
echo "=== PDF zusammenfügen – Installer ==="
echo ""
echo "Dieses Skript führt folgende Schritte aus:"
echo "  1. Prüft ob folgende Abhängigkeiten installiert sind:"
echo "     libreoffice, pdftk, img2pdf, zenity, ghostscript, yad"
echo "  2. Installiert fehlende Pakete automatisch (apt)"
echo "  3. Kopiert das Skript und Icon nach $INSTALL_DIR/"
echo "  4. Richtet drei Nemo-Rechtsklick-Einträge ein:"
echo "     - PDF Quick Merge"
echo "     - PDF Advanced Merge"
echo "     - Als PDF konvertieren"
echo ""

# Prüfen ob als root ausgeführt
if [ "$EUID" -ne 0 ]; then
    echo "FEHLER: Bitte mit sudo ausführen: sudo bash install.sh"
    exit 1
fi

# Prüfen ob Hauptskript vorhanden ist
if [ ! -f "$SCRIPT_NAME" ]; then
    echo "FEHLER: '$SCRIPT_NAME' nicht gefunden."
    echo "Installer muss aus dem Repository-Ordner ausgeführt werden."
    exit 1
fi

# Einmalige Bestätigung
read -rp "Fortfahren? (j/n): " ANSWER
if [[ "$ANSWER" != "j" && "$ANSWER" != "J" ]]; then
    echo "Installation abgebrochen."
    exit 0
fi

echo ""

# ── Schritt 1: Abhängigkeiten prüfen ─────────────────────────────────────────
echo "→ Prüfe Abhängigkeiten..."
NEEDED=()
for CMD in libreoffice pdftk img2pdf zenity gs yad; do
    if command -v "$CMD" &>/dev/null; then
        echo "  ✓ $CMD – bereits installiert"
    elif [ "$CMD" = "libreoffice" ]; then
        # Manuelle Installation in /opt/ erkennen (z.B. von libreoffice.org)
        LO_OPT=$(find /opt -maxdepth 3 -name "soffice" 2>/dev/null | head -1)
        if [ -n "$LO_OPT" ]; then
            echo "  → LibreOffice in $LO_OPT gefunden (manuelle Installation)"
            ln -sf "$LO_OPT" /usr/local/bin/libreoffice
            ln -sf "$LO_OPT" /usr/local/bin/soffice
            echo "  ✓ libreoffice – Symlink nach /usr/local/bin/ erstellt"
        else
            echo "  ✗ $CMD – fehlt"
            NEEDED+=("$CMD")
        fi
    else
        echo "  ✗ $CMD – fehlt"
        NEEDED+=("$CMD")
    fi
done

# ── Schritt 2: Fehlende Pakete installieren ───────────────────────────────────
if [ ${#NEEDED[@]} -gt 0 ]; then
    # gs → ghostscript im Paketnamen
    PACKAGES=()
    for CMD in "${NEEDED[@]}"; do
        if [ "$CMD" = "gs" ]; then
            PACKAGES+=("ghostscript")
        else
            PACKAGES+=("$CMD")
        fi
    done

    echo ""
    echo "→ Installiere fehlende Pakete: ${PACKAGES[*]} ..."
    apt-get update -qq
    apt-get install -y "${PACKAGES[@]}"

    # Verifizieren
    echo ""
    echo "→ Prüfe Installation..."
    FAILED=()
    for CMD in "${NEEDED[@]}"; do
        if command -v "$CMD" &>/dev/null; then
            echo "  ✓ $CMD"
        else
            echo "  ✗ $CMD – Installation fehlgeschlagen"
            FAILED+=("$CMD")
        fi
    done

    if [ ${#FAILED[@]} -gt 0 ]; then
        echo ""
        echo "FEHLER: Nicht alle Pakete konnten installiert werden."
        printf '  - %s\n' "${FAILED[@]}"
        echo "Bitte manuell nachinstallieren und Installer erneut starten."
        exit 1
    fi
else
    echo ""
    echo "  Alle Abhängigkeiten sind bereits installiert."
fi

# ── Schritt 3: Skript und Icon installieren ──────────────────────────────────
echo ""
echo "→ Installiere Skript nach $INSTALL_DIR/ ..."
sudo -u "$REAL_USER" mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_NAME" "$INSTALL_DIR/"
cp "advanced_dialog.py" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
chmod +x "$INSTALL_DIR/advanced_dialog.py"
chown "$REAL_USER:$REAL_USER" "$INSTALL_DIR/$SCRIPT_NAME"
chown "$REAL_USER:$REAL_USER" "$INSTALL_DIR/advanced_dialog.py"

echo "→ Installiere Icon nach $ICON_DIR/ ..."
sudo -u "$REAL_USER" mkdir -p "$ICON_DIR"
cp "$ICON_NAME" "$ICON_DIR/"
chown "$REAL_USER:$REAL_USER" "$ICON_DIR/$ICON_NAME"

# ── Schritt 4: Nemo-Integration einrichten ────────────────────────────────────
echo "→ Richte Nemo-Rechtsklick-Integration ein..."
sudo -u "$REAL_USER" mkdir -p "$NEMO_ACTIONS_DIR"

# Quick Merge
cat > "$NEMO_ACTIONS_DIR/pdf-quick-merge.nemo_action" << EOF
[Nemo Action]
Name=PDF Quick Merge
Comment=Dateien direkt zu einem PDF zusammenfügen
Exec=bash "$INSTALL_DIR/$SCRIPT_NAME" --quick %F
Icon-Name=$ICON_DIR/$ICON_NAME
Selection=Any
Extensions=pdf;doc;docx;odt;ods;odp;pptx;xlsx;txt;rtf;jpg;jpeg;png;gif;tiff;tif;bmp;webp;
EOF
chown "$REAL_USER:$REAL_USER" "$NEMO_ACTIONS_DIR/pdf-quick-merge.nemo_action"

# Advanced Merge
cat > "$NEMO_ACTIONS_DIR/pdf-advanced-merge.nemo_action" << EOF
[Nemo Action]
Name=PDF Advanced Merge
Comment=Dateien mit Reihenfolge und Optionen zu einem PDF zusammenfügen
Exec=bash "$INSTALL_DIR/$SCRIPT_NAME" --advanced %F
Icon-Name=$ICON_DIR/$ICON_NAME
Selection=Any
Extensions=pdf;doc;docx;odt;ods;odp;pptx;xlsx;txt;rtf;jpg;jpeg;png;gif;tiff;tif;bmp;webp;
EOF
chown "$REAL_USER:$REAL_USER" "$NEMO_ACTIONS_DIR/pdf-advanced-merge.nemo_action"

# Als PDF konvertieren (Batch – jede Datei einzeln)
cat > "$NEMO_ACTIONS_DIR/pdf-convert.nemo_action" << EOF
[Nemo Action]
Name=Als PDF konvertieren
Comment=Jede markierte Datei einzeln als PDF im selben Ordner speichern
Exec=bash "$INSTALL_DIR/$SCRIPT_NAME" --convert %F
Icon-Name=$ICON_DIR/$ICON_NAME
Selection=Any
Extensions=doc;docx;odt;ods;odp;pptx;xlsx;txt;rtf;jpg;jpeg;png;gif;tiff;tif;bmp;webp;
EOF
chown "$REAL_USER:$REAL_USER" "$NEMO_ACTIONS_DIR/pdf-convert.nemo_action"

# Alte Action-Datei entfernen (falls von v1.0 vorhanden)
rm -f "$NEMO_ACTIONS_DIR/pdf-zusammenfuegen.nemo_action"

# ── Fertig ────────────────────────────────────────────────────────────────────
echo ""
echo "=== Installation erfolgreich abgeschlossen! ==="
echo ""
echo "Nemo neu starten um die Rechtsklick-Einträge zu aktivieren:"
echo "  nemo -q && nemo &"
echo ""
echo "Neue Rechtsklick-Einträge:"
echo "  • PDF Quick Merge      – direkt zusammenfügen (Ordner der Quelldatei, Merge.pdf)"
echo "  • PDF Advanced Merge   – Reihenfolge & Optionen"
echo "  • Als PDF konvertieren – jede Datei einzeln als PDF (A4)"
echo ""