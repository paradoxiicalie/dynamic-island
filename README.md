<h1 align="center">DYNAMIC // ISLAND</h1>

<p align="center">
  <strong>Zero-Latency Native SystemAperture Engine for macOS</strong><br>
  Реверс-инжиниринг Apple Dynamic Island 1:1. Аппаратная интеграция с Liquid Retina XDR Notch и внешними мониторами. Чистый Swift / SwiftUI / AppKit. 0% CPU в режиме ожидания.
</p>

<p align="center">
  <a href="README.md"><strong>[ РУССКИЙ ]</strong></a> &nbsp;&bull;&nbsp; <a href="README.en.md"><strong>[ ENGLISH ]</strong></a>
</p>

<p align="center">
  <a href="#03--сборка-и-установка">
    <img src="https://img.shields.io/badge/СБОРКА-SWIFT_PM-E6DFD3?style=for-the-badge&labelColor=18181B&logo=swift&logoColor=E6DFD3" alt="Сборка Swift PM" />
  </a>
  <a href="#04--cli-и-ipc-управление">
    <img src="https://img.shields.io/badge/CLI-УПРАВЛЕНИЕ_IPC-E6DFD3?style=for-the-badge&labelColor=18181B&logo=gnubash&logoColor=E6DFD3" alt="CLI Управление" />
  </a>
  <a href="https://github.com/paradoxiicalie/dynamic-island/releases">
    <img src="https://img.shields.io/badge/РЕЛИЗЫ-СКАЧАТЬ_APP-E6DFD3?style=for-the-badge&labelColor=18181B&logo=apple&logoColor=E6DFD3" alt="Скачать релиз" />
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/АРХИТЕКТУРА-ZERO--LATENCY%20EVENT--DRIVEN-27272A?style=for-the-badge&labelColor=09090B&color=E4E4E7" alt="Архитектура" />
  <img src="https://img.shields.io/badge/РЕСУРСЫ-0%25%20IDLE%20CPU%20%7C%20LOW%20RAM-27272A?style=for-the-badge&labelColor=09090B&color=E4E4E7" alt="Ресурсы" />
  <img src="https://img.shields.io/badge/ПЛАТФОРМА-macOS%2014.0%2B%20(SONOMA%20%2F%20SEQUOIA)-27272A?style=for-the-badge&labelColor=09090B&color=E4E4E7" alt="Платформа" />
  <img src="https://img.shields.io/badge/АППАРАТНАЯ_ЧАСТЬ-APPLE%20SILICON%20%2B%20INTEL-27272A?style=for-the-badge&labelColor=09090B&color=E4E4E7" alt="Аппаратная часть" />
  <img src="https://img.shields.io/badge/ЛИЦЕНЗИЯ-MIT-27272A?style=for-the-badge&labelColor=09090B&color=E4E4E7" alt="Лицензия" />
</p>

---

### 01 // КОНЦЕПЦИЯ

**DYNAMIC // ISLAND** спроектирован как бескомпромиссная системная реализация архитектуры SystemAperture от Apple для компьютеров Mac. 

* **Zero-Latency Event-Driven ядро (0% CPU в режиме ожидания):** Полное отсутствие циклических таймеров опроса (`polling loops`). Вся обработка событий построена на прямых аппаратных прерываниях ядра IOKit (`IOPSNotificationCreateRunLoopSource`), низкоуровневых слушателях CoreAudio HAL и системных шинах `NSDistributedNotificationCenter` с мгновенной доставкой.
* **Монолитный капсульный рендеринг:** Корневой контейнер привязан к границам окна `GeometryReader` с монолитной черной капсулой на системном уровне окна `CGWindowLevelForKey(.screenSaverWindow) + 5`. Исключены любые визуальные артефакты обрезки краев, белые щели и выпадение контента за пределы капсулы при пружинных анимациях (`.spring(response: 0.42, dampingFraction: 0.82)`).
* **Адаптация под физический Notch и внешние дисплеи:** Движок автоматически считывает геометрию выреза Liquid Retina XDR через свойства `NSScreen.auxiliaryTopLeftArea` и `auxiliaryTopRightArea`. При подключении внешних мониторов без выреза остров автоматически трансформируется в парящую капсулу с выверенным отступом от строки меню.
* **Интерфейс высокой информационной плотности:** Строгая бруталистская монохромная эстетика, идентичная физическому поведению Dynamic Island на iPhone 15/16 Pro, с динамической цветовой адаптацией под медиаконтент в реальном времени.

---

### 02 // АРХИТЕКТУРА И МОДУЛИ

