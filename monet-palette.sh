#!/system/bin/sh
# RescueX Monet (dynamic color) palette reader.
#
# This resolves the palette the Android framework actually generated, instead of
# approximating one from a single seed color. Android 12+ publishes the Material
# You tonal palettes as framework color resources (system_accent1_*,
# system_accent2_*, system_neutral1_*, system_neutral2_*), and `cmd overlay
# lookup` returns their resolved values for the current user. That command needs
# shell or root privileges, which this module already has, so the WebUI can read
# the same colors the system UI uses.
#
# Resource suffix to Material tone mapping is fixed by the platform:
#   0 -> tone 100, 10 -> 99, 50 -> 95, 100 -> 90, 200 -> 80, 300 -> 70,
#   400 -> 60, 500 -> 50, 600 -> 40, 700 -> 30, 800 -> 20, 900 -> 10, 1000 -> 0
#
# This reader is display-only. It never writes settings, never enables or
# fabricates an overlay, and never touches rescue state.

MONET_SCHEMA=1

_monet_normalize_color() {
    # Accepts #aarrggbb, #rrggbb, aarrggbb or rrggbb and emits #rrggbb.
    local value hex
    value=$(printf '%s' "${1:-}" | tr -d ' \t\r\n' | tr 'A-F' 'a-f')
    case "$value" in \#*) value=${value#\#} ;; esac
    case "$value" in
        *[!0-9a-f]*) return 1 ;;
    esac
    case ${#value} in
        8) hex=$(printf '%s' "$value" | cut -c3-8) ;;
        6) hex="$value" ;;
        *) return 1 ;;
    esac
    printf '#%s' "$hex"
}

_monet_lookup_resource() {
    # Prints the resolved #rrggbb for a framework color resource, or fails.
    local name="$1" out color
    out=$(cmd overlay lookup --user current android "android:color/$name" 2>/dev/null)
    [ -n "$out" ] || return 1
    # Some builds print diagnostics first, so take the last color-looking token.
    color=$(printf '%s\n' "$out" | tr -s ' \t' '\n' | grep -Eo '#?[0-9a-fA-F]{6,8}' | tail -n 1)
    [ -n "$color" ] || return 1
    _monet_normalize_color "$color"
}

# Palette entries needed by the WebUI. Each lookup is a separate `cmd` call, so
# the list is restricted to the roles the WebUI actually maps instead of reading
# all 65 framework colors on every refresh.
_monet_resource_list() {
    printf '%s\n' \
        system_accent1_0 \
        system_accent1_100 \
        system_accent1_200 \
        system_accent1_600 \
        system_accent1_700 \
        system_accent1_800 \
        system_accent2_100 \
        system_neutral1_10 \
        system_neutral1_100 \
        system_neutral1_500 \
        system_neutral1_800 \
        system_neutral1_900 \
        system_neutral2_100 \
        system_neutral2_200 \
        system_neutral2_700
}

monet_read_platform_palette() {
    local name value found=0
    for name in $(_monet_resource_list); do
        value=$(_monet_lookup_resource "$name" 2>/dev/null) || continue
        printf 'MONET_%s=%s\n' "$name" "$value"
        found=$((found + 1))
    done
    # A partial read is not trustworthy as a palette; require the accents and
    # neutrals that the WebUI maps directly.
    [ "$found" -ge 12 ]
}

# Fallback only: the seed color the user or the vendor selected. It is reported
# separately so the WebUI can label an approximation as such instead of
# presenting it as the real system palette.
#
# The setting is a JSON string such as
#   {"android.theme.customization.system_palette":"3f6bd8", ...}
# so the value is extracted by key rather than by line position.
_monet_json_value() {
    local json="$1" key="$2"
    printf '%s' "$json" \
        | tr -d ' \t\r\n' \
        | sed -n "s/.*\"[a-zA-Z.]*${key}\":\"\([^\"]*\)\".*/\1/p" \
        | head -n 1
}

monet_read_seed() {
    local raw seed=''
    raw=$(settings get secure theme_customization_overlay_packages 2>/dev/null)
    case "$raw" in
        *system_palette*) seed=$(_monet_json_value "$raw" 'system_palette') ;;
    esac
    [ -n "$seed" ] || seed=$(getprop persist.sys.theme.accentcolor 2>/dev/null)
    [ -n "$seed" ] || seed=$(getprop persist.sys.oplus.theme_color 2>/dev/null)
    [ -n "$seed" ] || seed=$(getprop persist.sys.theme_color 2>/dev/null)
    [ -n "$seed" ] || return 1
    _monet_normalize_color "$seed"
}

monet_read_style() {
    local raw style
    raw=$(settings get secure theme_customization_overlay_packages 2>/dev/null)
    style=$(_monet_json_value "$raw" 'theme_style' | tr -cd 'A-Za-z_' | cut -c1-24)
    [ -n "$style" ] || return 1
    printf '%s' "$style"
}

monet_status() {
    local palette seed source=none style
    printf 'MONET_SCHEMA=%s\n' "$MONET_SCHEMA"

    palette=$(monet_read_platform_palette 2>/dev/null) && source=platform_palette
    if [ "$source" = platform_palette ]; then
        printf '%s\n' "$palette"
    fi

    if seed=$(monet_read_seed 2>/dev/null); then
        printf 'MONET_SEED=%s\n' "$seed"
        [ "$source" = none ] && source=seed_approx
    fi

    style=$(monet_read_style 2>/dev/null) && printf 'MONET_STYLE=%s\n' "$style"

    # Light/dark selection stays in the WebUI: the WebView already reports the
    # effective scheme through prefers-color-scheme, so no extra probe is needed.
    printf 'MONET_SOURCE=%s\n' "$source"
    [ "$source" != none ]
}

case "${1:-status}" in
    status) monet_status ;;
    palette) monet_read_platform_palette ;;
    seed) monet_read_seed ;;
    style) monet_read_style ;;
    *)
        printf 'usage: %s [status|palette|seed|style]\n' "${0##*/}" >&2
        exit 2
        ;;
esac
