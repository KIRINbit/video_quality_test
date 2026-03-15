#!/usr/bin/env bash
# Использование: ./video_quality_test.sh -o <оригинал> -d <тестируемое>

# --- Справка ---
usage() {
    echo "Использование: video_quality_test.sh [ОПЦИИ] -o ОРИГИНАЛ -d ТЕСТ_1]"
    echo ""
    echo "Обязательные опции:"
    echo "        -o, --original FILE    Путь к оригинальному видео"
    echo "        -d, --distorted FILE   Путь к тестируемому видео"
    echo ""
    echo "Прочие опции:"
    echo "        -h, --help             Показать эту справку"
    exit 0
}

# --- Аргументы ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--original)  ORIGINAL="$2";  shift 2 ;;
        -d|--distorted) DISTORTED="$2"; shift 2 ;;
        -h|--help)      usage ;;
        *) shift ;;
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
") || { rm -f "$TMP_JSON"; exit 1; }

# --- Запись отчёта ---
cat > "$REPORT" <<MD
# Video Quality Report

| | |
|---|---|
| **Дата** | $(date "+%d.%m.%Y %H:%М:%S") |
| **Оригинал** | \`$ORIGINAL\` |
| **Тест** | \`$DISTORTED\` |
| **VMAF** | $VMAF / 100 |

MD

# --- Cleanup и вывод результата ---
rm -f "$TMP_JSON"
echo "VMAF: $VMAF → $REPORT"
