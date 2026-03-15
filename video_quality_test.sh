#!/usr/bin/env bash
# Использование: ./video_quality_test.sh -o <оригинал> -d <тест_1> [-d <тест_2> ...]

# --- Справка ---
usage() {
    echo "Использование: video_quality_test.sh [ОПЦИИ] -o ОРИГИНАЛ -d ТЕСТ_1 [-d ТЕСТ_2 ...]"
    echo ""
    echo "Обязательные опции:"
    echo "        -o, --original FILE      Путь к оригинальному видео"
    echo "        -d, --distorted FILE     Путь к тестируемому видео (можно указывать несколько раз)"
    echo ""
    echo "Прочие опции:"
    echo "        -p, --output-dir DIR     Каталог для сохранения отчётов (по умолчанию: ~/vqt_reports)"
    echo "        -h, --help               Показать эту справку"
    exit 0
}

# --- Каталог для отчётов по умолчанию ---
OUTPUT_DIR="$HOME/vqt_reports"

# --- Массив тестируемых файлов ---
DISTORTED_FILES=()

# --- Аргументы ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--original)   ORIGINAL="$2";                  shift 2 ;;
        -d|--distorted)  DISTORTED_FILES+=("$2");         shift 2 ;;
        -p|--output-dir) OUTPUT_DIR="$2";                 shift 2 ;;
        -h|--help)       usage ;;
        *) shift ;;
    esac
done

# --- Создаём каталог если не существует ---
mkdir -p "$OUTPUT_DIR"

# --- Имя файла отчёта: дата + короткий хэш ---
DATE=$(date +"%Y%m%d_%H%M%S")
HASH=$(echo "${ORIGINAL}${DISTORTED_FILES[*]}${DATE}" | sha256sum | cut -c1-8)
REPORT="${OUTPUT_DIR}/result_vqt_${DATE}_${HASH}.md"

# --- Заголовок отчёта ---
cat > "$REPORT" <<MD
# Video Quality Report

**Дата:** $(date "+%d.%m.%Y %H:%M:%S")  
**Оригинал:** \`$ORIGINAL\`

---

MD

# --- Прогон VMAF для каждого тестируемого файла ---
for DISTORTED in "${DISTORTED_FILES[@]}"; do
    echo "Обработка: $DISTORTED"

    TMP_JSON=$(mktemp /tmp/vmaf_XXXXXX.json)

    # --- Запуск VMAF через ffmpeg ---
    ffmpeg -hide_banner -loglevel warning \
        -i "$DISTORTED" -i "$ORIGINAL" \
        -lavfi "[0:v][1:v]libvmaf=log_fmt=json:log_path=${TMP_JSON}" \
        -f null - || { rm -f "$TMP_JSON" "$REPORT"; exit 1; }

    # --- Извлечение среднего VMAF из JSON ---
    VMAF=$(python3 -c "
import json
with open('$TMP_JSON') as f:
    d = json.load(f)
print(f\"{d['pooled_metrics']['vmaf']['mean']:.2f}\")
") || { rm -f "$TMP_JSON" "$REPORT"; exit 1; }

    # --- Добавляем результат в отчёт ---
    cat >> "$REPORT" <<MD
## \`$(basename "$DISTORTED")\`

| | |
|---|---|
| **Путь** | \`$DISTORTED\` |
| **VMAF** | $VMAF / 100 |

---

MD

    echo "VMAF: $VMAF"
    rm -f "$TMP_JSON"
done

echo "Отчёт сохранён: $REPORT"
