# SilenceGate

**Sound only through your Bluetooth headphones — every other speaker stays dead silent.**

[中文](#中文) · [English](#english)

---

## 中文

> 我给家里那台电脑配了个"外放保险"：**没戴蓝牙耳机的时候，这台 Mac 一点声音都不许出。**

### 这个工具到底解决什么问题

我白天用远程控制软件（向日葵 / ToDesk / RustDesk / 微软远程桌面）连家里的电脑上班。

问题出在"声音"这一路上：家里那台机器会被家人拿去用，他们一开视频、一放歌，音频就顺着远控链路传过来，从我办公室这台 Mac mini 的扬声器里直接播出来 —— 整个办公室都听见了。

系统自带的静音挡不住这个，因为它是个二选一：要么全静音（我自己的提示音也没了），要么全放行（家人的视频就漏出来）。

SilenceGate 换了条思路：**不看系统音量，而是看"声音最终从哪个物理出口出去"**。

- 没连蓝牙耳机 → 内置扬声器、显示器 HDMI / DisplayPort 喇叭、USB 声卡，**全部压死**。远程的声音传过来了也只是一头撞进哑掉的设备，外面一点动静都没有。
- 连上蓝牙耳机 → 声音正常进你耳朵，**外放依旧保持静音**。

结果就是：声音只有两种去处 —— 耳机里，或者哪儿都不去。

### 安装

要求 macOS 13 或更高（Apple Silicon / Intel 都行）。

```bash
git clone https://github.com/bayniidt/SilenceGate.git
cd SilenceGate
make run        # 就地编译并启动
make install    # 装到 /Applications（想用开机自启就用这个）
```

没有 Xcode 也能编译，装好命令行工具即可（`xcode-select --install`）。

### 用法

点菜单栏图标，全部开关都在里面：

| 菜单项 | 作用 |
| --- | --- |
| 当前输出 / 状态 | 只读。告诉你现在声音往哪走、是不是已经静音了 |
| 启用屏蔽 | 总开关。关掉 = 完全恢复系统原本行为 |
| 静音规则 → 始终静音非蓝牙输出 | **默认**。外放永久静音，声音只从耳机走 |
| 静音规则 → 仅无蓝牙耳机时静音 | 没耳机时静音；连上耳机后把外放音量还给你 |
| 蓝牙耳机接入时自动切换输出 | 有些耳机连上后系统不会自动切过去，勾上它自动接管 |
| 忽略虚拟声卡（向日葵 / OBS 等） | 虚拟声卡不静音，免得影响远控会话本身的音频 |
| 输出设备 | 展开看每个设备的能力与状态，点一下可切换默认输出 |
| 立即静音一次 | 手动补一刀 |
| 语言 / Language | 跟随系统 / 中文 / English |
| 开机自动启动 | 写一个 LaunchAgent |
| 诊断信息… | 打印所有输出设备的能力，排错用 |
| 退出并恢复音量 | 退出时把音量还原（推荐） |
| 退出（保持静音） | 退出后系统继续保持静音 |

图标就是状态：🔇 已静音 / 🎧 耳机已连、放行 / 🔊 屏蔽已关闭。

### 它是怎么做到的

1. 用 CoreAudio 枚举所有**输出**设备，按 `kAudioDevicePropertyTransportType` 区分蓝牙、内置、HDMI、DisplayPort、USB、虚拟。
2. 对每个非蓝牙输出设备写**硬件静音**：`kAudioDevicePropertyMute = 1`，同时把 `kAudioDevicePropertyVolumeScalar` 压到 0（双保险，有些设备只认其中一个）。注意这改的是**设备级**音量，不是系统音量，所以耳机音量一点不受影响。
3. 监听三类事件，一有变化立刻重新压制：设备增删、默认输出变化、每台设备自己的音量/静音被改动。再加一个 2 秒看门狗兜底 —— **你用音量键、用脚本、用别的 App 调大音量，都会被压回 0**，控制中心里的滑块弹回去是预期行为。
4. **HDMI / DisplayPort 显示器喇叭在 Apple Silicon 上根本没有音量或静音接口**（数字直通）。这类输出压不住时，程序把默认输出**改道**到一个已经被静音的出口（通常是内置扬声器），音频流进哑设备，外面照样听不见。"默认输出"和"系统提示音输出"两条路由都会处理。
5. 压住任何设备之前，先把它的原始音量/静音状态记下来。正常退出、切规则、关屏蔽都会还原；就算程序被强杀，下次启动也会读到这笔记录把音量还回去，不会把你的 Mac 永久留在静音状态。

### 已知限制

- 如果一台机器上只剩"不可控输出"（例如外接显示器是唯一出口），而且**没有可以改道的静音出口**，物理上压不住。菜单会直接显示「⚠️ 压不住：xxx」，不装作成功。
- 声卡驱动之外的直通（专业音频接口的硬件监听、显示器的模拟音频输入）不受系统音量控制，本工具也管不到。
- 走 HDMI 出声时，改道会让那一路彻底没声音，包括你本来想从显示器听的情况 —— 这正是"禁止外放"的应有结果；需要外放时关掉「启用屏蔽」即可。
- "戴着耳机"是靠**蓝牙连接状态**判断的，不检测你是否真的戴在头上。

### 命令行

```bash
/Applications/SilenceGate.app/Contents/MacOS/SilenceGate --probe      # 打印所有输出设备的能力与当前决策
/Applications/SilenceGate.app/Contents/MacOS/SilenceGate --selftest   # 静音 → 读回校验 → 还原
/Applications/SilenceGate.app/Contents/MacOS/SilenceGate --help
/Applications/SilenceGate.app/Contents/MacOS/SilenceGate --lang en --probe
```

`--selftest` 读法：`✓` 表示该设备确实被压到 0；`⚠️` 表示它没有音量接口，只能靠改道。

### 构建细节

纯 Swift + CoreAudio，没有第三方依赖，没有 Xcode 工程文件：

```
Package.swift             Swift Package 描述
Info.plist                App 元信息（LSUIElement：纯菜单栏，无 Dock 图标）
Makefile                  build / run / install / probe / selftest
Sources/SilenceGate/
  CoreAudioSupport.swift  CoreAudio C API 封装
  AudioDevice.swift       输出设备模型 + 静音/音量接口探测
  GateEngine.swift        屏蔽引擎：决策、压制、监听、看门狗、崩溃残留恢复
  Strings.swift           中英文案表
  Preferences.swift       偏好设置
  StatusController.swift  菜单栏 UI
  Diagnostics.swift       --probe / --selftest
  LoginItem.swift         开机自启
  main.swift              入口
```

`make app` 会产出 `SilenceGate.app`（ad-hoc 签名），`make install` 装到 `/Applications`。

### License

MIT

---

## English

> A "speaker kill-switch" for my desk Mac: **when I'm not on Bluetooth headphones, this machine must not make a single sound.**

### The problem it actually solves

I work on a home PC through a remote-desktop tool (Sunlogin / ToDesk / RustDesk / Microsoft Remote Desktop).

The problem is the audio path. Family members use that home PC, and the moment they play music or a video, the sound travels down the remote session and comes straight out of the Mac mini on my desk — live, into the office.

The system mute can't help: it is all-or-nothing. Either everything is muted (including my own alerts), or everything plays (including their video).

SilenceGate takes a different angle: **it doesn't look at the system volume, it looks at which physical output the sound finally leaves through.**

- No Bluetooth headphones connected → built-in speakers, HDMI / DisplayPort monitor speakers and USB interfaces are **all muted**. Incoming remote audio just crashes into a dead device; the room stays silent.
- Bluetooth headphones connected → sound goes to your ears normally, and the speakers **stay muted anyway**.

So sound has exactly two destinations: your headphones, or nowhere.

### Install

Requires macOS 13 or later (Apple Silicon or Intel).

```bash
git clone https://github.com/bayniidt/SilenceGate.git
cd SilenceGate
make run        # build and launch in place
make install    # copy into /Applications (use this if you want launch-at-login)
```

No Xcode needed — command line tools are enough (`xcode-select --install`).

### Usage

Click the menu bar icon; everything lives there:

| Menu item | What it does |
| --- | --- |
| Output / Status | Read-only. Shows where audio is going and whether it is muted |
| Enable gate | Master switch. Off = original system behaviour, untouched |
| Mute rule → Always mute non-Bluetooth outputs | **Default.** Speakers permanently muted; sound only via headphones |
| Mute rule → Mute only when no headphones | Mute while no headphones; hand speaker volume back once they connect |
| Auto-switch output when headphones connect | Some headsets don't take over the output by themselves; this does it for them |
| Ignore virtual audio devices (remote desktop, OBS…) | Leaves virtual devices alone so remote-session audio keeps working |
| Output devices | Expand to see each device's capabilities and state; click to switch the default output |
| Silence now | One-shot extra mute |
| Language / 语言 | Follow system / 中文 / English |
| Launch at login | Writes a LaunchAgent |
| Diagnostics… | Prints every output device's capabilities, for troubleshooting |
| Quit and restore volume | Restores volumes on exit (recommended) |
| Quit (stay muted) | Leaves the system muted after exiting |

The icon is the state: 🔇 muted / 🎧 headphones connected, playing through them / 🔊 gate off.

### How it works

1. Enumerate every **output** device with CoreAudio and classify it by `kAudioDevicePropertyTransportType` (Bluetooth, built-in, HDMI, DisplayPort, USB, virtual).
2. For every non-Bluetooth output, write a **hardware mute**: `kAudioDevicePropertyMute = 1` plus `kAudioDevicePropertyVolumeScalar = 0` (belt and braces — some devices honour only one of them). This is **device-level** volume, not system volume, so headphone loudness is never touched.
3. Listen for three kinds of events and re-apply immediately: devices added/removed, default output changed, per-device volume/mute changed. A 2-second watchdog backs it up — **volume keys, scripts and other apps are all pushed back to zero**, and the Control Center slider snapping back is intended behaviour.
4. **HDMI / DisplayPort monitor speakers expose no volume or mute control at all on Apple Silicon** (digital passthrough). When such an output cannot be silenced, the app **reroutes** the default output to a sink that is already muted (usually the built-in speakers), so the stream flows into a dead device and nothing is audible. Both the default output and the system-alert output routes are handled.
5. Before muting any device, its original volume/mute state is recorded. Normal exit, mode changes and disabling all restore it; even after a hard kill, the next launch reads that record back and restores your volumes instead of leaving the Mac permanently muted.

### Known limits

- If a machine only has "uncontrollable" outputs (e.g. an external display is the only output) **and** no muted sink to reroute to, it cannot be silenced. The menu then says `⚠️ Cannot silence: xxx` rather than pretending it worked.
- Passthrough outside the sound-card driver (hardware monitoring on pro audio interfaces, a display's analogue audio input) is not governed by system volume and is out of scope.
- When audio goes out over HDMI, rerouting silences that path completely — including the case where you *did* want to listen on the monitor. That is exactly what "no speakers" means; turn the gate off when you want speakers.
- "Wearing headphones" is inferred from the **Bluetooth connection state**; it does not detect whether they are actually on your head.

### Command line

```bash
/Applications/SilenceGate.app/Contents/MacOS/SilenceGate --probe      # every output device and the current decision
/Applications/SilenceGate.app/Contents/MacOS/SilenceGate --selftest   # mute → verify → restore
/Applications/SilenceGate.app/Contents/MacOS/SilenceGate --help
/Applications/SilenceGate.app/Contents/MacOS/SilenceGate --lang en --probe
```

Reading `--selftest`: `✓` means the device really was driven to zero; `⚠️` means it has no volume control and can only be handled by rerouting.

### Build layout

Plain Swift + CoreAudio, no dependencies, no Xcode project:

```
Package.swift             Swift Package manifest
Info.plist                app metadata (LSUIElement: menu bar only, no Dock icon)
Makefile                  build / run / install / probe / selftest
Sources/SilenceGate/
  CoreAudioSupport.swift  thin wrapper over the CoreAudio C API
  AudioDevice.swift       output device model + mute/volume capability probing
  GateEngine.swift        the gate: decisions, enforcement, listeners, watchdog, crash recovery
  Strings.swift           Chinese/English string table
  Preferences.swift       preferences
  StatusController.swift  menu bar UI
  Diagnostics.swift       --probe / --selftest
  LoginItem.swift         launch at login
  main.swift              entry point
```

`make app` produces `SilenceGate.app` (ad-hoc signed); `make install` copies it to `/Applications`.

### License

MIT
