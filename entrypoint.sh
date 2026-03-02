#!/bin/bash
# ================= 配置区域 =================
VNC_PASS="Pass123"
RESOLUTION="1400x875x24"   
# ===========================================

# 0. 清理战场：强制杀掉所有旧进程
echo "🔪 Killing old processes..."
pkill -9 firefox 2>/dev/null
pkill -9 Xvfb 2>/dev/null
pkill -9 fluxbox 2>/dev/null
pkill -9 x11vnc 2>/dev/null
pkill -9 websockify 2>/dev/null
rm -f /tmp/.X0-lock
rm -f /tmp/.X11-unix/X0
sleep 2

# 1. 设置中文环境
export LANG=zh_CN.UTF-8
export LANGUAGE=zh_CN:zh
export LC_ALL=zh_CN.UTF-8

# 2. 基础路径
export HOME=/home/container
export XDG_CACHE_HOME=$HOME/.cache
export XDG_CONFIG_HOME=$HOME/.config
export XDG_DATA_HOME=$HOME/.local/share
export DISPLAY=:0

# 3. Firefox 优化变量
export MOZ_DISABLE_CONTENT_SANDBOX=1
export MOZ_FAKE_NO_SANDBOX=1
export MOZ_GFX_SPOOF_GL_VENDOR="Mesa"
export MOZ_GFX_SPOOF_GL_RENDERER="llvmpipe"

# 4. 初始化目录（删掉旧的，重新生成）
PROFILE_DIR="$HOME/firefox_clean_profile"
rm -rf "$PROFILE_DIR"
mkdir -p "$PROFILE_DIR/extensions"
mkdir -p $HOME/.vnc $HOME/.fluxbox

# 5. 🔥 下载中文语言包
echo "🔍 Detecting Firefox version..."
FF_VERSION=$(firefox --version 2>/dev/null | awk '{print $3}')

if [ -z "$FF_VERSION" ]; then
    FF_VERSION="128.0"
fi

echo "🎯 Detected Version: $FF_VERSION"

LANG_FILE="$PROFILE_DIR/extensions/langpack-zh-CN@firefox.mozilla.org.xpi"

echo "⬇️ Downloading Chinese Language Pack..."
download_success=false

# 尝试1: Mozilla 官方
if [ "$download_success" = false ]; then
    LANG_URL="https://releases.mozilla.org/pub/firefox/releases/$FF_VERSION/linux-x86_64/xpi/zh-CN.xpi"
    if wget --timeout=15 --tries=2 --no-check-certificate -q -O "$LANG_FILE" "$LANG_URL" 2>/dev/null; then
        if [ -f "$LANG_FILE" ] && [ -s "$LANG_FILE" ]; then
            echo "✅ 中文语言包已下载 (Mozilla releases)"
            download_success=true
        fi
    fi
fi

# 尝试2: 备用源
if [ "$download_success" = false ]; then
    echo "⚠️ 尝试备用下载源..."
    LANG_URL="https://addons.mozilla.org/firefox/downloads/file/4391895/zh_cn_language_pack-128.0.xpi"
    if wget --timeout=15 --tries=2 --no-check-certificate -q -O "$LANG_FILE" "$LANG_URL" 2>/dev/null; then
        if [ -f "$LANG_FILE" ] && [ -s "$LANG_FILE" ]; then
            echo "✅ 中文语言包已下载 (备用源)"
            download_success=true
        fi
    fi
fi

# 尝试3: 查找系统语言包
if [ "$download_success" = false ]; then
    echo "⚠️ 查找系统语言包..."
    SYSTEM_LANG=$(find /usr/lib*/firefox*/langpacks/ -name "zh-CN*.xpi" 2>/dev/null | head -n1)
    if [ -f "$SYSTEM_LANG" ]; then
        cp "$SYSTEM_LANG" "$LANG_FILE"
        echo "✅ 使用系统语言包: $SYSTEM_LANG"
        download_success=true
    fi
fi

if [ "$download_success" = false ]; then
    echo "⚠️ 语言包下载失败，将使用默认语言"
    rm -f "$LANG_FILE"
fi

# 6. 注入 user.js（核心配置）
cat > "$PROFILE_DIR/user.js" <<'EOF'
// --- 核心：全局缩放 80% ---
user_pref("layout.css.devPixelsPerPx", "0.8");

// --- 中文语言设置 ---
user_pref("extensions.autoDisableScopes", 0);
user_pref("extensions.enabledScopes", 15);
user_pref("extensions.langpacks.signatures.required", false);
user_pref("intl.locale.requested", "zh-CN");
user_pref("intl.accept_languages", "zh-CN, zh, en-US, en");
user_pref("intl.locale.matchOS", false);

// --- 跳过所有欢迎页、导入向导、升级提示 ---
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.startup.homepage", "about:blank");
user_pref("startup.homepage_welcome_url", "about:blank");
user_pref("startup.homepage_welcome_url.additional", "");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.fullscreen.autohide", false);
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// --- 性能优化 ---
user_pref("general.smoothScroll", false);
user_pref("browser.tabs.animate", false);
user_pref("layers.acceleration.disabled", true);
EOF

# 7. 注入 xulstore.json（强制窗口大小）
cat > "$PROFILE_DIR/xulstore.json" <<EOF
{
  "chrome://browser/content/browser.xhtml": {
    "main-window": {
      "screenX": "0",
      "screenY": "0",
      "width": "1400",
      "height": "875",
      "sizemode": "maximized"
    }
  }
}
EOF

# 8. 配置 Fluxbox（保底全屏）
cat > $HOME/.fluxbox/init <<EOF
session.screen0.toolbar.visible: false
session.screen0.defaultDeco: NONE
session.screen0.fullMaximization: true
EOF

cat > $HOME/.fluxbox/apps <<EOF
[app] (class=Firefox)
  [Deco] {NONE}
  [Maximized] {yes}
  [Position] (UPPERLEFT) {0 0}
  [Dimensions] {100% 100%}
EOF

# 9. 启动服务
x11vnc -storepasswd "$VNC_PASS" $HOME/.vnc/passwd

echo "🖥️ Starting Xvfb ($RESOLUTION)..."
Xvfb :0 -screen 0 $RESOLUTION -ac &
sleep 3

echo "🪟 Starting Fluxbox..."
fluxbox &
sleep 2

echo "🔗 Starting x11vnc..."
x11vnc -display :0 -forever -rfbauth $HOME/.vnc/passwd \
    -listen localhost -xkb -rfbport 5900 \
    -ncache 10 -nap &
sleep 2

CURRENT_PORT=${SERVER_PORT:-25830}
echo "🌐 Starting noVNC on port $CURRENT_PORT..."
websockify --web /usr/share/novnc $CURRENT_PORT localhost:5900 &

echo "🦊 Starting Firefox (Clean Profile + Chinese)..."
sleep 3

while true; do
    firefox --profile "$PROFILE_DIR" --no-remote --display=:0 --new-instance
    echo "Firefox restarting..."
    sleep 3
done
