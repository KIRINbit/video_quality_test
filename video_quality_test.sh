#!/usr/bin/env bash
# Использование: ./video_quality_test.sh -o <оригинал> -d <тест_1> [-d <тест_2> ...]

# --- Справка ---
usage() {
    echo "Использование: video_quality_test.sh [ОПЦИИ] -o ОРИГИНАЛ -d ТЕСТ_1 [-d ТЕСТ_2 ...]"
    echo ""
    echo "Обязательные опции:"
    echo "        -o, --original FILE          Путь к оригинальному видео"
    echo "        -d, --distorted FILE         Путь к тестируемому видео (можно указывать несколько раз)"
    echo ""
    echo "Необязательные опции:"
    echo "        -m, --metrics LIST           Метрики для расчёта: vmaf,psnr,ssim (по умолчанию: все три)"
    echo "        -p, --output-dir DIR         Каталог для сохранения отчётов (по умолчанию: ~/vqt_reports)"
    echo "        -v, --verbosity LEVEL        Подробность отчёта: min, full (по умолчанию: min)"
    echo ""
    echo "Прочие опции:"
    echo "        -h, --help                   Показать эту справку"
    exit 0
}

# --- Значения по умолчанию ---
OUTPUT_DIR="$HOME/vqt_reports"
METRICS="vmaf,psnr,ssim"
VERBOSITY="min"
DISTORTED_FILES=()

# --- Аргументы ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--original)   ORIGINAL="$2";           shift 2 ;;
        -d|--distorted)  DISTORTED_FILES+=("$2"); shift 2 ;;
        -m|--metrics)    METRICS="$2";             shift 2 ;;
        -p|--output-dir) OUTPUT_DIR="$2";          shift 2 ;;
        -v|--verbosity)  VERBOSITY="$2";           shift 2 ;;
        -h|--help)       usage ;;
        *) shift ;;
    esac
done

# --- Валидация аргументов ---
if [[ -z "$ORIGINAL" ]]; then
    echo "Ошибка: не указан оригинал (-o / --original)" >&2; exit 1
