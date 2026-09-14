# План интеграции протокола olcRTC в клиент

Документ описывает план добавления протокола **olcRTC** (WebRTC-туннель) в клиент по образцу уже выполненной интеграции **DNSTT** (см. [DNSTT_INTEGRATION.md](DNSTT_INTEGRATION.md)). Структура слоёв, приёмы сборки и решённые проблемы наследуются оттуда — здесь фиксируются только отличия и то, что предстоит написать.

> Статус документа: **план**. Часть фактов об olcRTC проверена по исходникам upstream (см. §7 «Что проверено»); пункты, помеченные **[discovery]**, требуют чтения кода olcRTC перед реализацией.

---

## 1. Что такое olcRTC и как он ложится в архитектуру

**olcRTC** (`github.com/openlibrecommunity/olcrtc`, Go 1.26, лицензия WTFPL) — зашифрованный туннель поверх **WebRTC**, маскирующий трафик под видеозвонки на легитимных сервисах (Jitsi, Yandex Telemost, WbStream). Клиент (`cnc`) поднимает локальный **SOCKS5-прокси**; сервер (`srv`) стоит на выходном узле. Транспорт — `pion/webrtc/v4` + `xtaci/smux` + `kcp-go` + XChaCha20-Poly1305 (`x/crypto`).

Ключевые следствия для интеграции:

1. **olcRTC — SOCKS5-прокси, а не IP-туннель.** В его `go.mod` нет TUN/netstack: он не принимает IP-пакеты. Значит мост «VpnService TUN → gVisor netstack → SOCKS5», уже построенный для dnstt, переиспользуется, а olcRTC подключается как SOCKS5-эндпоинт за ним.
2. **Туннель переносит stream (TCP-семантика), не IP.** Как и у dnstt: UDP-приложения напрямую не работают. SOCKS5 olcRTC поддерживает **только CONNECT** (D2: UDP ASSOCIATE и BIND отклоняются). Поэтому netstack проксирует DNS как DNS-over-TCP на :53, а прочий UDP дропает — тот же приём, что в dnstt. Это решение, не открытый вопрос.
3. **Нужна серверная пара.** Работает только против `olcrtc srv` на выходном узле **плюс** рабочая комната у провайдера (Jitsi/Telemost) с общим ключом. Как «one-click Amnezia-контейнер» это не упаковывается — только импорт готового конфига (как dnstt: Android-only, без docker-образа).
4. **WebRTC-сокеты должны обходить VPN.** pion динамически открывает много UDP-сокетов ICE + HTTPS к провайдеру; каждый обязан быть `protect()`-нут, иначе рекурсия в TUN или обрыв. olcRTC уже содержит механизм для этого (`internal/protect`, см. §3.1), но наружу его не пробрасывает — потребуется патч.

### Путь данных

```
[Android-приложения]
        │ IP-пакеты
        ▼
  [VpnService TUN fd]
        │
        ▼
[libolcrtc.so: gVisor netstack (tun2socks/core)]   ← переиспользуется из dnstt
   ├── TCP     ──▶ SOCKS5 CONNECT ─┐
   └── UDP:53  ──▶ DNS-over-TCP ───┤
                                   ▼
              [olcRTC cnc: локальный SOCKS5 на 127.0.0.1:PORT]
                                   │ smux ← WebRTC (pion) ← XChaCha20
                                   ▼
                    [WebRTC-провайдер: Jitsi / Telemost / WbStream]
                                   ▼
                          [olcrtc srv (VPS)]
                                   ▼
                             [Internet]
```

Все сокеты olcRTC (ICE UDP, HTTPS к провайдеру, DNS) идут **мимо** TUN через `protect()`.

---

## 2. Ключевое архитектурное решение: olcRTC как чёрный ящик через публичный API

У dnstt мы вендорили протокол и строили собственный `openStream()` над `smux.Session`. Для olcRTC это не нужно и невозможно (внутренние пакеты в `internal/`). Вместо этого используем **публичный API** `pkg/olcrtc/client`:

