#!/bin/bash
# Abhängigkeiten: libreoffice, pdftk, img2pdf, zenity, ghostscript, yad
# Installation: sudo bash install.sh

MODE="$1"
shift

TMPDIR=$(mktemp -d)

# Sperrdateien (LibreOffice .~lock.*#) herausfiltern
ORDERED_FILES=()
for F in "$@"; do
    BASENAME=$(basename "$F")
    [[ "$BASENAME" == .~lock.* ]] && continue
    ORDERED_FILES+=("$F")
done

if [ ${#ORDERED_FILES[@]} -eq 0 ]; then
    zenity --error --title="Fehler" --text="Keine verwertbaren Dateien ausgewählt."
    exit 1
fi

# ══════════════════════════════════════════════════════════════════════════════
# Gemeinsame Funktionen
# ══════════════════════════════════════════════════════════════════════════════

# Verarbeitet eine einzelne Datei und aktualisiert PDF_LIST/ERRORS/COUNTER
# Benötigt: TMPDIR, PDF_LIST, ERRORS, COUNTER im aufrufenden Scope
verarbeite_datei() {
    local FILE="$1"
    local EXT_LOWER BASENAME LO_OUT CONVERTED FILETYPE

    EXT_LOWER=$(echo "${FILE##*.}" | tr '[:upper:]' '[:lower:]')

    case "$EXT_LOWER" in
        pdf)
            PDF_LIST+=("$FILE")
            ;;
        doc|docx|odt|ods|odp|pptx|xlsx|txt|rtf)
            if ! command -v libreoffice &>/dev/null; then
                ERRORS+=("$(basename "$FILE") [LibreOffice nicht im PATH – Symlink prüfen]")
                return
            fi
            COUNTER=$((COUNTER+1))
            BASENAME=$(basename "${FILE%.*}")
            LO_OUT="$TMPDIR/$BASENAME.pdf"
            CONVERTED="$TMPDIR/${COUNTER}_$BASENAME.pdf"
            libreoffice --headless --norestore --convert-to pdf "$FILE" --outdir "$TMPDIR" 2>/dev/null
            if [ -f "$LO_OUT" ]; then
                mv "$LO_OUT" "$CONVERTED"
                PDF_LIST+=("$CONVERTED")
            else
                ERRORS+=("$(basename "$FILE")")
            fi
            ;;
        jpg|jpeg|png|gif|tiff|tif|bmp|webp)
            COUNTER=$((COUNTER+1))
            BASENAME=$(basename "${FILE%.*}")
            CONVERTED="$TMPDIR/${COUNTER}_$BASENAME.pdf"
            img2pdf "$FILE" -o "$CONVERTED" 2>/dev/null
            if [ -f "$CONVERTED" ]; then
                PDF_LIST+=("$CONVERTED")
            else
                ERRORS+=("$(basename "$FILE")")
            fi
            ;;
        *)
            FILETYPE=$(file --mime-type -b "$FILE")
            case "$FILETYPE" in
                image/jpeg|image/png|image/gif|image/tiff|image/bmp|image/webp)
                    COUNTER=$((COUNTER+1))
                    BASENAME=$(basename "$FILE")
                    CONVERTED="$TMPDIR/${COUNTER}_$BASENAME.pdf"
                    img2pdf "$FILE" -o "$CONVERTED" 2>/dev/null
                    if [ -f "$CONVERTED" ]; then
                        PDF_LIST+=("$CONVERTED")
                    else
                        ERRORS+=("$(basename "$FILE")")
                    fi
                    ;;
                application/pdf)
                    PDF_LIST+=("$FILE")
                    ;;
                *)
                    ERRORS+=("$(basename "$FILE") [nicht unterstützt: $FILETYPE]")
                    ;;
            esac
            ;;
    esac
}