#### [ МЕДИАПЛЕЕР И ЭКСТРАКЦИЯ ПАЛИТРЫ ]
* **Двусторонний IPC (Spotify и Apple Music):** Выполнение предварительно скомпилированного байткода `NSAppleScript` в памяти без повторных накладных расходов на компиляцию текста скриптов.
* **Двухточечная экстракция цвета обложки:** Алгоритмический анализ пиксельной матрицы постера с выбором двух ключевых цветовых опорных точек (верхней и нижней) по яркости и насыщенности. Позволяет формировать динамический линейный вертикальный градиент эквалайзера 1:1 по оттенку обложки.
* **6-полосный спектральный анализатор:** Столбики эквалайзера выровнены строго по базовой нижней линии (`alignment: .bottom`) с шириной 2.8 pt, скруглением 1.4 pt и независимой пружинной динамикой высоты, идентичной поведению плеера iOS 18.
* **Развернутая карточка трека (348 pt):** Полноразмерная обложка, интерактивный таймлайн-скраббер с возможностью поиска по треку, кнопки паузы/переключения и мгновенный доступ к аудиомаршрутам.
* **Интеллектуальный буфер задержки:** 60-миллисекундный демпфер при смене трека и разблокировке экрана исключает паразитные скачки текста или кратковременное выпадение в режим ожидания (`idle`).

#### [ МАРШРУТИЗАЦИЯ АУДИО И AIRPODS ]
* **Аппаратный CoreAudio Listener:** Прямой перехват системных событий подключения и отключения аудиоустройств без задержки.
* **Route Controller:** Выдвижное меню со списком подключенных устройств (AirPods Pro, AirPods Max, встроенные динамики, внешние ЦАП).
* **Индикация заряда:** Отображение реального уровня заряда аккумулятора наушников и кейса в компактном и развернутом состояниях.

#### [ DROP SHELF // КАРМАН ДЛЯ ФАЙЛОВ ]
* **Drag-and-Drop в физический Notch:** При перетаскивании любого файла из Finder, рабочего стола или веб-браузера в область физического выреза активируется неоновая индикаторная рамка.
* **Полнофункциональный буфер файлов:** Карман удерживает файлы любого типа, отображая имя, размер и системную иконку QuickLook.
* **Действия в один клик:** Быстрое копирование пути (`Copy Path`), переход в Finder (`Reveal`), отправка через системный `Share Sheet` / AirDrop или удаление из кармана.
* **Обратный трансфер:** Возможность вытягивать файлы из Drop Shelf напрямую в окна Telegram, Slack, Mail, Xcode или терминала.

#### [ ЭКРАН БЛОКИРОВКИ И БИОМЕТРИЯ ]
* **Интеграция с экраном блокировки:** Определение событий блокировки дисплея (`com.apple.screenIsLocked`) и отображение индикатора закрытого замка.
* **Touch ID / Apple Watch Unlock:** Анимация разблокировки с превращением замка в раскрытый зеленый бейдж «Разблокировано» и воспроизведением тактильного аудиосигнала `unlock.caf`.

#### [ БАТАРЕЯ, MAGSAFE И ЭНЕРГОПОТРЕБЛЕНИЕ ]
* **Прямые уведомления ядра IOKit:** Мониторинг интерфейса электропитания Mac без опроса процессора.
* **Индикация зарядки MagSafe:** Всплывающий компактный баннер с текущим процентом заряда и аутентичным звуковым сопровождением `chime.caf`.
* **Алерты низкого заряда:** Предупреждающие баннеры при достижении порогов 20% и 10% оставшейся емкости аккумулятора.

#### [ ЖИВЫЕ АКТИВНОСТИ // SPLIT ISLAND ]
* **Мульти-активность:** При одновременной работе медиаплеера и системного таймера остров разделяется на два независимых интерактивных сегмента.
* **Leading Segment:** Компактная миниатюра обложки и 3-полосный пульсирующий эквалайзер.
* **Trailing Segment:** Иконка таймера и живой обратный отсчет в секундах.
* **Раздельные зоны клика:** Нажатие на левый пузырь раскрывает карточку трека, нажатие на правый пузырь — контроллер управления таймером.

#### [ АППАРАТНЫЕ ИНДИКАТОРЫ ПРИВАТНОСТИ ]
* Интегрированные аппаратные точки приватности (зеленая точка для веб-камеры FaceTime HD, оранжевая точка для микрофона), расположенные строго в границах выреза рядом с физическим сенсором камеры.

---

### 03 // СБОРКА И УСТАНОВКА

#### [ СРАВНИТЕЛЬНЫЙ АНАЛИЗ СРОКА ДЕЙСТВИЯ: MAC VS IOS ]

| Платформа | Метод установки | Срок действия | Требуется ли переподпись раз в 7 дней? |
| :--- | :--- | :--- | :---: |
| **macOS** | **Локальная сборка (Swift PM / Binary)** | **БЕССРОЧНО (ВЕЧНО)** | **НЕТ** |
| **macOS** | **Установка в /Applications** | **БЕССРОЧНО (ВЕЧНО)** | **НЕТ** |
| iOS | Бесплатный Apple ID (Sideloadly / AltStore) | 7 дней | **ДА (Требует авторесайна)** |
| iOS | Платный аккаунт Apple Developer ($99/год) | 365 дней | Раз в год |

