#!/usr/bin/env python3
"""
Build zh-CN and zh-TW translation overlays for omarchy-menu.jsonc.

Each output is a partial JSONC file with only `label` and `title` overrides
(existing icons/actions/providers preserved by the upstream merge logic).
"""
import json, re, os, sys

SRC = "/home/axu/.local/share/omarchy/default/omarchy/omarchy-menu.jsonc"
OUT_DIR = "/home/axu/.local/share/omarchy/default/omarchy"

# ----------------------------------------------------------------------------
# Translation tables: English label -> (zh-CN, zh-TW)
# Brand names / proper nouns / file names stay as-is in both locales.
# ----------------------------------------------------------------------------
T = {
    # Root menu
    "Apps": ("应用", "應用"),
    "Learn": ("学习", "學習"),
    "Trigger": ("触发", "觸發"),
    "Style": ("风格", "風格"),
    "Setup": ("设置", "設定"),
    "Install": ("安装", "安裝"),
    "Remove": ("移除", "移除"),
    "Update": ("更新", "更新"),
    "About": ("关于", "關於"),
    "System": ("系统", "系統"),

    # System submenu
    "Screensaver": ("锁屏保护", "螢幕保護"),
    "Lock": ("锁屏", "鎖定"),
    "Suspend": ("挂起", "暫停"),
    "Hibernate": ("休眠", "休眠"),
    "Logout": ("登出", "登出"),
    "Reboot": ("重启", "重新啟動"),
    "Shutdown": ("关机", "關機"),

    # Learn
    "Keybindings": ("快捷键", "快速鍵"),
    "Omarchy": ("Omarchy", "Omarchy"),
    "Hyprland": ("Hyprland", "Hyprland"),
    "Arch": ("Arch", "Arch"),
    "Neovim": ("Neovim", "Neovim"),
    "Bash": ("Bash", "Bash"),
    "Tmux": ("Tmux", "Tmux"),
    "Herdr": ("Herdr", "Herdr"),
    "Community": ("社区", "社群"),

    # Trigger
    "Emoji": ("表情", "表情"),
    "Reminder": ("提醒", "提醒"),
    "Capture": ("捕获", "擷取"),
    "Screenshot": ("截图", "截圖"),
    "Stop Screenrecording": ("停止录屏", "停止錄影"),
    "Screenrecord": ("录屏", "錄影"),
    "Text": ("文本", "文字"),
    "QR Code": ("二维码", "QR 碼"),
    "Color": ("颜色", "顏色"),
    "With no audio": ("不带声音", "不含聲音"),
    "With desktop audio": ("带桌面音频", "含電腦音訊"),
    "With desktop + microphone audio": ("桌面音频 + 麦克风", "電腦音訊 + 麥克風"),
    "With desktop + microphone audio + webcam": ("桌面音频 + 麦克风 + 摄像头", "電腦 + 麥克風 + 攝影機"),
    "Transcode": ("转码", "轉檔"),
    "Share": ("分享", "分享"),
    "Toggle": ("切换", "切換"),
    "Hardware": ("硬件", "硬體"),
    "Speed Test": ("速度测试", "速度測試"),
    "Laptop Display": ("笔记本显示", "筆電螢幕"),
    "Mirror Display": ("镜像显示", "鏡像顯示"),
    "Hybrid GPU": ("混合显卡", "混合顯示卡"),
    "Touchpad": ("触控板", "觸控板"),
    "Touchpad Haptics": ("触控板触感", "觸控板觸感"),
    "low": ("弱", "弱"),
    "mid": ("中", "中"),
    "high": ("强", "強"),
    "Touchscreen": ("触摸屏", "觸控螢幕"),
    "Set one": ("新建一个", "新增一個"),
    "Show all": ("查看全部", "查看全部"),
    "Clear all": ("清空全部", "清空全部"),
    "Clipboard": ("剪贴板", "剪貼簿"),
    "File": ("文件", "檔案"),
    "Folder": ("文件夹", "資料夾"),
    "Receive": ("接收", "接收"),
    "Stay Awake": ("保持唤醒", "保持喚醒"),
    "Notifications": ("通知", "通知"),
    "Crash Capture": ("崩溃捕获", "當機擷取"),
    "Nightlight": ("夜灯", "夜燈"),
    "Menu Bar": ("菜单栏", "選單列"),
    "Battery Percentage": ("电量百分比", "電量百分比"),
    "Workspace Layout": ("工作区布局", "工作區佈局"),
    "Window Gaps": ("窗口间隙", "視窗間距"),
    "1-Window Ratio": ("单窗比例", "單視窗比例"),
    "Network Speed Test": ("网络测速", "網路測速"),
    "Disk Speed Test": ("磁盘测速", "磁碟測速"),

    # Style
    "Theme": ("主题", "主題"),
    "Background": ("壁纸", "桌布"),
    "Unlock": ("解锁", "解鎖"),
    "Font": ("字体", "字型"),
    "Position": ("位置", "位置"),
    "Transparency": ("透明度", "透明度"),
    "Top": ("顶部", "頂部"),
    "Bottom": ("底部", "底部"),
    "Left": ("左", "左"),
    "Right": ("右", "右"),
    "Edit Text": ("编辑文字", "編輯文字"),
    "Set From Image": ("从图片设置", "從圖片設定"),
    "Restore Default": ("恢复默认", "還原預設"),

    # Setup
    "Monitors": ("显示器", "螢幕"),
    "Input": ("输入法", "輸入法"),
    "Network": ("网络", "網路"),
    "DNS": ("DNS", "DNS"),
    "DHCP": ("DHCP", "DHCP"),
    "Cloudflare": ("Cloudflare", "Cloudflare"),
    "Google": ("Google", "Google"),
    "Custom": ("自定义", "自訂"),
    "Defaults": ("默认项", "預設項目"),
    "Agent": ("代理", "代理"),
    "Default Agent": ("默认代理", "預設代理"),
    "Antigravity": ("Antigravity", "Antigravity"),
    "Claude": ("Claude", "Claude"),
    "Codex": ("Codex", "Codex"),
    "Copilot": ("Copilot", "Copilot"),
    "Crush": ("Crush", "Crush"),
    "Grok": ("Grok", "Grok"),
    "Hermes": ("Hermes", "Hermes"),
    "omp": ("omp", "omp"),
    "OpenCode": ("OpenCode", "OpenCode"),
    "Ori": ("Ori", "Ori"),
    "Pi": ("Pi", "Pi"),
    "Browser": ("浏览器", "瀏覽器"),
    "Default Browser": ("默认浏览器", "預設瀏覽器"),
    "Chromium": ("Chromium", "Chromium"),
    "Chrome": ("Chrome", "Chrome"),
    "Brave": ("Brave", "Brave"),
    "Brave Origin": ("Brave 原版", "Brave 原版"),
    "Edge": ("Edge", "Edge"),
    "Firefox": ("Firefox", "Firefox"),
    "Zen": ("Zen", "Zen"),
    "Terminal": ("终端", "終端機"),
    "Default Terminal": ("默认终端", "預設終端機"),
    "Alacritty": ("Alacritty", "Alacritty"),
    "Foot": ("Foot", "Foot"),
    "Ghostty": ("Ghostty", "Ghostty"),
    "Kitty": ("Kitty", "Kitty"),
    "Editor": ("编辑器", "編輯器"),
    "Default Editor": ("默认编辑器", "預設編輯器"),
    "VSCode": ("VSCode", "VSCode"),
    "Cursor": ("Cursor", "Cursor"),
    "Zed": ("Zed", "Zed"),
    "Sublime Text": ("Sublime Text", "Sublime Text"),
    "Helix": ("Helix", "Helix"),
    "Vim": ("Vim", "Vim"),
    "Emacs": ("Emacs", "Emacs"),
    "Plugins": ("插件", "外掛"),
    "Enable Plugin": ("启用插件", "啟用外掛"),
    "Disable Plugin": ("禁用插件", "停用外掛"),
    "Add Plugin": ("添加插件", "新增外掛"),
    "Clone Plugin": ("克隆插件", "複製外掛"),
    "Remove Plugin": ("移除插件", "移除外掛"),
    "Security": ("安全", "安全"),
    "Config": ("配置", "設定檔"),
    "Fingerprint": ("指纹", "指紋"),
    "Fido2": ("Fido2", "Fido2"),
    "SSHD": ("SSHD", "SSHD"),
    "Passwordless Sudo": ("免密 sudo", "免密碼 sudo"),
    "Sudoless Docker": ("免 sudo Docker", "免 sudo Docker"),
    "Hyprsunset": ("Hyprsunset", "Hyprsunset"),
    "XCompose": ("XCompose", "XCompose"),
    "Direct Boot": ("直接启动", "直接啟動"),
    "Reset Computer": ("重置电脑", "重置電腦"),

    # Install / remove common
    "Package": ("软件包", "套件"),
    "AUR": ("AUR", "AUR"),
    "AI": ("AI", "AI"),
    "Service": ("服务", "服務"),
    "Services": ("服务", "服務"),
    "Development": ("开发环境", "開發環境"),
    "Cascadia Mono": ("Cascadia Mono", "Cascadia Mono"),
    "Meslo LG Mono": ("Meslo LG Mono", "Meslo LG Mono"),
    "Fira Code": ("Fira Code", "Fira Code"),
    "Victor Code": ("Victor Code", "Victor Code"),
    "Bitstream Vera Mono": ("Bitstream Vera Mono", "Bitstream Vera Mono"),
    "Iosevka": ("Iosevka", "Iosevka"),
    "Gaming": ("游戏", "遊戲"),
    "Web App": ("网页应用", "網頁應用"),
    "TUI": ("TUI", "TUI"),
    "Windows": ("Windows", "Windows"),
    "Preinstalls": ("预装软件", "預裝軟體"),

    # Services
    "1Password": ("1Password", "1Password"),
    "Dropbox": ("Dropbox", "Dropbox"),
    "Spotify": ("Spotify", "Spotify"),
    "Signal": ("Signal", "Signal"),
    "Tailscale": ("Tailscale", "Tailscale"),
    "NordVPN": ("NordVPN", "NordVPN"),
    "ONCE": ("ONCE", "ONCE"),
    "Bitwarden": ("Bitwarden", "Bitwarden"),
    "Chromium Account": ("Chromium 账号", "Chromium 帳號"),

    # AI / TUI / Apps
    "ChatGPT Desktop": ("ChatGPT 桌面版", "ChatGPT 桌面版"),
    "Dictation": ("听写", "聽寫"),
    "Grok Bot": ("Grok Bot", "Grok Bot"),
    "Hermes Desktop": ("Hermes 桌面版", "Hermes 桌面版"),
    "LM Studio": ("LM Studio", "LM Studio"),
    "Ollama": ("Ollama", "Ollama"),
    "T3 Code": ("T3 Code", "T3 Code"),

    # Gaming
    "Steam": ("Steam", "Steam"),
    "RetroArch": ("RetroArch", "RetroArch"),
    "Minecraft": ("Minecraft", "Minecraft"),
    "NVIDIA GeForce NOW": ("NVIDIA GeForce NOW", "NVIDIA GeForce NOW"),
    "Xbox Cloud Gaming": ("Xbox 云游戏", "Xbox 雲端遊戲"),
    "Xbox Controllers": ("Xbox 手柄", "Xbox 控制器"),
    "Xbox Controllers (\U000F00AF)": ("Xbox 手柄 (\U000F00AF)", "Xbox 控制器 (\U000F00AF)"),
    "Battle.net": ("Battle.net", "Battle.net"),
    "Lutris": ("Lutris", "Lutris"),
    "Heroic (Epic Games)": ("Heroic (Epic Games)", "Heroic (Epic Games)"),
    "RetroArch Game Launcher": ("RetroArch 游戏启动器", "RetroArch 遊戲啟動器"),

    # Development
    "Ruby on Rails": ("Ruby on Rails", "Ruby on Rails"),
    "Docker DB": ("Docker 数据库", "Docker 資料庫"),
    "JavaScript": ("JavaScript", "JavaScript"),
    "Go": ("Go", "Go"),
    "PHP": ("PHP", "PHP"),
    "Python": ("Python", "Python"),
    "Elixir": ("Elixir", "Elixir"),
    "Zig": ("Zig", "Zig"),
    "Rust": ("Rust", "Rust"),
    "Java": ("Java", "Java"),
    ".NET": (".NET", ".NET"),
    "OCaml": ("OCaml", "OCaml"),
    "Clojure": ("Clojure", "Clojure"),
    "Scala": ("Scala", "Scala"),
    "Node.js": ("Node.js", "Node.js"),
    "Bun": ("Bun", "Bun"),
    "Deno": ("Deno", "Deno"),
    "Laravel": ("Laravel", "Laravel"),
    "Symfony": ("Symfony", "Symfony"),
    "Phoenix": ("Phoenix", "Phoenix"),

    # Update
    "Channel": ("更新频道", "更新頻道"),
    "Stable": ("稳定版", "穩定版"),
    "RC": ("候选版", "候選版"),
    "Edge": ("Edge 版", "Edge 版"),
    "Dev": ("开发版", "開發版"),
    "Process": ("进程", "程序"),
    "Hardware": ("硬件", "硬體"),
    "Firmware": ("固件", "韌體"),
    "Password": ("密码", "密碼"),
    "Timezone": ("时区", "時區"),
    "Time": ("时间", "時間"),
    "Audio": ("音频", "音訊"),
    "Wi-Fi": ("Wi-Fi", "Wi-Fi"),
    "Bluetooth": ("蓝牙", "藍牙"),
    "Trackpad": ("触控板", "觸控板"),
    "Drive Encryption": ("磁盘加密", "磁碟加密"),
    "User": ("用户", "使用者"),
    "Extra Themes": ("额外主题", "額外主題"),
    "Plymouth": ("Plymouth", "Plymouth"),
    "Shell": ("Shell", "Shell"),

    # Update submenu titles
    "Default Agent": ("默认代理", "預設代理"),
    "Default Browser": ("默认浏览器", "預設瀏覽器"),
    "Default Terminal": ("默认终端", "預設終端機"),
    "Default Editor": ("默认编辑器", "預設編輯器"),
    "Reset to default": ("恢复默认", "還原預設"),
    "Restart": ("重启服务", "重新啟動"),
    "Remove": ("移除", "移除"),
}