konvertiere_dateien() {
    PDF_LIST=()
    ERRORS=()
    COUNTER=0

    for FILE in "${ORDERED_FILES[@]}"; do
        verarbeite_datei "$FILE"
    done

    if [ ${#ERRORS[@]} -gt 0 ]; then
        zenity --warning \
            --title="Hinweis" \
            --text="Folgende Dateien konnten nicht konvertiert werden:\n\n$(printf '%s\n' "${ERRORS[@]}")\n\nDie restlichen Dateien werden trotzdem zusammengefügt."
    fi

    if [ ${#PDF_LIST[@]} -eq 0 ]; then
        zenity --error --title="Fehler" --text="Keine verwertbaren Dateien gefunden. Abbruch."
        rm -rf "$TMPDIR"
        exit 1
    fi
}

speicherort_waehlen() {
    OUTPUT=$(zenity --file-selection \
        --save \
        --confirm-overwrite \
        --title="Speicherort und Dateiname wählen" \
        --filename="$HOME/zusammengefuehrt.pdf" \
        --file-filter="PDF-Dateien | *.pdf")

    [ -z "$OUTPUT" ] && { rm -rf "$TMPDIR"; exit 0; }
    [[ "$OUTPUT" != *.pdf ]] && OUTPUT="$OUTPUT.pdf"
}

zusammenfuegen() {
    MERGED="$TMPDIR/merged.pdf"
    pdftk "${PDF_LIST[@]}" cat output "$MERGED"

    if [ $? -ne 0 ]; then
        zenity --error --title="Fehler" --text="pdftk ist fehlgeschlagen."
        rm -rf "$TMPDIR"
        exit 1
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# QUICK MERGE – keine Dialoge, direkt zusammenfügen
# ══════════════════════════════════════════════════════════════════════════════

quick_merge() {
    speicherort_waehlen

    TOTAL=${#ORDERED_FILES[@]}
    ERRORS_FILE="$TMPDIR/errors.txt"
    PDFTK_LOG="$TMPDIR/pdftk.log"

    (
    PDF_LIST=()
    ERRORS=()
    COUNTER=0

    for IDX in "${!ORDERED_FILES[@]}"; do
        FILE="${ORDERED_FILES[$IDX]}"
        CURRENT=$((IDX + 1))
        echo $(( CURRENT * 90 / TOTAL ))
        echo "# Datei $CURRENT von $TOTAL: $(basename "$FILE")"
        verarbeite_datei "$FILE"
    done

    # Fehler an Datei weitergeben (Subshell-Variablen gehen sonst verloren)
    if [ ${#ERRORS[@]} -gt 0 ]; then
        printf '%s\n' "${ERRORS[@]}" > "$ERRORS_FILE"
    fi

    echo "95"
    echo "# PDF wird zusammengefügt..."

    if [ ${#PDF_LIST[@]} -gt 0 ]; then
        pdftk "${PDF_LIST[@]}" cat output "$OUTPUT" 2> "$PDFTK_LOG"
    else
        echo "Keine verwertbaren Dateien gefunden." > "$PDFTK_LOG"
    fi
    echo "100"
    ) | zenity --progress \
        --title="PDF Quick Merge" \
        --text="Dateien werden verarbeitet..." \
        --percentage=0 \
        --auto-close \
        --no-cancel \
        --width=350

    # Ergebnis auswerten – außerhalb der Subshell, damit Fehler sichtbar sind
    ERROR_CONTENT=""
    [ -s "$ERRORS_FILE" ] && ERROR_CONTENT=$(cat "$ERRORS_FILE")

    if [ -f "$OUTPUT" ]; then
        if [ -n "$ERROR_CONTENT" ]; then
            zenity --warning \
                --title="Teilweise erfolgreich" \
                --text="PDF wurde erstellt, aber folgende Dateien konnten nicht konvertiert werden:\n\n$ERROR_CONTENT\n\nGespeichert als:\n<b>$OUTPUT</b>" \
                --width=450
        else
            zenity --info \
                --title="Fertig!" \
                --text="PDF erfolgreich erstellt:\n<b>$OUTPUT</b>" \
                --width=400
        fi
    else
        PDFTK_ERR=""
        [ -s "$PDFTK_LOG" ] && PDFTK_ERR=$(cat "$PDFTK_LOG")
        FEHLER_TEXT="PDF konnte nicht erstellt werden."
        [ -n "$ERROR_CONTENT" ] && FEHLER_TEXT="$FEHLER_TEXT\n\nFehlgeschlagene Dateien:\n$ERROR_CONTENT"
        [ -n "$PDFTK_ERR" ]     && FEHLER_TEXT="$FEHLER_TEXT\n\nDetails:\n$PDFTK_ERR"
        zenity --error \
            --title="Fehler" \
            --text="$FEHLER_TEXT" \
            --width=450
    fi

    rm -rf "$TMPDIR"
}

# ══════════════════════════════════════════════════════════════════════════════
# ADVANCED MERGE – Reihenfolge, Orientierung, Ghostscript
# ══════════════════════════════════════════════════════════════════════════════

advanced_merge() {
    # ── Kombinierter Dialog: Reihenfolge + Optionen ──────────────────────────
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    DIALOG_OUTPUT=$(python3 "$SCRIPT_DIR/advanced_dialog.py" "${ORDERED_FILES[@]}")

    [ $? -ne 0 ] && { rm -rf "$TMPDIR"; exit 0; }

    # Ergebnis parsen
    ORDERED_FILES=()
    SIZE_OPT=""
    ORIENT_OPT=""
    OPEN_AFTER=""
    while IFS= read -r line; do
        case "$line" in
            FILE=*)   ORDERED_FILES+=("${line#FILE=}") ;;
            SIZE=*)   SIZE_OPT="${line#SIZE=}" ;;
            ORIENT=*) ORIENT_OPT="${line#ORIENT=}" ;;
            OPEN=*)   OPEN_AFTER="${line#OPEN=}" ;;
        esac
    done <<< "$DIALOG_OUTPUT"

    # ── Speicherort, Konvertierung, Zusammenfügen ────────────────────────────
    speicherort_waehlen
    konvertiere_dateien
    zusammenfuegen

    # ── Nachbearbeitung je nach Optionen ─────────────────────────────────────
    if [ "$SIZE_OPT" = "original" ] && [ "$ORIENT_OPT" = "original" ]; then
        # Keine Anpassung – direkt kopieren
        cp "$MERGED" "$OUTPUT"
    elif [ "$SIZE_OPT" = "a4" ] && [ "$ORIENT_OPT" = "original" ]; then
        # A4 + Original-Ausrichtung: jede Seite einzeln verarbeiten,
        # damit Querformat-Seiten als A4-Querformat erhalten bleiben
        PAGE_COUNT=$(pdftk "$MERGED" dump_data | grep "NumberOfPages" | awk '{print $2}')
        A4_PAGES=()

        (
        for ((i=1; i<=PAGE_COUNT; i++)); do
            PAGE_PDF="$TMPDIR/page_${i}.pdf"
            PAGE_A4="$TMPDIR/page_${i}_a4.pdf"
            pdftk "$MERGED" cat "$i" output "$PAGE_PDF"

            # Seitenmaße und Rotation auslesen
            PAGE_DATA=$(pdftk "$PAGE_PDF" dump_data)
            W=$(echo "$PAGE_DATA" | grep "PageMediaDimensions" | head -1 | awk '{print $2}')
            H=$(echo "$PAGE_DATA" | grep "PageMediaDimensions" | head -1 | awk '{print $3}')
            ROT=$(echo "$PAGE_DATA" | grep "PageMediaRotation" | head -1 | awk '{print $2}')

            # Bei Rotation 90°/270° sind Breite und Höhe vertauscht
            if [ "$ROT" = "90" ] || [ "$ROT" = "270" ]; then
                TEMP="$W"; W="$H"; H="$TEMP"
            fi

            # Querformat erkennen (effektive Breite > Höhe)
            if (( $(echo "$W > $H" | bc -l) )); then
                GS_W=841.89; GS_H=595.28
            else
                GS_W=595.28; GS_H=841.89
            fi

            gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite \
               -dPDFFitPage -dFIXEDMEDIA -dAutoRotatePages=/None \
               -dDEVICEWIDTHPOINTS="$GS_W" -dDEVICEHEIGHTPOINTS="$GS_H" \
               -sOutputFile="$PAGE_A4" "$PAGE_PDF"

            A4_PAGES+=("$PAGE_A4")
            echo $(( i * 100 / PAGE_COUNT ))
            echo "# Seite $i von $PAGE_COUNT wird auf A4 angepasst..."
        done

        pdftk "${A4_PAGES[@]}" cat output "$OUTPUT"
        echo "100"
        ) | zenity --progress \
            --title="A4-Anpassung" \
            --text="Seiten werden auf A4 angepasst..." \
            --percentage=0 \
            --auto-close \
            --no-cancel \
            --width=350
    elif [ "$SIZE_OPT" = "original" ] && [ "$ORIENT_OPT" != "original" ]; then
        # Original-Größe + feste Ausrichtung: jede Seite einzeln drehen
        # (nur wenn Seite nicht bereits in gewünschter Ausrichtung ist)
        PAGE_COUNT=$(pdftk "$MERGED" dump_data | grep "NumberOfPages" | awk '{print $2}')
        ROTATED_PAGES=()

        (
        for ((i=1; i<=PAGE_COUNT; i++)); do
            PAGE_PDF="$TMPDIR/page_${i}.pdf"
            PAGE_OUT="$TMPDIR/page_${i}_rot.pdf"
            pdftk "$MERGED" cat "$i" output "$PAGE_PDF"

            # Seitenmaße und Rotation auslesen
            PAGE_DATA=$(pdftk "$PAGE_PDF" dump_data)
            W=$(echo "$PAGE_DATA" | grep "PageMediaDimensions" | head -1 | awk '{print $2}')
            H=$(echo "$PAGE_DATA" | grep "PageMediaDimensions" | head -1 | awk '{print $3}')
            ROT=$(echo "$PAGE_DATA" | grep "PageMediaRotation" | head -1 | awk '{print $2}')

            # Bei Rotation 90°/270° sind Breite und Höhe effektiv vertauscht
            if [ "$ROT" = "90" ] || [ "$ROT" = "270" ]; then
                TEMP="$W"; W="$H"; H="$TEMP"
            fi

            # Aktuelle Orientierung feststellen
            IS_LANDSCAPE=0
            if (( $(echo "$W > $H" | bc -l) )); then
                IS_LANDSCAPE=1
            fi

            # Drehen nur wenn aktuelle Ausrichtung nicht passt
            if [ "$ORIENT_OPT" = "querformat" ] && [ "$IS_LANDSCAPE" = "0" ]; then
                pdftk "$PAGE_PDF" cat 1east output "$PAGE_OUT"
            elif [ "$ORIENT_OPT" = "hochformat" ] && [ "$IS_LANDSCAPE" = "1" ]; then
                pdftk "$PAGE_PDF" cat 1east output "$PAGE_OUT"
            else
                cp "$PAGE_PDF" "$PAGE_OUT"
            fi

            ROTATED_PAGES+=("$PAGE_OUT")
            echo $(( i * 100 / PAGE_COUNT ))
            echo "# Seite $i von $PAGE_COUNT wird gedreht..."
        done

        pdftk "${ROTATED_PAGES[@]}" cat output "$OUTPUT"
        echo "100"
        ) | zenity --progress \
            --title="Ausrichtung ändern" \
            --text="Seiten werden gedreht..." \
            --percentage=0 \
            --auto-close \
            --no-cancel \
            --width=350
    else
        # SIZE=a4 + feste Ausrichtung: alle Seiten auf A4 zwingen
        GS_ARGS=(-dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite -dPDFFitPage -dFIXEDMEDIA)

        case "$ORIENT_OPT" in
            "hochformat")
                GS_ARGS+=(-dDEVICEWIDTHPOINTS=595.28 -dDEVICEHEIGHTPOINTS=841.89)
                ;;
            "querformat")
                GS_ARGS+=(-dDEVICEWIDTHPOINTS=841.89 -dDEVICEHEIGHTPOINTS=595.28)
                ;;
        esac

        gs "${GS_ARGS[@]}" -sOutputFile="$OUTPUT" "$MERGED"
    fi

    # Erfolg prüfen: Output-Datei muss existieren und nicht leer sein
    # ($? ist nach einer Pipe zu zenity unbrauchbar)
    if [ -s "$OUTPUT" ]; then
        zenity --info \
            --title="Fertig!" \
            --text="PDF erfolgreich erstellt:\n<b>$OUTPUT</b>" \
            --width=400
        [ "$OPEN_AFTER" = "yes" ] && xdg-open "$OUTPUT" &
    else
        zenity --error \
            --title="Fehler" \
            --text="PDF konnte nicht erstellt werden.\n\nDie Nachbearbeitung (Größe/Ausrichtung) ist fehlgeschlagen." \
            --width=450
    fi

    rm -rf "$TMPDIR"
}

# ══════════════════════════════════════════════════════════════════════════════
# Modus starten
# ══════════════════════════════════════════════════════════════════════════════

case "$MODE" in
    --quick)    quick_merge ;;
    --advanced) advanced_merge ;;
    *)
        zenity --error --title="Fehler" --text="Unbekannter Modus: $MODE\n\nVerwendung:\n  $0 --quick DATEIEN...\n  $0 --advanced DATEIEN..."
        exit 1
        ;;
esac