> [!IMPORTANT]
> **Приложение на Mac работает вечно.** В macOS нативные локально скомпилированные бинарники не имеют 7-дневного ограничения, характерного для мобильной операционной системы iOS. После сборки и установки в директорию `/Applications` приложение DynamicIsland работает в фоновом режиме непрерывно и не требует повторных компиляций или обновления сертификатов.

---

#### Сборка из исходников (Swift Package Manager)

1. Клонируйте репозиторий:
   ```bash
   git clone https://github.com/paradoxiicalie/dynamic-island.git
   cd dynamic-island
   ```
2. Запустите автоматический установочный скрипт:
   ```bash
   ./scripts/install.sh
   ```
   *Скрипт выполнит сборку оптимизированного релиза через `swift build -c release`, упакует бандл `DynamicIsland.app` со всеми аудиофайлами `.caf`, скопирует его в `/Applications` и перезапустит процесс.*

---

#### Регистрация в автозапуск при входе в систему

Для постоянной работы приложения в фоне после перезагрузки компьютера:
* Нажмите на иконку острова в строке меню macOS (Menu Bar).
* Активируйте пункт **«Запуск при входе»** (появится отметка подтверждения).
* *Альтернативно через настройки macOS:* перейдите в *Системные настройки → Основные → Объекты входа* и добавьте `DynamicIsland.app`.

---

### 04 // CLI И IPC-УПРАВЛЕНИЕ

Управление островом и отправка событий могут производиться из любого терминала, скрипта или хоткея Raycast/Alfred через бинарный интерфейс командной строки:

| Флаг CLI | Назначение | Пример команды |
| :--- | :--- | :--- |
| `--toggle` | Переключить остров между компактным и развернутым состоянием | `DynamicIsland --toggle` |
| `--collapse` | Принудительно свернуть остров в компактную форму | `DynamicIsland --collapse` |
| `--expand-music` | Развернуть расширенный плеер трека | `DynamicIsland --expand-music` |
| `--expand-battery` | Развернуть детальную информацию о батарее | `DynamicIsland --expand-battery` |
| `--expand-timer` | Развернуть карточку таймера | `DynamicIsland --expand-timer` |
| `--routes` | Открыть селектор аудиовыходов и AirPods | `DynamicIsland --routes` |
| `--shelf` | Открыть или закрыть карман файлов Drop Shelf | `DynamicIsland --shelf` |
| `--shelf-add <path>` | Добавить указанный файл в карман Drop Shelf | `DynamicIsland --shelf-add ~/Downloads/document.pdf` |
| `--timer <sec> [label]` | Запустить обратный отсчет таймера на указанное число секунд | `DynamicIsland --timer 300 "Фокус"` |
| `--stop-timer` | Сбросить и остановить активный таймер | `DynamicIsland --stop-timer` |
| `--battery` | Показать алерт подключения питания MagSafe | `DynamicIsland --battery` |
| `--unlock` | Показать системный баннер разблокировки Touch ID | `DynamicIsland --unlock` |
| `--lock` | Перевести остров в режим заблокированного экрана | `DynamicIsland --lock` |
| `--airpods` | Показать всплывающий алерт подключения AirPods | `DynamicIsland --airpods` |
| `--alert <title> [sub] [icon] [color]` | Вывести кастомный системный алерт с иконкой SF Symbols | `DynamicIsland --alert "Компиляция" "Успешно" checkmark.circle green` |
| `--focus <name> [on\|off]` | Показать статус смены режима фокусирования | `DynamicIsland --focus "Кодинг" on` |
| `--brightness <0..100>` | Показать HUD изменения яркости дисплея | `DynamicIsland --brightness 80` |
| `--privacy <mic\|camera\|both\|off>` | Установить состояние аппаратных индикаторов приватности | `DynamicIsland --privacy camera` |

---

### 05 // ТЕХНИЧЕСКИЙ СТЕК

```text
[ ARCHITECTURE ]       Zero-Latency Event-Driven, Monolithic Geometry Lock, Notch-Native
[ RUNTIME & UI ]       Swift 5.10+, SwiftUI, AppKit (NSPanel, NSWindow.Level, CGWindowLevel)
[ KERNEL & HARDWARE ]  IOKit (IOPSNotificationCreateRunLoopSource), CoreAudio HAL, AVFoundation
[ MEDIA INTEROP ]      Compiled AppleScript Bytecode (Spotify & Apple Music), DistributedNotificationCenter
[ SOUND SYNTHESIS ]    Apple CoreAudio CAF Engine (Hardware Alert Acoustic Profiles)
[ COLOR EXTRACTION ]   Dual-Anchor Luminance & Saturation Color Extractor (RGB Gradient Fitting)
[ RESOURCE PROFILE ]   0% Idle CPU Usage, Zero Background Polling Loops, < 45 MB RSS Memory
[ PLATFORMS ]          macOS 14.0+ (Sonoma), macOS 15.0+ (Sequoia) | Apple Silicon (M1/M2/M3/M4) & Intel
```

---

### 06 // ЛИЦЕНЗИЯ

Проект распространяется под свободной лицензией **MIT**. Полный текст лицензии приведен в файле [LICENSE](LICENSE).
