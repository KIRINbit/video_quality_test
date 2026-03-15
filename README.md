# Video Quality Test

Инструмент для автоматической оценки качества видео на основе метрик VMAF, PSNR и SSIM. Генерирует Markdown-отчёт с результатами анализа.

---

## Зависимости

- `ffmpeg` (собранный с поддержкой `libvmaf`)
- `python3`

### Установка на Fedora

```bash
sudo dnf install ffmpeg python3
```

---

## Установка

```bash
git clone https://github.com/KIRINbit/video_quality_test.git
cd video_quality_test
chmod +x video_quality_test.sh
```

---

## Использование

```
./video_quality_test.sh [ОПЦИИ] -o ОРИГИНАЛ -d ТЕСТ_1 [-d ТЕСТ_2 ...]

Обязательные опции:
        -o, --original FILE          Путь к оригинальному видео
        -d, --distorted FILE         Путь к тестируемому видео (можно указывать несколько раз)

Необязательные опции:
        -m, --metrics LIST           Метрики для расчёта: vmaf,psnr,ssim (по умолчанию: все три)
        -p, --output-dir DIR         Каталог для сохранения отчётов (по умолчанию: ~/vqt_reports)

Прочие опции:
        -h, --help                   Показать эту справку
```

### Примеры

Базовый запуск:
```bash
./video_quality_test.sh -o original.mkv -d test.mkv
```

Сравнение нескольких файлов:
```bash
./video_quality_test.sh -o original.mkv -d test_1.mkv -d test_2.mkv -d test_3.mkv
```

Только VMAF и PSNR:
```bash
./video_quality_test.sh -o original.mkv -d test.mkv -m vmaf,psnr
```

Указать каталог для отчётов:
```bash
./video_quality_test.sh -o original.mkv -d test.mkv -p ~/my_reports
```

---

## Пример отчёта

Отчёты сохраняются в `~/vqt_reports/` в формате `result_vqt_<дата>_<хэш>.md`.

```
# Video Quality Report

**Дата:** 15.03.2026 14:12:29
**Оригинал:** `/home/user/videos/original.mkv`
**Метрики:** vmaf,psnr,ssim

---

## `test_crf23.mkv`

| Метрика | Значение |
|---------|----------|
| **VMAF** | 94.3821 / 100 |
| **PSNR** | 42.1054 dB |
| **SSIM** | 0.9912 |

**Путь:** `/home/user/videos/test_crf23.mkv`

---

## `test_crf40.mkv`

| Метрика | Значение |
|---------|----------|
| **VMAF** | 76.5243 / 100 |
| **PSNR** | 33.8871 dB |
| **SSIM** | 0.9541 |

**Путь:** `/home/user/videos/test_crf40.mkv`

---
```
