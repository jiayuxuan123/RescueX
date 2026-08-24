#!/bin/sh

set -u

PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." 2>/dev/null && pwd)
PASS_COUNT=0
FAIL_COUNT=0

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    return 1
}

assert_true() {
    "$@" || fail "expected success: $*"
}

assert_false() {
    if "$@"; then
        fail "expected failure: $*"
    fi
}

assert_eq() {
    expected=$1
    actual=$2
    label=$3
    [ "$expected" = "$actual" ] || fail "$label (expected=$expected actual=$actual)"
}

setup_case() {
    TEST_ROOT=$(mktemp -d)
    RX_WEBUI_CHOICE_FILE="$TEST_ROOT/persist/webui_install_preference"
    export RX_WEBUI_CHOICE_FILE
    getprop() {
        case "$1" in
            persist.sys.locale) printf 'zh-CN\n' ;;
            persist.sys.timezone) printf 'Asia/Shanghai\n' ;;
            *) printf '\n' ;;
        esac
    }
    # shellcheck source=../webui-choice.sh
    . "$PROJECT_DIR/webui-choice.sh"
    rx_webui_set_locale
}

teardown_case() {
    rm -rf "$TEST_ROOT"
    unset RX_WEBUI_CHOICE_FILE
}

case_pending_then_confirmed() {
    setup_case || return 1
    assert_false rx_webui_choice_is_confirmed || return 1
    assert_true rx_webui_choice_write_pending install volume || return 1
    assert_eq PENDING "$(rx_webui_choice_read STATE)" 'pending state' || return 1
    assert_eq install "$(rx_webui_choice_read CHOICE)" 'pending choice' || return 1
    assert_eq Asia/Shanghai "$(rx_webui_choice_read TIMEZONE)" 'timezone persistence' || return 1
    assert_true rx_webui_choice_write_confirmed install ui || return 1
    assert_true rx_webui_choice_is_confirmed || return 1
    assert_eq CONFIRMED "$(rx_webui_choice_read STATE)" 'confirmed state' || return 1
    [ ! -e "$RX_WEBUI_CHOICE_FILE.tmp.$$" ] || fail 'temporary preference file remains'
    teardown_case
}

case_deferred_choice_is_not_confirmed() {
    setup_case || return 1
    assert_true rx_webui_choice_write_deferred skip ui-defer || return 1
    assert_false rx_webui_choice_is_confirmed || return 1
    assert_eq DEFERRED "$(rx_webui_choice_read STATE)" 'deferred state' || return 1
    assert_eq skip "$(rx_webui_choice_read CHOICE)" 'deferred choice' || return 1
    teardown_case
}

case_corrupt_record_fails_closed() {
    setup_case || return 1
    mkdir -p "${RX_WEBUI_CHOICE_FILE%/*}"
    printf 'SCHEMA=999\nSTATE=CONFIRMED\nCHOICE=install\n' > "$RX_WEBUI_CHOICE_FILE"
    assert_false rx_webui_choice_is_valid || return 1
    assert_false rx_webui_choice_is_confirmed || return 1
    teardown_case
}

# A non-Chinese locale still selects English prose, but the volume-key lines
# stay bilingual so the choice cannot be misread.
case_foreign_locale_uses_english_prose() {
    setup_case || return 1
    getprop() { [ "$1" = persist.sys.locale ] && printf 'fr-FR\n' || printf 'Europe/Paris\n'; }
    rx_webui_set_locale
    assert_eq en "$RX_WEBUI_LANG" 'foreign locale selects English' || return 1
    assert_eq 'WebUI installation choice' "$(rx_webui_text title)" 'English title' || return 1
    assert_eq '[音量+] 安装 WebUI / Install WebUI' "$(rx_webui_text install)" 'bilingual install line' || return 1
    teardown_case
}

# Recovery and installer environments often expose no locale at all. Chinese is
# the default there so the installer never mixes languages mid-screen.
case_unknown_locale_defaults_to_chinese() {
    setup_case || return 1
    getprop() { return 1; }
    LC_ALL=''
    LANG=''
    rx_webui_set_locale
    assert_eq zh "$RX_WEBUI_LANG" 'unknown locale defaults to Chinese' || return 1
    assert_eq 'WebUI 安装选择' "$(rx_webui_text title)" 'Chinese title' || return 1
    teardown_case
}

case_chinese_variants_select_chinese() {
    setup_case || return 1
    for value in zh-CN zh-TW zh-Hans-CN cmn-Hans yue-HK; do
        getprop() { [ "$1" = persist.sys.locale ] && printf '%s\n' "$LOCALE_UNDER_TEST" || printf 'Asia/Shanghai\n'; }
        LOCALE_UNDER_TEST=$value
        rx_webui_set_locale
        assert_eq zh "$RX_WEBUI_LANG" "Chinese variant $value" || { teardown_case; return 1; }
    done
    teardown_case
}

# The three volume-key lines must never be single-language, in either direction.
case_key_prompt_is_always_bilingual() {
    setup_case || return 1
    for locale in zh-CN en-US de-DE; do
        LOCALE_UNDER_TEST=$locale
        getprop() { [ "$1" = persist.sys.locale ] && printf '%s\n' "$LOCALE_UNDER_TEST" || printf 'UTC\n'; }
        rx_webui_set_locale
        for key in install skip timeout; do
            text=$(rx_webui_text "$key")
            case "$text" in
                *音量*|*秒*) ;;
                *) fail "missing Chinese in $key for $locale"; teardown_case; return 1 ;;
            esac
            case "$text" in
                *Install*|*Skip*|*input*) ;;
                *) fail "missing English in $key for $locale"; teardown_case; return 1 ;;
            esac
        done
    done
    teardown_case
}

run_case() {
    name=$1
    shift
    if ("$@"); then
        PASS_COUNT=$((PASS_COUNT + 1))
        printf 'ok - %s\n' "$name"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        printf 'not ok - %s\n' "$name"
    fi
}

run_case 'pending WebUI choice can be confirmed atomically' case_pending_then_confirmed
run_case 'deferred WebUI choice is not treated as confirmed' case_deferred_choice_is_not_confirmed
run_case 'corrupt WebUI preference fails closed' case_corrupt_record_fails_closed
run_case 'foreign locale uses English prose' case_foreign_locale_uses_english_prose
run_case 'unknown locale defaults to Chinese' case_unknown_locale_defaults_to_chinese
run_case 'Chinese locale variants select Chinese' case_chinese_variants_select_chinese
run_case 'volume-key prompt is always bilingual' case_key_prompt_is_always_bilingual

printf '\nWebUI choice tests: %s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