fi
if [[ ${#DISTORTED_FILES[@]} -eq 0 ]]; then
    echo "Ошибка: не указано ни одного тестируемого файла (-d / --distorted)" >&2; exit 1
fi
if [[ ! -f "$ORIGINAL" ]]; then
    echo "Ошибка: файл оригинала не найден: $ORIGINAL" >&2; exit 1
fi
for F in "${DISTORTED_FILES[@]}"; do
    if [[ ! -f "$F" ]]; then
        echo "Ошибка: файл не найден: $F" >&2; exit 1
    fi
done

# --- Валидация метрик ---
VALID_METRICS=("vmaf" "psnr" "ssim")
IFS=',' read -ra REQUESTED_METRICS <<< "$METRICS"
for M in "${REQUESTED_METRICS[@]}"; do
    VALID=false
    for V in "${VALID_METRICS[@]}"; do
        [[ "$M" == "$V" ]] && VALID=true && break
    done
    if ! $VALID; then
        echo "Ошибка: неизвестная метрика '$M'. Доступные: vmaf, psnr, ssim" >&2; exit 1
    fi
done

# --- Валидация verbosity ---
if [[ "$VERBOSITY" != "min" && "$VERBOSITY" != "full" ]]; then
    echo "Ошибка: неизвестный уровень подробности '$VERBOSITY'. Доступные: min, full" >&2; exit 1
fi

# --- Определяем какие метрики считать ---
DO_VMAF=false; DO_PSNR=false; DO_SSIM=false
[[ "$METRICS" == *"vmaf"* ]] && DO_VMAF=true
[[ "$METRICS" == *"psnr"* ]] && DO_PSNR=true
[[ "$METRICS" == *"ssim"* ]] && DO_SSIM=true

# --- Создаём каталог если не существует ---
mkdir -p "$OUTPUT_DIR" || { echo "Ошибка: не удалось создать каталог: $OUTPUT_DIR" >&2; exit 1; }

# --- Имя файла отчёта: дата + короткий хэш ---
DATE=$(date +"%Y%m%d_%H%M%S")
HASH=$(echo "${ORIGINAL}${DISTORTED_FILES[*]}${DATE}" | sha256sum | cut -c1-8)
REPORT="${OUTPUT_DIR}/result_vqt_${DATE}_${HASH}.md"

# --- Размер файла: байты + человекочитаемый формат ---
human_size() {
    local bytes=$1
    python3 -c "
b = $bytes
if b >= 1024**3:
    print(f'{b:,} байт ({b/1024**3:.2f} ГБ)'.replace(',', ' '))
elif b >= 1024**2:
    print(f'{b:,} байт ({b/1024**2:.2f} МБ)'.replace(',', ' '))
else:
    print(f'{b:,} байт ({b/1024:.2f} КБ)'.replace(',', ' '))
"
}

# --- Размер оригинала ---
ORI_BYTES=$(stat -c%s "$ORIGINAL")
ORI_SIZE=$(human_size "$ORI_BYTES")

# --- Заголовок отчёта ---
cat > "$REPORT" <<MD
# Video Quality Report

**Дата:** $(date "+%d.%m.%Y %H:%M:%S")  
**Оригинал:** \`$ORIGINAL\`  
**Метрики:** $METRICS

---

MD

# --- Прогон метрик для каждого тестируемого файла ---
for DISTORTED in "${DISTORTED_FILES[@]}"; do
    echo "Обработка: $DISTORTED"

    TMP_VMAF=$(mktemp /tmp/vmaf_XXXXXX.json)
    TMP_PSNR=$(mktemp /tmp/psnr_XXXXXX.log)
    TMP_SSIM=$(mktemp /tmp/ssim_XXXXXX.log)

    VMAF_SCORE="—"; PSNR_SCORE="—"; SSIM_SCORE="—"
    PSNR_Y="—"; PSNR_U="—"; PSNR_V="—"
    SSIM_Y="—"; SSIM_U="—"; SSIM_V="—"

    if $DO_VMAF; then
        ffmpeg -hide_banner -loglevel warning \
            -i "$DISTORTED" -i "$ORIGINAL" \
            -lavfi "[0:v][1:v]libvmaf=log_fmt=json:log_path=${TMP_VMAF}" \
            -f null - || { rm -f "$TMP_VMAF" "$TMP_PSNR" "$TMP_SSIM" "$REPORT"; exit 1; }

        VMAF_SCORE=$(python3 -c "
import json
with open('$TMP_VMAF') as f:
    d = json.load(f)
print(f\"{d['pooled_metrics']['vmaf']['mean']:.4f}\")
") || { rm -f "$TMP_VMAF" "$TMP_PSNR" "$TMP_SSIM" "$REPORT"; exit 1; }
    fi

    if $DO_PSNR; then
        ffmpeg -hide_banner -loglevel warning \
            -i "$DISTORTED" -i "$ORIGINAL" \
            -lavfi "[0:v][1:v]psnr=stats_file=${TMP_PSNR}" \
            -f null - || { rm -f "$TMP_VMAF" "$TMP_PSNR" "$TMP_SSIM" "$REPORT"; exit 1; }

        # Извлекаем средние значения PSNR
        read PSNR_SCORE PSNR_Y PSNR_U PSNR_V <<< $(python3 -c "
import re
avg, y, u, v = [], [], [], []
with open('$TMP_PSNR') as f:
    for line in f:
        for val, lst in [(r'psnr_avg:([0-9.]+)', avg), (r'psnr_y:([0-9.]+)', y),
                         (r'psnr_u:([0-9.]+)', u), (r'psnr_v:([0-9.]+)', v)]:
            m = re.search(val, line)
            if m: lst.append(float(m.group(1)))
def mean(l): return f'{sum(l)/len(l):.4f}' if l else '—'
print(mean(avg), mean(y), mean(u), mean(v))
") || { rm -f "$TMP_VMAF" "$TMP_PSNR" "$TMP_SSIM" "$REPORT"; exit 1; }
    fi

    if $DO_SSIM; then
        ffmpeg -hide_banner -loglevel warning \
            -i "$DISTORTED" -i "$ORIGINAL" \
            -lavfi "[0:v][1:v]ssim=stats_file=${TMP_SSIM}" \
            -f null - || { rm -f "$TMP_VMAF" "$TMP_PSNR" "$TMP_SSIM" "$REPORT"; exit 1; }

        # Извлекаем средние значения SSIM
        read SSIM_SCORE SSIM_Y SSIM_U SSIM_V <<< $(python3 -c "
import re
all_, y, u, v = [], [], [], []
with open('$TMP_SSIM') as f:
    for line in f:
        for val, lst in [(r'All:([0-9.]+)', all_), (r'Y:([0-9.]+)', y),
                         (r'U:([0-9.]+)', u), (r'V:([0-9.]+)', v)]:
            m = re.search(val, line)
            if m: lst.append(float(m.group(1)))
def mean(l): return f'{sum(l)/len(l):.4f}' if l else '—'
print(mean(all_), mean(y), mean(u), mean(v))
") || { rm -f "$TMP_VMAF" "$TMP_PSNR" "$TMP_SSIM" "$REPORT"; exit 1; }
    fi

    # --- Размер тестируемого файла и степень сжатия ---
    DIST_BYTES=$(stat -c%s "$DISTORTED")
    DIST_SIZE=$(human_size "$DIST_BYTES")
    COMPRESSION=$(python3 -c "
ori=$ORI_BYTES; dist=$DIST_BYTES
ratio = ori/dist if dist > 0 else 0
reduction = (1 - dist/ori) * 100 if ori > 0 else 0
print(f'{ratio:.2f}x', f'{reduction:.2f}%')
")
    COMP_RATIO=$(echo "$COMPRESSION" | awk '{print $1}')
    COMP_REDUCTION=$(echo "$COMPRESSION" | awk '{print $2}')

    # --- Добавляем результат в отчёт ---
    cat >> "$REPORT" <<MD
## \`$(basename "$DISTORTED")\`

| Метрика | Значение |
|---------|----------|
MD

    $DO_VMAF && echo "| **VMAF** | $VMAF_SCORE / 100 |" >> "$REPORT"

    if $DO_PSNR; then
        echo "| **PSNR** | $PSNR_SCORE dB |" >> "$REPORT"
        if [[ "$VERBOSITY" == "full" ]]; then
            echo "| PSNR Y | $PSNR_Y dB |" >> "$REPORT"
            echo "| PSNR U | $PSNR_U dB |" >> "$REPORT"
            echo "| PSNR V | $PSNR_V dB |" >> "$REPORT"
        fi
    fi

    if $DO_SSIM; then
        echo "| **SSIM** | $SSIM_SCORE |" >> "$REPORT"
        if [[ "$VERBOSITY" == "full" ]]; then
            echo "| SSIM Y | $SSIM_Y |" >> "$REPORT"
            echo "| SSIM U | $SSIM_U |" >> "$REPORT"
            echo "| SSIM V | $SSIM_V |" >> "$REPORT"
        fi
    fi

    # --- Размеры файлов ---
    if [[ "$VERBOSITY" == "full" ]]; then
        cat >> "$REPORT" <<MD

| Параметр | Значение |
|----------|----------|
| **Размер оригинала** | $ORI_SIZE |
| **Размер результата** | $DIST_SIZE |
| **Степень сжатия** | $COMP_RATIO |
| **Уменьшение размера** | $COMP_REDUCTION |
MD
    fi

    echo "" >> "$REPORT"
    echo "**Путь:** \`$DISTORTED\`" >> "$REPORT"
    echo "" >> "$REPORT"
    echo "---" >> "$REPORT"
    echo "" >> "$REPORT"

    echo "  VMAF: $VMAF_SCORE | PSNR: $PSNR_SCORE | SSIM: $SSIM_SCORE"
    rm -f "$TMP_VMAF" "$TMP_PSNR" "$TMP_SSIM"
done

echo "Отчёт сохранён: $REPORT"