```go
type Config struct {
    Transport, Provider, RoomURL, ChannelID, Engine, URL string
    Token, ProviderToken, KeyHex, LocalAddr             string
    SOCKSUser, SOCKSPass, DNSServer, DeviceID, DeviceIDPath string
    Resolver         *net.Resolver
    TransportOptions TransportOptions
    Liveness         LivenessConfig
    Traffic          TrafficConfig
    Claims           map[string]any
    OnHealth         HealthFunc
}

func New(cfg Config) *Client
func (c *Client) Run(ctx context.Context) error
func (c *Client) RunWithReady(ctx context.Context, onReady func()) error
func (c *Client) RunWithAddress(ctx context.Context, onReady func(addr string)) error
```

Схема: `New(Config{ LocalAddr: "127.0.0.1:0", OnHealth: ... })` → `RunWithAddress(ctx, func(addr){ поднять netstack, целящийся в addr })`. `OnHealth` маппится на состояния connected/reconnecting/disconnected. Связанность с olcRTC минимальна — только документированный cnc-интерфейс, устойчиво к их beta-churn.

---

## 3. Состав по слоям

### 3.1. Go-ядро (`client/3rd/olcrtc/`) — ✅ РЕАЛИЗОВАНО И СОБРАНО

Зеркалит `client/3rd/dnstt/` **структурно**, но проще: olcRTC **не вендорится** — подключается обычной go.mod-зависимостью и используется как чёрный ящик через публичный пакет `github.com/openlibrecommunity/olcrtc/mobile`. Ни shim, ни патча, ни `COPYING.upstream` не нужно (изменение относительно первоначального плана — см. §4).

| Путь | Происхождение | Назначение | Статус |
|------|---------------|------------|--------|
| `go.mod` | наше | зависимость `olcrtc`, `tun2socks/v2 v2.7.0`, **pin gvisor** `v0.0.0-20260701204157-...` (грабля №7) | ✅ |
| `olcrtcclient/tunnel.go` | **наше** | `Config`/`Client`/`NewClient`/`Start`/`Stop`; обёртка `mobile.Runtime`; `protector` → `SocketProtector`; резерв loopback-порта | ✅ |
| `olcrtcclient/netstack.go` | **наше** — из dnstt | gVisor на TUN fd; `dialSocks()` = `net.Dial("tcp", socksAddr)`; UDP как dnstt (DNS-over-TCP + дроп, по D2) | ✅ |
| `olcrtcclient/socks.go` | **наше** — дословно из dnstt | SOCKS5 CONNECT к loopback-листенеру olcRTC | ✅ |
| `jni/main.go`, `jni/jni_helper.c/.h` | **наше** — из dnstt | экспорт `startTunnel(tunFd,mtu,provider,transport,roomUrl,key,dns,providerToken)`/`stopTunnel`, колбэки `protectSocket`/`nativeLog`/`notifyState` | ✅ (cgo, собирается NDK) |

Как работает `tunnel.go` (проверено сборкой против реального API olcRTC):
```go
rt := mobile.New()
rt.SetProvider(...); rt.SetTransport(...); rt.SetRoom(...); rt.SetKey(...)
rt.SetDNS(...); rt.SetProviderToken(...)
rt.SetSocksListenHost("127.0.0.1"); rt.SetSocksPort(port)
rt.SetProtector(protector{protectFn})   // process-global; protect ICE/HTTPS/WS
rt.Start(); rt.WaitReady(ms)             // поднять cnc SOCKS5
ns := newNetStack(tunFd, mtu, c)         // gVisor TUN → dialSocks() → socks5Connect
// Stop: ns.Close(); rt.Stop(ms); rt.SetProtector(nil)
```
Порт SOCKS5 резервируется через `pickLoopbackPort()` (listen на `127.0.0.1:0`, взять порт). `dialSocks` к loopback **не** протектится — этот сокет на OS-стеке и в TUN не попадает; наружу через protect ходит только сам olcRTC.

**protect() (риск №1 снят, D1).** Публичный `mobile.Runtime.SetProtector(p SocketProtector)` (где `SocketProtector interface{ Protect(fd int) bool }`) форвардит в `internal/protect.SetProtector`. На Android `ProtectedNet` включается автоматически (`runtime.GOOS=="android"`) и покрывает pion- и LiveKit-движки (детали в §5, блок D1). Поэтому доступ к protect есть из коробки — патч не нужен.

