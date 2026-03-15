#!/usr/bin/env bash
# Использование: ./video_quality_test.sh -o <оригинал> -d <тестируемое>

# --- Аргументы ---
while getopts "o:d:" opt; do
    case $opt in
        o) ORIGINAL="$OPTARG" ;;  # Оригинальное (эталонное) видео
        d) DISTORTED="$OPTARG" ;; # Тестируемое (сжатое/обработанное) видео
    esac
done

# --- Имя файла отчёта: дата + короткий хэш от путей и времени ---
DATE=$(date +"%Y%m%d_%H%M%S")
HASH=$(echo "${ORIGINAL}${DISTORTED}${DATE}" | sha256sum | cut -c1-8)
REPORT="result_vqt_${DATE}_${HASH}.md"

# --- Временный файл для JSON-вывода VMAF ---
TMP_JSON=$(mktemp /tmp/vmaf_XXXXXX.json)

# --- Запуск VMAF через ffmpeg ---
ffmpeg -hide_banner -loglevel warning \
    -i "$DISTORTED" -i "$ORIGINAL" \
    -lavfi "[0:v][1:v]libvmaf=log_fmt=json:log_path=${TMP_JSON}" \
    -f null -

# --- Извлечение среднего VMAF из JSON ---
VMAF=$(python3 -c "
import json
with open('$TMP_JSON') as f:
    d = json.load(f)
print(f\"{d['pooled_metrics']['vmaf']['mean']:.2f}\")
")

# --- Запись отчёта ---
cat > "$REPORT" <<MD
# Video Quality Report

| | |
|---|---|
| **Дата** | $(date "+%d.%m.%Y %H:%M:%S") |
| **Оригинал** | \`$ORIGINAL\` |
| **Тест** | \`$DISTORTED\` |
| **VMAF** | $VMAF / 100 |

MD

# --- Cleanup и вывод результата ---
rm -f "$TMP_JSON"
echo "VMAF: $VMAF → $REPORT"
