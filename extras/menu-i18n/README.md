# Omarchy 菜单简体/繁体汉化（menu-i18n）

Omarchy 4 (Quattro) Super+D 菜单的中文汉化包，含简体（zh-CN）与繁体（zh-TW）。

## 文件

| 文件 | 作用 |
|---|---|
| `build-menu-i18n.py` | 从 default 菜单源批量生成翻译源 `omarchy-menu.<lang>.jsonc` |
| `locales/omarchy-menu.zh-CN.jsonc` | 简体中文翻译源（331 条，只含 `label` 字段） |
| `locales/omarchy-menu.zh-TW.jsonc` | 繁體中文翻译源（331 条，只含 `label` 字段） |
| `omarchy-menu-locale` | 语言切换脚本，installed 到 `~/.local/bin/` |
| `../dotfiles/omarchy-port` | launcher（含 Hyprland instance signature 自动发现） |
| `../dotfiles/omarchy-menu-toggle` | Super+D 绑定 wrapper（zombie qs + HIS stale 双层兜底） |

## 安装

翻译源放到 `$OMARCHY_PATH/default/omarchy/omarchy-menu.<lang>.jsonc`；
`omarchy-menu-locale` 放到 `~/.local/bin/`。

## 用法

```bash
omarchy-menu-locale            # 显示当前生效语言
omarchy-menu-locale zh-CN      # 切到简体中文
omarchy-menu-locale zh-TW      # 切到繁體中文
omarchy-menu-locale en         # 切回英文（清空 user extension）
omarchy-menu-locale list       # 列出已安装语言
```

切换会把翻译合并写入 `~/.config/omarchy/extensions/omarchy-menu.jsonc`，
并触发 menu 插件 re-read。自定义条目（不带 `_locale` 字段）会被保留。

## 关键：为什么必须改 core 的 merge 逻辑（2026-09-05 修复）

### 问题

`MenuModel.mergeMenuSources(defaultItems, userItems)` 是**条目级**合并：user
extension 里出现某个 id，就**整体覆盖** default 里该 id 的条目。

而翻译源每条只写了 `{"label":"关于"}`。经 `MenuModel.normalizeItem()` 补全后
会变成 `{id:"about", parent:"root", kind:"menu", icon:"", label:"关于",
action:"", target:"", ...}` —— `kind` 被重推断为 `menu`、`action/target/icon`
全被清空。merge 时这些空字段/错误 kind 就冲掉了 `about`/`apps`/`install`… 这些
default 条目的真实 `kind/action/icon`，导致整个菜单条目全部失效 → 屏幕只剩
「Go… + Nothing here yet」。

### 解法

给 `parseMenuJsonc`/`normalizeItem` 增加 **sparse（字段级）合并**模式：

- **default 文件**解析用 `sparse=false`（保持原补全逻辑，行为不变）。
- **user extension**（含 i18n overlay）解析用 `sparse=true`：只携带用户**显式写**
  的字段，不再补全空、不再自动推断 `kind/parent`。

这样 `{"label":"关于"}` 只覆盖 default 里 `about` 的 `label`，`kind/action/icon/parent`
全部保留 default 原值 → 菜单内容完整，只是文字换成中文。

### 涉及的 core 改动

- `MenuModel.js`：
  - `normalizeItem(id, raw, sparse)` 增加 sparse 分支。
  - `parseMenuJsonc(raw, sparse)` 透传 sparse。
- `Menu.qml`：
  - 封装 `parseMenuJsonc(raw, sparse)`。
  - `userMenuFile.onLoaded` 改用 `parseMenuJsonc(text(), true)`。

> 注意：这两个文件是 Quickshell core（`~/.local/share/omarchy/shell/plugins/menu/`），
> 不在本仓库；仓库维护的是脚本与翻译源。改 core 后需 `omarchy-restart-shell`
> 或 kill qs 重启才生效。

## 验证

`hyprctl layers` 里出现 `namespace: omarchy-menu` 的 Layer 即为菜单已实例化；
切换语言后重启 qs，Super+D 应按对应语言显示完整条目。