**Проверка сборки (WSL, Go 1.26).** `go build ./olcrtcclient` (GOOS=linux, CGO off) — успешно. Более того, **весь `.so` собран под NDK вживую** (см. §3.5): `libolcrtc.so` для android/arm64, экспортирует обе JNI-функции и **ровно один** `JNI_OnLoad` (грабли №2/№6 отсутствуют). olcRTC зафиксирован на `v0.0.2-0.20260905232354-189d16c093c4` (D5).

> ⚠️ **Обязательный флаг сборки:** линковка требует `-checklinkname=0` в `-ldflags`, т.к. pion тянет `github.com/wlynxg/anet`, использующий `//go:linkname` к `net.zoneCache` (Go 1.23+ иначе падает `invalid reference to net.zoneCache`). Уже добавлено в `android.cmake`.

> ⚠️ Транзитивно olcRTC тянет несколько малоизвестных личных модулей (`codeberg.org/rape4me/kc`, `github.com/zarazaex69/gr`, `github.com/zarazaex69/j`) и крупное дерево livekit/nats/redis/prometheus. На размер `.so` неиспользуемое не влияет (линкер отбросит), но с точки зрения supply-chain это стоит отметить: olcRTC — beta под WTFPL. Все версии запинены в `go.mod`/`go.sum`.

### 3.2. Android (`client/android/olcrtc/`) — ✅ РЕАЛИЗОВАНО

Зеркалит `client/android/dnstt/`. Созданы: `olcrtc/build.gradle.kts`, `OlcrtcNative.kt`, `OlcrtcConfig.kt`, `Olcrtc.kt`, `src/.../OlcrtcService.kt`. Правки: `settings.gradle.kts` (`include(":olcrtc")`), `build.gradle.kts` (`implementation(project(":olcrtc"))`), `VpnProto.kt` (`OLCRTC`), `AndroidManifest.xml` (сервис `:amneziaOlcrtcService`).

* **`OlcrtcNative.kt`** (копия `DnsttNative.kt`): `@Volatile var protector`, `stateListener`, `nativeLog`, `onStateChanged`; `external fun startTunnel(tunFd, tunMtu, provider, transport, roomUrl, channelId, key, dns): String?`, `stopTunnel(): String?`. `calculateMtu` убрать.
* **`Olcrtc.kt`** (копия `Dnstt.kt`, реализует `Protocol`): `detachFd()` (владение fd → Go), установка `OlcrtcNative.protector` на время сессии, парсинг `olcrtc_config_data`, валидация ключа (64 hex) и provider/transport из допустимых множеств.
* **`OlcrtcService.kt`**, `VpnProto.kt`, `AndroidManifest.xml`, `settings.gradle.kts`, `build.gradle.kts` — сервис в отдельном процессе `:amneziaOlcrtcService`.
* **Прямой CGO JNI, не gomobile** — иначе повторится грабля №2 (конфликт `libgojni.so` с `libxray.aar`). У olcRTC есть gomobile-биндинги — сознательно не берём.

### 3.3. C++ ядро (`client/core/`) — ✅ РЕАЛИЗОВАНО

> Файлы `core/**` и `core/configurators/*` подхватываются CMake через `GLOB_RECURSE`/`GLOB` — правки сборки для C++ не требуются. Не скомпилировано отдельно (полный Qt-билд тяжёлый); правки — механическое зеркало dnstt, финальная проверка на сборке APK (§3.5). Ниже — фактически изменённые места.