# ----------------------------------------------------------------------------
# Read source menu
# ----------------------------------------------------------------------------
with open(SRC) as f:
    raw = f.read()

raw_no_comments = re.sub(r"^\s*//.*$", "", raw, flags=re.M)
raw_no_comments = re.sub(r",(\s*[}\]])", r"\1", raw_no_comments)
data = json.loads(raw_no_comments)

# Submenu-pseudo-removal-headers don't have label
def emit_for_locale(locale_key, lang_field):
    overrides = {}
    missing = []
    for k, v in data.items():
        label = v.get("label")
        title = v.get("title", "")
        if label:
            if label not in T:
                missing.append(label)
                continue
            translated = T[label][lang_field]
            entry = {"label": translated}
            if title and title in T:
                entry["title"] = T[title][lang_field]
            overrides[k] = entry
        # Entries with title-only and no label (e.g., setup.default.agent) already
        # covered by their parent's title.

    return overrides, missing

cn_overrides, cn_missing = emit_for_locale("zh-CN", 0)
tw_overrides, tw_missing = emit_for_locale("zh-TW", 1)

# Sort keys for human-readable output
def write_overlay(filename, items, locale_tag):
    path = os.path.join(OUT_DIR, filename)
    with open(path, "w", encoding="utf-8") as out:
        out.write("{\n")
        out.write(f"  // Omarchy menu translation overlay — {locale_tag}\n")
        out.write("  // Applied via ~/.config/omarchy/extensions/omarchy-menu.jsonc\n")
        out.write("  // See ~/.local/bin/omarchy-menu-locale for switching.\n")
        out.write("  \"items\": {\n")
        keys = sorted(items.keys())
        for i, kid in enumerate(keys):
            entry = items[kid]
            line = "    " + json.dumps(kid, ensure_ascii=False) + ": "
            line += "{"
            inner = []
            if "label" in entry:
                inner.append('"label": ' + json.dumps(entry["label"], ensure_ascii=False))
            if "title" in entry:
                inner.append('"title": ' + json.dumps(entry["title"], ensure_ascii=False))
            line += ", ".join(inner)
            line += "}"
            if i < len(keys) - 1:
                line += ","
            out.write(line + "\n")
        out.write("  }\n")
        out.write("}\n")

    return path, len(items)

cn_path, cn_n = write_overlay("omarchy-menu.zh-CN.jsonc", cn_overrides, "简体中文")
tw_path, tw_n = write_overlay("omarchy-menu.zh-TW.jsonc", tw_overrides, "繁體中文")

# Sanity check: warn about missing entries
seen_missing = sorted(set(cn_missing))
print(f"✓ wrote {cn_path}  ({cn_n} entries)")
print(f"✓ wrote {tw_path}  ({tw_n} entries)")
if seen_missing:
    print(f"⚠ {len(seen_missing)} unique labels without translations (kept as English):")
    for m in seen_missing:
        print(f"  - {m}")