* **`utils/protocolEnum.h`** — добавить `Olcrtc` в enum `Proto` (рядом с `Dnstt`, [protocolEnum.h:28](client/core/utils/protocolEnum.h#L28)).
* **`utils/containerEnum.h`** — `DockerContainer::Olcrtc`.
* **`utils/containers/containerUtils.cpp`** — записи для `Olcrtc` во всех switch/map (имя «olcRTC», описание, `containerToProto`, флаги установки/поддержки), **только Android**, без docker-образа. Ориентир — ветки `DockerContainer::Dnstt` (строки ~82, 121, 202, 244, 263, 300, 314, 321).
* **`models/protocols/olcrtcProtocolConfig.{h,cpp}`** (копия `dnsttProtocolConfig`): поля `provider/transport/roomUrl/channelId/key/dns` (+ опц. `token`, `providerToken`, `name`), валидация (D4: `key` — ровно 64 hex; `provider` ∈ {jitsi, telemost, wbstream, none}; `transport` ∈ {datachannel, vp8channel, seichannel, videochannel}; `roomUrl` обязателен для всех провайдеров кроме сценариев создания комнаты «на лету»). **`engine` в конфиге не нужен** — выводится из провайдера (`Provider.Engine()`: jitsi→jitsi, telemost→goolom, wbstream→livekit); поле `Engine` в `client.Config` оставляем пустым (или задаём только при `provider=none`). Хранение `{"olcrtc": {"last_config": "<json>", "isThirdPartyConfig": true}}`; на Android — `olcrtc_config_data` со snake_case-ключами. Расчёт MTU выкинуть.
* **`models/protocolConfig.cpp`** — ветки `OlcrtcProtocolConfig` в `type()`, `fromJson()`, `getClientConfigJson()`, `hasClientConfig()`, `isThirdPartyConfig()` + `case Proto::Olcrtc` в фабрике (ориентир — строки 50, 125, 185, 250, 297, 337).
* **`controllers/selfhosted/importController.{h,cpp}`** — `ConfigTypes::Olcrtc`, ветка в разборе (`config.startsWith("olcrtc://")`, ~стр.166) и метод `extractOlcrtcConfig` (аналог `extractDnsttConfig`, ~стр.774). URI upstream **не описан** → определяем свой формат, напр.:
  `olcrtc://<keyHex>@<provider>/<roomUrlEncoded>?transport=<t>&channel=<id>&dns=<ip>`
* **`configurators/olcrtcConfigurator.{h,cpp}`** + ветка в `configuratorBase.cpp` — при необходимости генерации клиентского конфига.

### 3.4. UI (`client/ui/`) — ✅ РЕАЛИЗОВАНО

> Созданы `olcrtcConfigModel.{h,cpp}`, `PageProtocolOlcrtcSettings.qml`, `PageSetupWizardOlcrtcSettings.qml`. Правки: `coreController.{h,cpp}` (регистрация `OlcrtcConfigModel`, передача в installUiController), `installUiController.{h,cpp}` (параметр + два `case Proto::Olcrtc`), `protocolsModel.{h,cpp}` и `containersModel.{h,cpp}` (`IsOlcrtcRole` + маршрут на `PageProtocolOlcrtcSettings`), `pageEnum.h`, `qml.qrc`, `SettingsContainersListView.qml` (роутинг `isOlcrtc`), `PageSetupWizardConfigSource.qml` (карточка, Android-only). Provider/Transport — `DropDownType` (роль `name`, inline `ListModel`).

* **`models/protocols/olcrtcConfigModel.{h,cpp}`** (копия `dnsttConfigModel`): модель формы; зарегистрировать QML-свойством `OlcrtcConfigModel` в `coreController`.
* **`qml/Pages2/PageSetupWizardOlcrtcSettings.qml`** и **`PageProtocolOlcrtcSettings.qml`** (копии dnstt-страниц): provider (комбобокс: jitsi/telemost/wbstream/none), transport (комбобокс: datachannel/vp8channel/seichannel/videochannel, по умолчанию datachannel), roomUrl, key (64 hex); опц. dns, token/name (под «Дополнительно»). **Engine не показываем** (авто из provider). Валидация — в C++-модели.
* **`qml/Pages2/PageSetupWizardConfigSource.qml`** — карточка «olcRTC (WebRTC Tunnel)», видима только на Android.
* Регистрация страниц/протокола в тех же местах, что правились для dnstt: **`utils/pageEnum.h`**, **`qml/qml.qrc`**, **`models/protocolsModel.{cpp,h}`**, **`models/containersModel.{cpp,h}`**, **`controllers/selfhosted/installUiController.{cpp,h}`**, **`Components/SettingsContainersListView.qml`**.

### 3.5. Сборка (`client/cmake/`, `deploy/`) — ✅ РЕАЛИЗОВАНО И ПРОВЕРЕНО

> В `android.cmake` добавлен блок сборки `libolcrtc.so` (зеркало dnstt, переиспользует `DNSTT_*` host/arch/ndk-переменные) с флагом `-checklinkname=0`. **Собран весь подписанный APK** (`deploy/build_android_wsl.sh`, arm64-v8a, Qt 6.10.0 + NDK 26.3.11579264): CMake `[81/257] Building libolcrtc.so` отработал, C++/QML скомпилировались, gradle-модуль `:olcrtc` собрался, `assembleRelease` + zipalign + apksigner прошли. Итог: `deploy/build/AmneziaVPN-dnstt.apk` (89 МБ), внутри `lib/arm64-v8a/libolcrtc.so` (39 МБ) рядом с libdnstt.so. `patch_libs_xml.py` не менялся.

* **`client/cmake/android.cmake`** — добавить сборку второго Go-модуля (`libolcrtc.so`) тем же NDK-тулчейном; блок копируется с dnstt (ABI→GOARCH уже решено). Результат в `client/android/libs/<ABI>/libolcrtc.so`.
* **`deploy/patch_libs_xml.py`** — не менять (проходит все `.so`; грабля №4 закрыта).
* **`go.mod`** — pin gvisor под tun2socks и pion/v4.
* Новое сверх dnstt: **размер APK** (дерево pion/livekit крупное), повторная проверка граблей №2 (JNI_OnLoad/libgojni) и №6 (duplicate `JNI_OnLoad`) при вендоринге.

---

## 4. Патч olcRTC — НЕ ТРЕБУЕТСЯ (обновлено после реализации)

Первоначальный план предполагал shim/патч для доступа к protect. При реализации нашёлся **публичный top-level пакет `github.com/openlibrecommunity/olcrtc/mobile`** — штатная точка входа для Android-форков, которая уже экспонирует всё нужное:

```go
type SocketProtector interface{ Protect(fd int) bool }
func New() *Runtime
func (r *Runtime) SetProtector(p SocketProtector)   // → internal/protect.SetProtector
func (r *Runtime) SetProvider/SetTransport/SetRoom/SetKey/SetDNS/SetProviderToken(...)
func (r *Runtime) SetSocksListenHost(string); SetSocksPort(int)
func (r *Runtime) Start() error; WaitReady(ms int) error; Stop(ms int) error
func (r *Runtime) State() string; IsRunning() bool
```

Поэтому olcRTC подключается как **обычная go.mod-зависимость** (без вендоринга исходников, без правок `internal/`, без `client.Config`-полей). `SetProtector` process-global — безопасно, т.к. туннель работает в отдельном процессе `:amneziaOlcrtcService`. Это реализовано в `olcrtcclient/tunnel.go` (§3.1) и подтверждено сборкой.

---

## 5. Discovery-задачи (до начала реализации)

| № | Вопрос | Где смотреть | Влияние |
|---|--------|--------------|---------|
| ~~D1~~ | ~~Как protect устанавливается и покрывает ли все движки~~ | — | **РЕШЕНО** (см. ниже): публичный `mobile.Runtime.SetProtector`, авто-`SetNet` на Android, покрыты pion- и LiveKit-движки. Патч не нужен (§4). Не блокер |
| ~~D2~~ | ~~SOCKS5 UDP ASSOCIATE~~ | — | **РЕШЕНО**: только CONNECT (0x01); UDP/BIND отклоняются. Общий UDP невозможен → DNS-over-TCP + дроп UDP в netstack (как dnstt) |
| D3 | Достижимость DNS/провайдера вне туннеля до его подъёма (bootstrap) | `Config.Resolver`, `Config.DNSServer`, `NewProtectedNet(resolvers...)` | нужен ли bootstrap-IP, как у dnstt |
| ~~D4~~ | ~~Значения `Provider/Transport/Engine`, `RoomURL/ChannelID`~~ | — | **РЕШЕНО** (см. ниже): наборы значений + авто-derive Engine из provider |
| ~~D5~~ | ~~Версия для пина~~ | — | **РЕШЕНО**: olcRTC запинен на `v0.0.2-0.20260905232354-189d16c093c4`, gvisor на `v0.0.0-20260701204157-69c2d17aea96`, tun2socks `v2.7.0` — всё в `go.mod`/`go.sum`, сборка `olcrtcclient` зелёная |

### D1 — результат discovery (protect)

Проверено чтением исходников olcRTC (`master`):
* **`internal/protect/protect.go`**: `var protector atomic.Pointer[protectorHolder]`; `func SetProtector(protectFunc func(int) bool)` (экспортный сеттер, process-global); `func HasProtector() bool`; `func controlFunc(network, _ string, c syscall.RawConn) error` — применяет protector к fd.
* **`internal/protect/pionnet.go`**: `type ProtectedNet` `implements transport.Net`; `NewProtectedNet(resolvers ...*net.Resolver)`; `Dial`/`ListenPacket`/`ListenUDP` навешивают `controlFunc`. Плюс платформенные `pionnet_android*.go` (`//go:build android && cgo`) и `pionnet_default.go` (`//go:build !android`).
* **`internal/engine/pion.go`**: `NewPionSettings(opts)` → замыкание над `webrtc.SettingEngine`; условие `useProtectedNet := protect.HasProtector() || opts.Resolver != nil || runtime.GOOS == "android"`; при истинности — `settings.SetNet(protectedNet)`.
* **Покрытие движков подтверждено на «трудном» случае:** `internal/engine/livekit/livekit.go` не строит pion напрямую, а делегирует LiveKit SDK — и **всё равно** протектит: `protect.NewHTTPClient()` → `lksdk.WithConnectHTTPClient`, `protect.NewWebSocketDialer()` → `lksdk.WithWebSocketDialer`, `applySettings` (обёртка `NewPionSettings`) → `lksdk.WithSettingEngineFunc`. Pion-движки (`jitsi`, `goolom`) используют тот же `NewPionSettings`.

**Вывод:** protect в olcRTC реализован системно и покрывает ICE/HTTPS/WebSocket во всех движках; на Android включается автоматически. Регистрация колбэка доступна публично через `mobile.Runtime.SetProtector` (§4) — ни патча, ни доработки `client.Config` не нужно, риск №1 снят. Остаётся лишь стендовая проверка утечек (§6, tcpdump) как финальная валидация, а не как открытый архитектурный вопрос.

### D2 — результат discovery (SOCKS5/UDP)

`internal/client/socks.go`: диспетчер команд отклоняет всё, кроме CONNECT — `if header[1] != 1 { return ..., ErrUnsupportedSOCKSCommand }`. UDP ASSOCIATE (0x03) и BIND (0x02) не реализованы. **Следствие:** общий UDP приложений через olcRTC не проходит (как в dnstt). В `netstack.go` оставляем dnstt-логику: DNS (:53) → DNS-over-TCP через CONNECT-поток, прочий UDP — дроп (не выпускать мимо туннеля). CONNECT к `resolver:53` работает, т.к. `olcrtc srv` подключается к произвольным адресам в интернет напрямую.

### D4 — результат discovery (значения конфига)

Из `internal/config/config.go` (комментарии-перечисления) и провайдеров `internal/auth/*`:

| Поле | Значения / формат | Обязательность |
|------|-------------------|----------------|
| `Provider` | `jitsi`, `telemost`, `wbstream`, `none` | да |
| `Transport` | `datachannel`, `videochannel`, `seichannel`, `vp8channel` | да (есть дефолт в реестре) |
| `Engine` | `livekit`, `goolom`, `jitsi` | **не задаём** — авто из провайдера |
| `KeyHex` | 64 hex (32 байта) | да |
| `RoomURL` | URL комнаты или id/хеш | да (кроме создания комнаты «на лету») |
| `ChannelID` | id канала комнаты | опц. |
| `Token`/`Name` | токен аккаунта / имя гостя | опц. |
| `DNSServer` | кастомный резолвер | опц. |

**Provider.Engine() (авто-derive):** `jitsi`→`jitsi`, `telemost`→`goolom` (Яндекс Telemost: полный URL или хеш комнаты; без логина, тянет данные из сервиса), `wbstream`→`livekit` (без Token авто-регистрирует гостя), `none`→passthrough (URL+Token+Engine задаёт вызывающий). Это подтверждает: в UI показываем **Provider + Transport + RoomURL + Key**, а Engine выводим автоматически.

---

## 6. Порядок работ

1. ~~**Discovery** D1–D5~~ — D1, D2, D4, D5 решены; осталось только **D3** (bootstrap DNS — не блокер).
2. ✅ **Go-ядро** — `tunnel.go`/`netstack.go`/`socks.go`/`jni` + `go.mod` написаны; `go build ./olcrtcclient` зелёный. Осталось собрать `libolcrtc.so` через NDK (§3.5) — проверить экспорт `JNI_OnLoad` и двух функций.
3. ✅ **C++ ядро** — сделано (§3.3).
4. ✅ **UI** — config-модель + QML-страницы + регистрация (§3.4).
5. ✅ **Android-слой** + `android.cmake` + **полный подписанный APK собран** (§3.2, §3.5).
6. **Стенд:** `protect()`-аудит (tcpdump: все ICE/HTTPS/DNS-сокеты мимо TUN) + живой туннель против `olcrtc srv` с реальной комнатой провайдера.

Все слои реализованы и **весь код проверен компиляцией сквозь сборку APK** (C++/QML/Kotlin/Go/JNI). Не пройдено только стендовое испытание (6): живой туннель против сервера и аудит утечек protect — ни разу не гонялось (как и dnstt).

---

## 7. Что проверено, а что нет

**Проверено по исходникам upstream (commit на ветке `master`, дата составления плана 2026-09-12):**
* `go.mod`: модуль `github.com/openlibrecommunity/olcrtc`, Go 1.26.3, `pion/webrtc/v4` v4.2.15, `xtaci/smux`, `kcp-go/v5`, `x/crypto`, `livekit/protocol`, `gorilla/websocket`; TUN/netstack отсутствует.
* Публичный API `pkg/olcrtc/client`: `Config` (поля выше), `New`, `Run`/`RunWithReady`/`RunWithAddress`.
* `internal/protect/pionnet.go`: `ProtectedNet implements transport.Net`, применяет `controlFunc` к каждому сокету; конструктор `NewProtectedNet(resolvers ...*net.Resolver)`.
* Структура: `cmd/{olcrtc,olcrtc-cgo}`, `pkg/olcrtc/{client,tunnel,engineconn}`, `internal/{app,auth,client,config,control,crypto,e2e,engine,framing,handshake,logger,muxconn,names,protect,runtime,server,supervisor,transport,tunnelcore}`, транспорты datachannel/vp8channel/seichannel/videochannel, движки builtin(агрегатор)/jitsi/livekit/goolom.
* **protect (D1)** — полностью подтверждён чтением: `protect.SetProtector`/`HasProtector`/`controlFunc`/`ProtectedNet`/`NewProtectedNet`, `engine.NewPionSettings` с авто-`SetNet` на Android, покрытие pion- и LiveKit-движков (детали в §5, блок «D1 — результат discovery»).
* `cmd/olcrtc-cgo/main.go` экспонирует `Ping`/`Check`; полноценная точка входа для Android — публичный пакет `github.com/openlibrecommunity/olcrtc/mobile` (`New()`, `Runtime` с `SetProtector`/`SetProvider`/…/`Start`/`WaitReady`/`Stop`), что и делает патч ненужным (§4).
* **Собрано:** `go build ./olcrtcclient` (WSL, Go 1.26, GOOS=linux) — зелёный; имена методов `mobile.Runtime` и весь граф зависимостей подтверждены компилятором; olcRTC `v0.0.2-0.20260905232354-189d16c093c4`, gvisor запинен, tun2socks `v2.7.0`.
* **D2:** `internal/client/socks.go` — только CONNECT; UDP ASSOCIATE/BIND → `ErrUnsupportedSOCKSCommand`.
* **D4:** значения `Provider`/`Transport`/`Engine` из `internal/config/config.go`; `Provider.Engine()` подтверждён чтением `internal/auth/{telemost,wbstream}` (goolom/livekit) и структурой (`internal/auth/jitsi`→jitsi); `pkg/olcrtc/client/client.go` прочитан на уровне экспортного API (внутренняя логика делегируется `internalclient.RunWithAddress`).
* Локальные точки вставки в клиенте подтверждены чтением: `protocolConfig.cpp`, `containerUtils.cpp`, `importController.cpp`, `socks.go`, `netstack.go`, `tunnel.go`, `jni/main.go`, `DnsttNative.kt`, `Dnstt.kt`, `protocolEnum.h`.

**Не проверено (осталось D3, D5 из §5):** bootstrap-достижимость DNS/провайдера до подъёма туннеля (нужен ли аналог bootstrap-IP dnstt); стабильность и конкретный тег публичного API для пина `go.mod`. Не прочитана построчно точная строка создания `SettingEngine` в пакете `jitsi` (в `bridge.go`/`negotiate.go`; применение `NewPionSettings` подтверждено архитектурно и на livekit-движке). Как и у dnstt, живой туннель против сервера ещё не прогонялся ни разу — обязательна стендовая проверка (§6), включая tcpdump-аудит утечек protect.
