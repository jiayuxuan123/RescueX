/* RescueX v3.0.1 - WebUI 控制器
 * MD3 + i18n 中英切换 + 模块选择器 + 配置导入导出 + 快照 + 诊断报告
 * 兼容：KSU / Magisk v27+ / MMRL
 *
 * v3.0.1 新增（专业级升级）:
 * - 嫌疑模块追踪面板（已知良好模块列表对比）
 * - 三级救砖级别展示与手动重置
 * - APP 解冻功能（删除 package-restrictions.xml）
 * - 脚本目录锁定功能
 */

(function () {
'use strict';

// === 安全校验常量 ===
const MODULE_ID_RE = /^[A-Za-z0-9._-]+$/;
const ALLOWED_BASES = ['/data/adb/modules', '/data/adb/ksu/modules', '/data/adb/ap/modules', '/data/adb/ap_modules'];
const DEFAULT_BASE_PATH = '/data/adb/modules/RescueX';
const EXEC_DEFAULT_TIMEOUT_MS = 15000;
const EXEC_STATS_TIMEOUT_MS = 20000;
const EXEC_REPORT_TIMEOUT_MS = 60000;

// UTF-8 安全的 base64 编码：用 TextEncoder 代替已弃用的 unescape() 组合写法
function utf8ToBase64(str) {
    const bytes = new TextEncoder().encode(str);
    let binary = '';
    for (let i = 0; i < bytes.length; i++) {
        binary += String.fromCharCode(bytes[i]);
    }
    return btoa(binary);
}

// === i18n 多语言 ===
const I18N = {
    zh: {
        current_status: '当前状态',
        boot_status: '启动状态',
        last_result: '上次启动结果',
        fail_count: '连续失败次数',
        boot_duration: '上次启动耗时',
        ota_mode: 'OTA 模式',
        watchdog: '看门狗',
        rescue_count: '救砖次数',
        fail_progress: '失败进度',
        config: '救砖参数',
        reboot_threshold: '连续重启阈值',
        threshold_hint: '达到此次数后触发全量救砖',
        boot_timeout: '开机超时',
        timeout_hint: '超时未完成开机则判定失败',
        ota_timeout: 'OTA 升级超时',
        ota_hint: '检测到 OTA 时使用此超时',
        grace_period: '用户重启宽限期',
        grace_hint: '短时间内重启不计入失败',
        advanced: '高级选项',
        opt_log: '记录详细启动日志',
        opt_progressive: '渐进式救砖（先禁用最近安装的模块）',
        opt_autoreenable: '救砖后自动恢复模块（实验性）',
        opt_dryrun: 'DRY_RUN 模式（仅记录日志不真禁用）',
        save_config: '保存配置',
        export_config: '导出配置',
        import_config: '导入配置',
        // v2.4 补丁更新
        patch_update: '补丁更新',
        patch_detected: '检测到补丁更新',
        patch_fail_count: '补丁失败次数',
        patch_timeout: '补丁更新超时',
        patch_timeout_hint: '补丁更新时使用此超时（默认 180 秒）',
        patch_fail_threshold: '补丁失败阈值',
        patch_fail_threshold_hint: '达到此次数后回滚补丁（不清整机）',
        opt_patch_auto_rollback: '补丁失败自动回滚（保留用户数据）',
        toggle_patch_flag: '设置/清除补丁标记',
        whitelist: '白名单模块',
        whitelist_desc: '救砖时不会被禁用的模块。勾选要保留的模块，保存即可。',
        refresh_modules: '刷新模块列表',
        save_whitelist: '保存白名单',
        module_status: '模块状态',
        module_status_desc: '当前被禁用的模块列表（含非 RescueX 禁用的）。',
        snapshots: '快照管理',
        snapshot_desc: '记录当前所有模块的启用/禁用状态，出问题可一键回滚。',
        take_snapshot: '拍快照',
        restore_baseline: '恢复稳定基线',
        no_snapshots: '暂无快照',
        actions: '手动操作',
        disable_all: '禁用所有模块',
        enable_all: '恢复所有模块',
        test_watchdog: '测试看门狗',
        reboot: '重启设备',
        generate_decision_report: '生成救援决策报告',
        generate_report: '生成诊断报告',
        script_risk_title: '高风险脚本拦截',
        script_risk_badge: '已拦截',
        script_risk_desc: '检测到疑似擦除/格式化脚本，RescueX 已优先拦截并禁用对应入口。',
        script_risk_module: '模块',
        script_risk_reason: '命中规则',
        script_risk_action: '处理动作',
        script_risk_time: '检测时间',
        script_risk_clear: '清除提醒',
        script_risk_toast: '检测到高风险脚本，已拦截并禁用相关入口',
        logs: '日志与历史',
        log: '日志',
        history: '历史',
        refresh: '刷新',
        copy: '复制',
        export: '导出',
        clear: '清空',
        about: '关于',
        version: '版本',
        manager: '管理器',
        source_code: '源码',
        update_notice: '更新公告',
        update_notice_title: '自动快照去重与在线更新接入',
        update_notice_desc: '同一轮启动只保留一次自动快照，WebUI 已加入 GitHub 开源入口，模块元数据已接入 GitHub Release 在线更新。',
        open_source_repo: '开源仓库',
        view_releases: '版本发布',
        about_desc: 'RescueX 通过监控启动失败次数和开机超时，自动禁用问题模块以救砖。兼容 Magisk / KernelSU / APatch。基于 uptime 单调时钟计算启动耗时，不受 RTC 同步影响。v3.2.2 继续整合快照、稳定基线、决策报告、高风险脚本拦截与 GitHub 在线更新。',
        loading: '加载中...',
        // 状态文本
        status_ok: '系统正常',
        status_ok_meta: '上次启动成功',
        status_rescued: '已救砖',
        status_rescued_meta: '问题模块已被禁用',
        status_booting: '启动中',
        status_booting_meta: '系统正在启动',
        status_disabled: '模块已禁用',
        status_disabled_meta: 'RescueX 未生效',
        status_init: '初始化',
        status_init_meta: '首次运行',
        status_unknown: '未知',
        status_unknown_meta: '无状态数据',
        badge_ok: '正常',
        badge_rescued: '已救砖',
        badge_booting: '启动中',
        badge_disabled: '已禁用',
        badge_init: '初始化',
        badge_unknown: '未知',
        // 看门狗状态
        wd_running: '运行中',
        wd_idle: '未运行',
        // Toast
        saved: '已保存',
        save_failed: '保存失败',
        copied: '已复制到剪贴板',
        copy_failed: '复制失败',
        no_content: '无内容可复制',
        exported: '已导出',
        export_failed: '导出失败',
        refreshed: '已刷新',
        cleared: '已清空',
        // 模块状态
        mod_enabled: '启用',
        mod_disabled: '禁用',
        mod_no_modules: '未找到其他模块',
        mod_no_disabled: '当前没有被禁用的模块',
        // 快照
        snapshot_taken: '快照已创建',
        snapshot_restored: '快照已恢复，重启后生效',
        snapshot_deleted: '快照已删除',
        snapshot_failed: '操作失败',
        baseline_restored: '稳定基线已恢复，重启后生效',
        decision_report_title: '救援决策报告',
        script_risk_reason_rm_rf: '敏感路径递归删除',
        script_risk_reason_find_delete: '敏感路径批量删除',
        script_risk_reason_format: '格式化命令',
        script_risk_reason_dd: '原始块设备写入',
        script_risk_reason_wipe: '擦除或格式化调用',
        script_risk_action_module_disabled: '模块已禁用',
        script_risk_action_script_blocked: '脚本已锁定',
        script_risk_cleared: '高风险脚本提醒已清除',
        // 确认对话框
        confirm_title: '确认操作',
        confirm_disable_all: '将禁用除 RescueX 和白名单外的全部模块，重启后生效。是否继续？',
        confirm_enable_all: '将移除所有模块的 disable 标记（不包括 RescueX）。是否继续？',
        confirm_test_wd: '将启动一个 10 秒短超时看门狗。10 秒后若 boot 未完成将触发救砖（禁用非白名单模块并重启）。建议先开启 DRY_RUN。是否继续？',
        confirm_reboot: '将立即重启设备。RescueX 会在下次启动时检查启动状态。是否继续？',
        confirm_clear: '此操作不可撤销。是否继续？',
        confirm_restore_baseline: '将按最近一次稳定基线恢复模块启用状态，重启后生效。是否继续？',
        btn_confirm: '确认',
        btn_cancel: '取消',
        // 操作结果
        disabled_count: '已禁用 N 个模块，重启后生效',
        enabled_count: '已恢复 N 个模块，重启后生效',
        // 报告
        report_title: '诊断报告',
        report_generated: '报告已生成',
        // 环境错误
        env_error_title: '不兼容的环境',
        env_error_desc: '当前未运行在 KernelSU / APatch / Magisk v27+ WebUI 容器中。',
        env_error_solution: '请在以下任意一个环境中打开本模块：',
        // 时钟
        clock_unsync: '时钟未同步',
        boot_error: '启动异常',
        // 单位
        seconds: '秒',
        // 配置导入导出
        config_exported: '配置已导出',
        config_imported: '配置已导入，重启后生效',
        config_import_failed: '配置文件格式错误',
        invalid_config: '配置文件无效',
        // 模块选择器
        select_all: '全选',
        deselect_all: '取消全选',
        // v2.5 新增
        stats_panel: '启动统计',
        success_rate: '启动成功率',
        avg_boot_time: '平均启动耗时',
        total_boots: '总启动次数',
        rescue_times: '救砖次数',
        success_count: '成功启动',
        failed_count: '失败启动',
        last_success: '最近成功',
        last_rescue: '最近救砖',
        watchdog_poll: '看门狗轮询间隔',
        watchdog_poll_hint: '长超时场景会自动放大（v2.5）',
        feature_intro: '功能介绍',
        privacy_policy: '隐私协议',
        usage_notice: '使用须知',
        // 引导
        onboarding_title: '欢迎使用 RescueX',
        onboarding_subtitle: '可靠的 Android 启动失败保护',
        onboarding_step1_title: '自动救砖',
        onboarding_step1_desc: '连续启动失败达到阈值（默认 3 次）或开机超时，自动禁用问题模块并重启，打破 bootloop。',
        onboarding_step2_title: '智能识别',
        onboarding_step2_desc: '区分 OTA 升级、系统补丁、用户主动重启，避免正常场景被误判为失败。Recovery/Fastboot 模式自动跳过计数。',
        onboarding_step3_title: '白名单保护',
        onboarding_step3_desc: '字体、音效等关键模块可加入白名单，救砖时不会被禁用。',
        onboarding_step4_title: 'DRY_RUN 验证',
        onboarding_step4_desc: '首次使用建议开启 DRY_RUN 模式，仅记录日志不实际禁用，验证逻辑符合预期后再正式启用。',
        onboarding_step5_title: 'WebUI 管理',
        onboarding_step5_desc: '所有参数、白名单、快照、诊断报告均可通过此 WebUI 管理。支持配置导入导出。',
        onboarding_ack: '我已了解，开始使用',
        onboarding_skip: '稍后再看',
        onboarding_new_features: 'v3.0 新功能',
        onboarding_new_features_desc: '三级渐进式救砖（嫌疑禁用→全量+脚本锁定→APP解冻）、嫌疑模块精准追踪、脚本目录锁定、APP 自动解冻',
        // 文档
        doc_close: '关闭',
        features_title: 'RescueX 功能介绍',
        privacy_title: 'RescueX 隐私协议',
        usage_title: 'RescueX 使用须知',
        // 其他
        never: '从未',
        just_now: '刚刚',
        minutes_ago: '分钟前',
        hours_ago: '小时前',
        days_ago: '天前',
        unknown_time: '未知',
        loading_failed: '加载失败，请刷新重试',
        stats_unavailable: '统计读取失败，请检查模块安装路径',
        // v2.7 新增
        audit_log: '救砖审计',
        audit_log_desc: '记录所有救砖操作的详细信息（操作类型、时间、影响的模块）。',
        no_audit: '暂无审计记录',
        toggle_enable: '启用',
        toggle_disable: '禁用',
        export_full: '导出完整状态',
        export_full_desc: '导出配置、白名单、启动状态、审计日志等全部数据。',
        boot_trend: '启动耗时趋势',
        custom_dirs_title: '自定义目录权限',
        custom_dirs_desc: '模块启动时自动对指定目录设置权限。默认仅对模块自身持久目录 /data/adb/rescuex_data 授予 770。',
        no_custom_dirs: '未设置自定义目录',
        add_custom_dir: '添加目录',
        save_custom_dirs: '保存',
        dir_path: '目录路径',
        dir_perms: '权限',
        // v3.0 新增
        suspect_panel: '嫌疑模块追踪',
        suspect_panel_desc: '启动成功后自动记录已知良好模块列表。下次启动失败时对比差异，精准定位新增/新启用的模块。',
        good_modules_count: '已知良好模块数',
        suspect_count: '最近检测嫌疑数',
        save_good_modules_now: '立即保存当前列表',
        clear_suspect_log: '清除嫌疑日志',
        reset_rescue_level: '重置救砖级别',
        unfreeze_apps: 'APP 解冻',
        lock_script_dirs: '锁定脚本目录',
        rescue_level_label: '当前救砖级别',
        rescue_level_0: '级别 0: 精准嫌疑禁用',
        rescue_level_1: '级别 1: 全量+脚本锁定',
        rescue_level_2: '级别 2: APP 解冻（最后手段）',
        unfreeze_confirm: '将删除 package-restrictions.xml 来解冻所有被冻结的应用。操作后需重启。是否继续？',
        unfreeze_done: 'APP 解冻完成，请重启设备',
        unfreeze_skip: '未发现需要解冻的限制文件',
        lock_scripts_confirm: '将锁定所有脚本目录（service.d/post-fs-data.d 等）的执行权限。操作后需重启。是否继续？',
        lock_scripts_done: '脚本目录已锁定，请重启设备',
        good_modules_saved: '已知良好模块列表已保存',
        suspect_cleared: '嫌疑日志已清除',
        rescue_level_reset: '救砖级别已重置为 0',
        readiness_title: '救砖就绪度',
        readiness_baseline: '已知良好基线',
        readiness_policy: '目录权限策略',
        readiness_mode: '当前模式',
        readiness_level: '当前救砖级别',
        readiness_score_good: '就绪',
        readiness_score_warn: '关注',
        readiness_score_danger: '风险',
        readiness_mode_active: '正式保护',
        readiness_mode_dry: '演练模式',
        readiness_policy_clean: '安全',
        readiness_policy_risky: '待清理',
        readiness_baseline_missing: '未建立',
        readiness_baseline_ready: '已建立',
        readiness_item_baseline_ok_title: '基线已建立',
        readiness_item_baseline_ok_desc: '成功启动后会用它追踪新增和重新启用的模块。',
        readiness_item_baseline_missing_title: '缺少已知良好基线',
        readiness_item_baseline_missing_desc: '先在稳定状态下保存当前模块列表，后续才能精准命中嫌疑模块。',
        readiness_item_dry_title: '当前处于 DRY_RUN',
        readiness_item_dry_desc: '此模式只记录动作，适合验证逻辑。',
        readiness_item_mode_ok_title: '自动救砖已执行',
        readiness_item_mode_ok_desc: '启动失败达到条件后会实际禁用模块。',
        readiness_item_policy_ok_title: '目录权限范围安全',
        readiness_item_policy_ok_desc: '自定义目录限制在 RescueX 自身数据范围内。',
        readiness_item_policy_risky_title: '检测到历史目录配置超出安全范围',
        readiness_item_policy_risky_desc: '保存一次目录配置后会自动剔除超出白名单前缀的路径。',
        readiness_item_fail_warn_title: '失败计数已接近阈值',
        readiness_item_fail_warn_desc: '建议先拍快照并确认最近变更的模块。',
        readiness_item_level_warn_title: '当前处于升级救砖级别',
        readiness_item_level_warn_desc: '最近一轮救砖已经进入更激进的策略。',
        readiness_item_watchdog_warn_title: '启动中但看门狗未确认存活',
        readiness_item_watchdog_warn_desc: '建议检查 watchdog.sh 权限和宿主执行环境。',
        readiness_item_disabled_title: 'RescueX 当前处于禁用状态',
        readiness_item_disabled_desc: '禁用后不会执行自动救砖。',
        custom_dir_invalid: '目录不在允许范围内',
        custom_dir_rejected: '已过滤 N 条超出安全范围的目录配置',
    },
    en: {
        current_status: 'Current Status',
        boot_status: 'Boot Status',
        last_result: 'Last Result',
        fail_count: 'Fail Count',
        boot_duration: 'Boot Duration',
        ota_mode: 'OTA Mode',
        watchdog: 'Watchdog',
        rescue_count: 'Rescue Count',
        fail_progress: 'Fail Progress',
        config: 'Configuration',
        reboot_threshold: 'Reboot Threshold',
        threshold_hint: 'Trigger full rescue after this many failures',
        boot_timeout: 'Boot Timeout',
        timeout_hint: 'Fail if boot not completed within this time',
        ota_timeout: 'OTA Timeout',
        ota_hint: 'Used when OTA update is detected',
        grace_period: 'Reboot Grace Period',
        grace_hint: 'Short reboots not counted as failures',
        advanced: 'Advanced',
        opt_log: 'Enable detailed boot logging',
        opt_progressive: 'Progressive rescue (disable recently installed first)',
        opt_autoreenable: 'Auto re-enable modules after rescue (experimental)',
        opt_dryrun: 'DRY_RUN mode (log only, no actual disable)',
        save_config: 'Save Config',
        export_config: 'Export',
        import_config: 'Import',
        // v2.4 patch update
        patch_update: 'Patch Update',
        patch_detected: 'Patch Detected',
        patch_fail_count: 'Patch Fail Count',
        patch_timeout: 'Patch Update Timeout',
        patch_timeout_hint: 'Used when patch update is detected (default 180s)',
        patch_fail_threshold: 'Patch Fail Threshold',
        patch_fail_threshold_hint: 'Roll back patch after this many failures (no data wipe)',
        opt_patch_auto_rollback: 'Auto roll back patch on failure (preserve user data)',
        toggle_patch_flag: 'Set/Clear Patch Flag',
        whitelist: 'Whitelist',
        whitelist_desc: 'Modules that will NOT be disabled during rescue. Check the ones to keep.',
        refresh_modules: 'Refresh Module List',
        save_whitelist: 'Save Whitelist',
        module_status: 'Module Status',
        module_status_desc: 'Currently disabled modules (including those disabled by other tools).',
        snapshots: 'Snapshots',
        snapshot_desc: 'Record current enable/disable state of all modules. Roll back when something goes wrong.',
        take_snapshot: 'Take Snapshot',
        restore_baseline: 'Restore Baseline',
        no_snapshots: 'No snapshots yet',
        actions: 'Actions',
        disable_all: 'Disable All',
        enable_all: 'Enable All',
        test_watchdog: 'Test Watchdog',
        reboot: 'Reboot',
        generate_decision_report: 'Decision Report',
        generate_report: 'Generate Report',
        script_risk_title: 'Risk Script Blocked',
        script_risk_badge: 'Blocked',
        script_risk_desc: 'A destructive wipe or format script was detected. RescueX blocked the entry point first.',
        script_risk_module: 'Module',
        script_risk_reason: 'Rule',
        script_risk_action: 'Action',
        script_risk_time: 'Detected',
        script_risk_clear: 'Clear Alert',
        script_risk_toast: 'High-risk script detected and blocked',
        logs: 'Logs & History',
        log: 'Log',
        history: 'History',
        refresh: 'Refresh',
        copy: 'Copy',
        export: 'Export',
        clear: 'Clear',
        about: 'About',
        version: 'Version',
        manager: 'Manager',
        source_code: 'Source',
        update_notice: 'Update Notice',
        update_notice_title: 'Auto snapshot dedupe and online updates',
        update_notice_desc: 'Each boot session now keeps a single automatic snapshot. The WebUI includes GitHub entry points, and module metadata now supports GitHub Release-based online updates.',
        open_source_repo: 'Open Repository',
        view_releases: 'View Releases',
        about_desc: 'RescueX monitors boot failures and auto-disables problematic modules to break bootloops. Compatible with Magisk / KernelSU / APatch. Uses uptime monotonic clock for boot duration, unaffected by RTC sync. v3.2.2 continues the snapshot, baseline restore, decision report, high-risk script interception, and GitHub-based online update pass.',
        loading: 'Loading...',
        status_ok: 'OPERATIONAL',
        status_ok_meta: 'Last boot succeeded',
        status_rescued: 'RESCUED',
        status_rescued_meta: 'Problematic modules disabled',
        status_booting: 'BOOTING',
        status_booting_meta: 'System is booting',
        status_disabled: 'DISABLED',
        status_disabled_meta: 'RescueX inactive',
        status_init: 'INITIALIZING',
        status_init_meta: 'First run',
        status_unknown: 'UNKNOWN',
        status_unknown_meta: 'No status data',
        badge_ok: 'OK',
        badge_rescued: 'RESCUED',
        badge_booting: 'BOOTING',
        badge_disabled: 'DISABLED',
        badge_init: 'INIT',
        badge_unknown: 'UNKNOWN',
        wd_running: 'Running',
        wd_idle: 'Idle',
        saved: 'Saved',
        save_failed: 'Save failed',
        copied: 'Copied to clipboard',
        copy_failed: 'Copy failed',
        no_content: 'Nothing to copy',
        exported: 'Exported',
        export_failed: 'Export failed',
        refreshed: 'Refreshed',
        cleared: 'Cleared',
        mod_enabled: 'Enabled',
        mod_disabled: 'Disabled',
        mod_no_modules: 'No other modules found',
        mod_no_disabled: 'No disabled modules',
        snapshot_taken: 'Snapshot created',
        snapshot_restored: 'Snapshot restored, effective after reboot',
        snapshot_deleted: 'Snapshot deleted',
        snapshot_failed: 'Operation failed',
        baseline_restored: 'Known-good baseline restored, effective after reboot',
        decision_report_title: 'Rescue Decision Report',
        script_risk_reason_rm_rf: 'Recursive delete on sensitive path',
        script_risk_reason_find_delete: 'Bulk delete on sensitive path',
        script_risk_reason_format: 'Format command',
        script_risk_reason_dd: 'Raw block write',
        script_risk_reason_wipe: 'Wipe or format invocation',
        script_risk_action_module_disabled: 'Module disabled',
        script_risk_action_script_blocked: 'Script blocked',
        script_risk_cleared: 'Risk script alert cleared',
        confirm_title: 'Confirm',
        confirm_disable_all: 'This will disable all modules except RescueX and whitelisted ones. Effective after reboot. Continue?',
        confirm_enable_all: 'This will remove all disable marks (except RescueX). Continue?',
        confirm_test_wd: 'This will start a 10s short-timeout watchdog. If boot not completed in 10s, rescue will be triggered (disable non-whitelisted modules and reboot). Consider enabling DRY_RUN first. Continue?',
        confirm_reboot: 'Device will reboot immediately. RescueX will check boot status on next boot. Continue?',
        confirm_clear: 'This cannot be undone. Continue?',
        confirm_restore_baseline: 'Restore module states from the last known-good baseline. Effective after reboot. Continue?',
        btn_confirm: 'Confirm',
        btn_cancel: 'Cancel',
        disabled_count: 'Disabled N modules, effective after reboot',
        enabled_count: 'Enabled N modules, effective after reboot',
        report_title: 'Diagnostic Report',
        report_generated: 'Report generated',
        env_error_title: 'Incompatible Environment',
        env_error_desc: 'Not running in KernelSU / APatch / Magisk v27+ WebUI container.',
        env_error_solution: 'Please open this module in one of these environments:',
        clock_unsync: 'Clock unsynced',
        boot_error: 'Boot error',
        seconds: 's',
        config_exported: 'Config exported',
        config_imported: 'Config imported, effective after reboot',
        config_import_failed: 'Invalid config file format',
        invalid_config: 'Invalid config',
        select_all: 'Select All',
        deselect_all: 'Deselect All',
        // v2.5 新增
        stats_panel: 'Boot Statistics',
        success_rate: 'Success Rate',
        avg_boot_time: 'Avg Boot Time',
        total_boots: 'Total Boots',
        rescue_times: 'Rescue Times',
        success_count: 'Successful Boots',
        failed_count: 'Failed Boots',
        last_success: 'Last Success',
        last_rescue: 'Last Rescue',
        watchdog_poll: 'Watchdog Poll Interval',
        watchdog_poll_hint: 'Auto-scales for long timeouts (v2.5)',
        feature_intro: 'Features',
        privacy_policy: 'Privacy',
        usage_notice: 'Usage Notice',
        // 引导
        onboarding_title: 'Welcome to RescueX',
        onboarding_subtitle: 'Reliable Android bootloop protection',
        onboarding_step1_title: 'Auto Rescue',
        onboarding_step1_desc: 'After consecutive boot failures reach threshold (default 3) or boot timeout, problematic modules are auto-disabled and device reboots to break bootloop.',
        onboarding_step2_title: 'Smart Detection',
        onboarding_step2_desc: 'Distinguishes OTA updates, system patches, user-initiated reboots to avoid false positives. Recovery/Fastboot modes are skipped.',
        onboarding_step3_title: 'Whitelist Protection',
        onboarding_step3_desc: 'Critical modules (fonts, audio, etc.) can be whitelisted to survive rescue operations.',
        onboarding_step4_title: 'DRY_RUN Validation',
        onboarding_step4_desc: 'For first-time use, enable DRY_RUN mode to log-only without actually disabling. Verify logic before enabling for real.',
        onboarding_step5_title: 'WebUI Management',
        onboarding_step5_desc: 'All parameters, whitelist, snapshots, diagnostic reports are managed via this WebUI. Config import/export supported.',
        onboarding_ack: 'Got it, start using',
        onboarding_skip: 'Later',
        onboarding_new_features: 'New in v3.0',
        onboarding_new_features_desc: 'Three-level rescue (suspect disable → full+scripts lock → APP unfreeze), suspect module tracking, script directory locking, APP auto-unfreeze',
        // 文档
        doc_close: 'Close',
        features_title: 'RescueX Features',
        privacy_title: 'RescueX Privacy Policy',
        usage_title: 'RescueX Usage Notice',
        // 其他
        never: 'Never',
        just_now: 'Just now',
        minutes_ago: 'min ago',
        hours_ago: 'h ago',
        days_ago: 'd ago',
        unknown_time: 'Unknown',
        loading_failed: 'Load failed, please refresh',
        stats_unavailable: 'Stats unavailable, check module path',
        // v2.7 new
        audit_log: 'Rescue Audit',
        audit_log_desc: 'Detailed records of all rescue operations (type, time, affected modules).',
        no_audit: 'No audit records',
        toggle_enable: 'Enable',
        toggle_disable: 'Disable',
        export_full: 'Export Full State',
        export_full_desc: 'Export all data including config, whitelist, boot status, audit log, etc.',
        boot_trend: 'Boot Duration Trend',
        custom_dirs_title: 'Custom Directory Permissions',
        custom_dirs_desc: 'Automatically set permissions on specified directories at boot. Default: 770 on /data/adb/rescuex_data.',
        no_custom_dirs: 'No custom directories configured',
        add_custom_dir: 'Add Directory',
        save_custom_dirs: 'Save',
        dir_path: 'Directory Path',
        dir_perms: 'Permissions',
        // v3.0 new
        suspect_panel: 'Suspect Module Tracking',
        suspect_panel_desc: 'Automatically saves known-good module list after successful boot. On next boot failure, compares differences to pinpoint newly installed/enabled modules.',
        good_modules_count: 'Known Good Modules',
        suspect_count: 'Recent Suspects',
        save_good_modules_now: 'Save Current List Now',
        clear_suspect_log: 'Clear Suspect Log',
        reset_rescue_level: 'Reset Rescue Level',
        unfreeze_apps: 'APP Unfreeze',
        lock_script_dirs: 'Lock Script Dirs',
        rescue_level_label: 'Current Rescue Level',
        rescue_level_0: 'Level 0: Precise Suspect Disable',
        rescue_level_1: 'Level 1: Full Disable + Lock Scripts',
        rescue_level_2: 'Level 2: APP Unfreeze (Last Resort)',
        unfreeze_confirm: 'This will delete package-restrictions.xml to unfreeze all frozen apps. Reboot required. Continue?',
        unfreeze_done: 'Apps unfrozen. Please reboot.',
        unfreeze_skip: 'No restriction files found.',
        lock_scripts_confirm: 'This will lock all script directories (service.d/post-fs-data.d etc.). Reboot required. Continue?',
        lock_scripts_done: 'Script directories locked. Please reboot.',
        good_modules_saved: 'Known good module list saved.',
        suspect_cleared: 'Suspect log cleared.',
        rescue_level_reset: 'Rescue level reset to 0.',
        readiness_title: 'Rescue Readiness',
        readiness_baseline: 'Known-good baseline',
        readiness_policy: 'Directory policy',
        readiness_mode: 'Current mode',
        readiness_level: 'Current rescue level',
        readiness_score_good: 'Ready',
        readiness_score_warn: 'Watch',
        readiness_score_danger: 'Risk',
        readiness_mode_active: 'Active',
        readiness_mode_dry: 'Dry run',
        readiness_policy_clean: 'Safe',
        readiness_policy_risky: 'Needs cleanup',
        readiness_baseline_missing: 'Missing',
        readiness_baseline_ready: 'Ready',
        readiness_item_baseline_ok_title: 'Known-good baseline is present',
        readiness_item_baseline_ok_desc: 'Successful boots can use it to track newly added or re-enabled modules.',
        readiness_item_baseline_missing_title: 'Known-good baseline is missing',
        readiness_item_baseline_missing_desc: 'Save the current module list while the device is stable to unlock precise suspect targeting.',
        readiness_item_dry_title: 'DRY_RUN is active',
        readiness_item_dry_desc: 'Actions are logged only and the setup stays in rehearsal mode.',
        readiness_item_mode_ok_title: 'Automatic rescue is active',
        readiness_item_mode_ok_desc: 'Modules will be disabled when boot failures hit the configured threshold.',
        readiness_item_policy_ok_title: 'Custom directory scope is safe',
        readiness_item_policy_ok_desc: 'Directory permissions stay inside RescueX-owned data paths.',
        readiness_item_policy_risky_title: 'Legacy directory entries exceed the safe scope',
        readiness_item_policy_risky_desc: 'Save the directory settings once to remove paths outside the allowed prefixes.',
        readiness_item_fail_warn_title: 'Failure count is close to the threshold',
        readiness_item_fail_warn_desc: 'Take a snapshot and review recent module changes now.',
        readiness_item_level_warn_title: 'Rescue escalation level is active',
        readiness_item_level_warn_desc: 'Recent rescue activity already moved into a more aggressive strategy.',
        readiness_item_watchdog_warn_title: 'Boot is in progress and watchdog is not confirmed',
        readiness_item_watchdog_warn_desc: 'Check watchdog.sh permissions and the host execution container.',
        readiness_item_disabled_title: 'RescueX is disabled',
        readiness_item_disabled_desc: 'Automatic rescue does not run while the module is disabled.',
        custom_dir_invalid: 'Path is outside the allowed scope',
        custom_dir_rejected: 'Filtered N directory entries outside the safe scope',
    }
};

class RescueXUI {
    constructor() {
        this.selfId = 'RescueX';
        this.setBasePath(DEFAULT_BASE_PATH);
        this.moduleBases = ALLOWED_BASES;

        this.config = {};
        this.refreshTimer = null;
        this.currentTab = 'log';
        this.isLoading = false;
        this.lang = localStorage.getItem('rescuex_lang') || 'zh';
        this.modulesCache = []; // 模块列表缓存
        this.firstRun = 0;      // v2.5: 首次运行标记（0=已确认，1=首次安装，2=从旧版升级）
        this.onboardingShown = false;
        this.lastStatus = null;
        this.goodModuleStats = { enabled: 0, total: 0 };
        this.rescueLevel = 0;
        this._customDirs = [];
        this.scriptRiskAlert = null;
        this.dashboardSnapshot = null;
        this.dashboardSnapshotFetchedAt = 0;
        this.dashboardSnapshotPromise = null;
        this._easterTapCount = 0;
        this._easterTapTimer = null;
        this._easterLangHits = [];
        this._easterSubtitleTimer = null;

        this.init();
    }

    async init() {
        // 环境检测：支持 KSU / Magisk v27+ / MMRL
        const hasKsu = typeof ksu !== 'undefined' && ksu.exec;
        const hasMagisk = typeof magisk !== 'undefined' && magisk.exec;
        if (!hasKsu && !hasMagisk) {
            this.showEnvError();
            return;
        }
        this.bridge = hasKsu ? ksu : magisk;
        // 记录标记而非在别处直接比较 `this.bridge === ksu`：
        // 若宿主容器压根未声明 ksu 变量（而非设为 undefined），直接引用会在严格模式下抛 ReferenceError
        this.isKsu = !!hasKsu;

        // 应用初始语言
        this.applyLang(this.lang);

        // 事件委托
        document.body.addEventListener('click', (e) => {
            const target = e.target.closest('[data-action]');
            if (target) {
                e.preventDefault();
                const action = target.dataset.action;
                if (typeof this[action] === 'function') this[action](e, target);
                return;
            }
            // v2.7: 单模块切换按钮
            const modToggle = e.target.closest('.mod-toggle');
            if (modToggle) {
                const modId = modToggle.dataset.modId;
                const enable = modToggle.dataset.modEnabled !== '1';
                this.toggleModule(modId, enable);
                return;
            }
            const tab = e.target.closest('.tab');
            if (tab) this.switchTab(tab.dataset.tab);
            const langBtn = e.target.closest('.lang-btn');
            if (langBtn) this.switchLang(langBtn.dataset.lang);
        });

        // 输入校验
        ['cfg-threshold', 'cfg-timeout', 'cfg-ota-timeout', 'cfg-grace', 'cfg-patch-timeout', 'cfg-patch-fail-threshold', 'cfg-watchdog-poll'].forEach(id => {
            const el = this.qs(`#${id}`);
            if (el) el.addEventListener('blur', () => this.clampInput(el));
        });

        // v2.5: 帮助按钮
        const helpBtn = this.qs('#btn-help');
        if (helpBtn) helpBtn.addEventListener('click', () => this.showFeatures());

        this.setupEasterEggs();

        await this.resolvePaths();
        await this.loadAll();
        this.startAutoRefresh();
        // v2.5: 加载完成后检查是否需要显示引导
        this.checkFirstRun();  // v3.0.1: 非阻塞，不 await
    }

    setBasePath(basePath) {
        this.basePath = basePath;
        this.stateDir = `${this.basePath}/webroot/state`;
        this.confFile = `${this.stateDir}/config.conf`;
        this.whitelistFile = `${this.stateDir}/whitelist.conf`;
        this.statusFile = `${this.stateDir}/boot_status`;
        this.historyFile = `${this.stateDir}/boot_history`;
        this.logFile = `${this.stateDir}/rescue.log`;
        this.watchdogPidFile = `${this.stateDir}/watchdog_pid`;
        this.snapshotDir = `${this.stateDir}/snapshots`;
        this.customDirsFile = `${this.stateDir}/custom_dirs.conf`;
        this.scriptRiskAlertFile = `${this.stateDir}/script_risk_alert.conf`;
    }

    async resolvePaths() {
        // v2.6.0 F-BUG-5 加固：
        //   1. 优先从 localStorage 读取上次解析结果，加速二次加载
        //   2. 探测管理器类型并相应调整默认路径（避免 KSU/APatch 用户静默被指向 Magisk）
        //   3. 解析全失败时输出 console.warn 与可见 toast，避免静默失败
        // v3.0.1 PERF: 如果有缓存路径，直接使用并后台验证，不阻塞 loadAll
        const cached = (() => {
            try { return localStorage.getItem('rescuex_base_path'); } catch (_) { return null; }
        })();
        if (cached && ALLOWED_BASES.some(b => cached === `${b}/${this.selfId}`)) {
            this.setBasePath(cached);
            // v3.0.1: 后台异步验证缓存路径，不阻塞 UI
            this._validatePathAsync(cached);
            return;
        }
        // 无缓存时同步解析（仅首次启动）
        await this._resolvePathsNow();
    }

    // 后台验证缓存路径是否仍然有效
    async _validatePathAsync(cachedPath) {
        const script = `[ -f "${cachedPath}/common.sh" ] && echo "1" || echo "0"`;
        try {
            const result = (await this.exec(script, 3000)).trim();
            if (result !== '1') {
                // 缓存失效，重新解析
                console.warn('[RescueX] cached path invalid, re-resolving');
                await this._resolvePathsNow();
            }
        } catch (e) {
            // 验证失败不影响已设置的路径
        }
    }

    // 同步解析路径（首次启动或缓存失效时）
    async _resolvePathsNow() {
        const candidates = ALLOWED_BASES.map(base => `${base}/${this.selfId}`);
        const script = `for d in ${candidates.join(' ')}; do
  [ -f "$d/common.sh" ] && { echo "$d"; exit 0; }
done`;
        let resolved = '';
        try {
            resolved = (await this.exec(script, 5000)).trim();
        } catch (e) {
            console.warn('[RescueX] resolvePaths exec failed:', e);
        }
        if (candidates.includes(resolved)) {
            this.setBasePath(resolved);
            try { localStorage.setItem('rescuex_base_path', resolved); } catch (_) {}
        } else {
            console.warn(`[RescueX] resolvePaths: no valid module path found in ${JSON.stringify(candidates)}, falling back to ${this.basePath}`);
            if (this.t) {
                try { this.toast(this.t('stats_unavailable'), 'warn'); } catch (_) {}
            }
        }
    }

    // === i18n ===
    t(key) {
        return (I18N[this.lang] && I18N[this.lang][key]) || key;
    }

    applyLang(lang) {
        this.lang = lang;
        localStorage.setItem('rescuex_lang', lang);
        document.documentElement.lang = lang === 'zh' ? 'zh-CN' : 'en';
        document.querySelectorAll('.lang-btn').forEach(b => b.classList.toggle('active', b.dataset.lang === lang));
        document.querySelectorAll('[data-i18n]').forEach(el => {
            const key = el.dataset.i18n;
            el.textContent = this.t(key);
        });
        this.setDefaultSubtitle();
    }

    async switchLang(lang) {
        if (lang === this.lang) return;
        this.recordLangEasterEgg();
        this.applyLang(lang);
        this.showLoading(true);
        try {
            const dashboardSnapshot = await this.getDashboardSnapshot({ force: true });
            await Promise.all([
                this.loadStatus({ snapshot: dashboardSnapshot }),
                this.loadModules(),
                this.loadDisabledModules(),
                this.loadSnapshots(),
                this.loadStats({ silent: true, snapshot: dashboardSnapshot }),
                this.loadAuditLog(),
                this.loadBootTrend(),
                this.loadScriptRiskAlert()
            ]);
        } finally {
            this.showLoading(false);
        }
    }

    showEnvError() {
        document.body.innerHTML = `
            <div class="container">
                <div class="env-error">
                    <h2>${this.t ? this.t('env_error_title') : '不兼容的环境'}</h2>
                    <p>${this.t ? this.t('env_error_desc') : '当前未运行在 KernelSU / APatch / Magisk v27+ WebUI 容器中。'}</p>
                    <p>${this.t ? this.t('env_error_solution') : '请在以下任意一个环境中打开本模块：'}</p>
                    <p style="margin-top:16px;">
                        • <strong>KernelSU 管理器</strong>（内置 WebUI）<br>
                        • <strong>Magisk v27+</strong>（内置 WebUI）<br>
                        • <strong>KsuWebUI</strong> / <strong>MMRL</strong> 应用
                    </p>
                </div>
            </div>
        `;
    }

    setDefaultSubtitle() {
        const el = this.qs('#app-subtitle');
        if (!el) return;
        el.classList.remove('easter-note');
        el.textContent = this.lang === 'zh' ? '自动救砖守护 v3.2.2' : 'Automatic Boot Rescue v3.2.2';
    }

    openExternal(url) {
        if (!url) return;
        try {
            if (typeof window.open === 'function') {
                const win = window.open(url, '_blank');
                if (win) return;
            }
        } catch (_) {}
        try {
            window.location.href = url;
        } catch (_) {
            this.copyText(url);
        }
    }

    openRepository() {
        this.openExternal('https://github.com/jiayuxuan123/RescueX');
    }

    openReleases() {
        this.openExternal('https://github.com/jiayuxuan123/RescueX/releases');
    }

    setupEasterEggs() {
        const logo = this.qs('.logo-icon');
        if (logo) {
            logo.addEventListener('click', () => {
                this._easterTapCount += 1;
                clearTimeout(this._easterTapTimer);
                this._easterTapTimer = setTimeout(() => {
                    this._easterTapCount = 0;
                }, 3200);
                if (this._easterTapCount >= 5) {
                    this._easterTapCount = 0;
                    this.triggerLogoEasterEgg();
                }
            });
        }
    }

    triggerLogoEasterEgg() {
        const logo = this.qs('.logo-icon');
        const subtitle = this.qs('#app-subtitle');
        if (logo) {
            logo.classList.remove('easter-glow');
            void logo.offsetWidth;
            logo.classList.add('easter-glow');
            setTimeout(() => logo.classList.remove('easter-glow'), 1400);
        }
        if (subtitle) {
            clearTimeout(this._easterSubtitleTimer);
            subtitle.classList.add('easter-note');
            subtitle.textContent = this.lang === 'zh' ? '本次启动，先保平安。' : 'Keep this boot clean.';
            this._easterSubtitleTimer = setTimeout(() => this.setDefaultSubtitle(), 12000);
        }
        this.toast(this.lang === 'zh' ? '隐藏巡检模式已点亮' : 'Hidden inspection mode enabled', 'success', 2500);
    }

    recordLangEasterEgg() {
        const now = Date.now();
        this._easterLangHits = this._easterLangHits.filter(ts => now - ts < 4500);
        this._easterLangHits.push(now);
        if (this._easterLangHits.length >= 4) {
            this._easterLangHits = [];
            this.toast(this.lang === 'zh' ? '双语巡检完成' : 'Bilingual check complete', '', 2200);
        }
    }

    // === 桥接执行（统一 KSU / Magisk v27）===
    exec(cmd, timeoutMs = EXEC_DEFAULT_TIMEOUT_MS) {
        return new Promise(resolve => {
            const cb = `_rx_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
            let done = false;
            const timer = setTimeout(() => {
                if (done) return;
                done = true;
                delete window[cb];
                resolve('');
            }, timeoutMs);
            window[cb] = (code, out) => {
                if (done) return;
                done = true;
                clearTimeout(timer);
                delete window[cb];
                resolve((out || '').trim());
            };
            try {
                // KSU: ksu.exec(cmd, "{}", cb)  Magisk: magisk.exec(cmd, cb)
                if (this.isKsu) {
                    this.bridge.exec(cmd, '{}', cb);
                } else {
                    this.bridge.exec(cmd, cb);
                }
            } catch (e) {
                if (done) return;
                done = true;
                clearTimeout(timer);
                delete window[cb];
                resolve('');
            }
        });
    }

    qs(s) { return document.querySelector(s); }
    setText(s, t) { const e = this.qs(s); if (e) e.textContent = t; }
    setVal(s, v) { const e = this.qs(s); if (e) e.value = v; }
    setChecked(s, v) { const e = this.qs(s); if (e) e.checked = v; }

    showLoading(yes) {
        const bar = this.qs('#loading-bar');
        if (bar) bar.classList.toggle('show', yes);
        this.isLoading = yes;
    }

    toast(msg, type = '', duration) {
        const t = this.qs('#toast');
        t.textContent = msg;
        t.className = `toast show ${type}`;
        const dur = duration || (type === 'error' ? 5000 : (type === 'warn' ? 3500 : 2500));
        clearTimeout(this._toastTimer);
        this._toastTimer = setTimeout(() => { t.className = 'toast'; }, dur);
    }

    clampInput(el) {
        const min = parseInt(el.min);
        const max = parseInt(el.max);
        let v = parseInt(el.value) || min;
        v = Math.max(min, Math.min(max, v));
        el.value = v;
    }

    parseKV(raw) {
        const obj = {};
        if (!raw) return obj;
        raw.split('\n').forEach(line => {
            const idx = line.indexOf('=');
            if (idx <= 0) return;
            const k = line.slice(0, idx).trim();
            const v = line.slice(idx + 1).trim();
            if (k) obj[k] = v;
        });
        return obj;
    }

    escapeHtml(s) {
        return String(s).replace(/[&<>"']/g, c => ({
            '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
        })[c]);
    }

    getSafeCustomDirPrefixes() {
        return [
            '/data/adb/rescuex_data',
            `${this.stateDir}`,
            `${this.snapshotDir}`,
            '/data/local/tmp/RescueX'
        ].map(p => p.replace(/\/+$/, ''));
    }

    normalizeCustomDirPath(path) {
        return String(path || '').trim().replace(/\/+$/, '');
    }

    isSafeCustomDirPath(path) {
        const normalized = this.normalizeCustomDirPath(path);
        if (!normalized.startsWith('/')) return false;
        if (!normalized || /\s/.test(normalized) || normalized.includes('..')) return false;
        if (/[*?\[\]]/.test(normalized)) return false;
        return this.getSafeCustomDirPrefixes().some(prefix => normalized === prefix || normalized.startsWith(`${prefix}/`));
    }

    renderReadiness() {
        const list = this.qs('#readiness-list');
        const scoreEl = this.qs('#readiness-score');
        if (!list || !scoreEl) return;

        const status = this.lastStatus || {};
        const goodStats = this.goodModuleStats || { enabled: 0, total: 0 };
        const entries = this._customDirs || [];
        const unsafeCount = entries.filter(item => item && item.valid === false).length;
        const result = status.result || 'UNKNOWN';
        const failCount = status.failCount || 0;
        const threshold = parseInt(this.config.REBOOT_THRESHOLD || '3', 10) || 3;
        const enabled = this.config.ENABLED !== 'false';
        const dryRun = this.config.DRY_RUN === 'true';

        let score = 100;
        const items = [];
        const pushItem = (type, titleKey, descKey) => {
            items.push({ type, title: this.t(titleKey), desc: this.t(descKey) });
        };

        if (goodStats.total > 0) {
            pushItem('ok', 'readiness_item_baseline_ok_title', 'readiness_item_baseline_ok_desc');
        } else {
            score -= 30;
            pushItem('danger', 'readiness_item_baseline_missing_title', 'readiness_item_baseline_missing_desc');
        }

        if (enabled) {
            if (dryRun) {
                score -= 10;
                pushItem('warn', 'readiness_item_dry_title', 'readiness_item_dry_desc');
            } else {
                pushItem('ok', 'readiness_item_mode_ok_title', 'readiness_item_mode_ok_desc');
            }
        } else {
            score -= 45;
            pushItem('danger', 'readiness_item_disabled_title', 'readiness_item_disabled_desc');
        }

        if (unsafeCount > 0) {
            score -= 25;
            pushItem('danger', 'readiness_item_policy_risky_title', 'readiness_item_policy_risky_desc');
        } else {
            pushItem('ok', 'readiness_item_policy_ok_title', 'readiness_item_policy_ok_desc');
        }

        if (this.scriptRiskAlert && this.scriptRiskAlert.DETECTED === '1') {
            score -= 35;
            items.unshift({
                type: 'danger',
                title: this.t('script_risk_title'),
                desc: this.t('script_risk_desc')
            });
        }

        if (failCount >= Math.max(1, threshold - 1)) {
            score -= 20;
            pushItem('warn', 'readiness_item_fail_warn_title', 'readiness_item_fail_warn_desc');
        }

        if (this.rescueLevel > 0) {
            score -= 10 + (this.rescueLevel * 5);
            pushItem('warn', 'readiness_item_level_warn_title', 'readiness_item_level_warn_desc');
        }

        if (result === 'BOOTING' && !status.watchdogAlive) {
            score -= 15;
            pushItem('warn', 'readiness_item_watchdog_warn_title', 'readiness_item_watchdog_warn_desc');
        }

        score = Math.max(0, Math.min(100, score));
        const scoreLabel = score >= 85 ? this.t('readiness_score_good') : (score >= 60 ? this.t('readiness_score_warn') : this.t('readiness_score_danger'));
        scoreEl.textContent = `${score} ${scoreLabel}`;
        scoreEl.className = `badge ${score >= 85 ? 'badge-ok' : (score >= 60 ? 'badge-warn' : 'badge-err')}`;

        this.setText('#readiness-baseline', goodStats.total > 0 ? `${this.t('readiness_baseline_ready')} (${goodStats.enabled}/${goodStats.total})` : this.t('readiness_baseline_missing'));
        this.setText('#readiness-policy', unsafeCount > 0 ? `${this.t('readiness_policy_risky')} (${unsafeCount})` : this.t('readiness_policy_clean'));
        this.setText('#readiness-mode', enabled ? (dryRun ? this.t('readiness_mode_dry') : this.t('readiness_mode_active')) : this.t('badge_disabled'));
        this.setText('#readiness-level', this.t(`rescue_level_${Math.min(2, Math.max(0, this.rescueLevel))}`));

        list.innerHTML = items.map(item => `
            <div class="readiness-item ${item.type}">
                <div>
                    <strong>${this.escapeHtml(item.title)}</strong>
                    <span>${this.escapeHtml(item.desc)}</span>
                </div>
            </div>
        `).join('');
    }

    isSafeSnapshotPath(path) {
        if (!path || !path.startsWith(`${this.snapshotDir}/snap-`) || !path.endsWith('.txt')) return false;
        const name = path.slice(this.snapshotDir.length + 1);
        return /^snap-[A-Za-z0-9._-]+\.txt$/.test(name);
    }

    // === 加载 ===
    async loadAll() {
        this.showLoading(true);
        document.body.classList.add('app-loading');
        try {
            await this.loadConfig();
            const dashboardSnapshot = await this.getDashboardSnapshot({ force: true });
            // v3.0.1 PERF: 并行加载所有面板数据（10个并发请求）
            await Promise.all([
                this.loadStatus({ snapshot: dashboardSnapshot }),
                this.loadWhitelist(),
                this.loadModules(),
                this.loadDisabledModules(),
                this.loadSnapshots(),
                this.loadStats({ snapshot: dashboardSnapshot }),
                this.loadAuditLog(),
                this.loadCustomDirs(),
                this.loadSuspectModules(),
                this.loadRescueLevel(),
                this.loadScriptRiskAlert()
            ]);
            // v3.0.1 PERF: 日志、历史、趋势图、管理器检测也并行
            await Promise.all([
                this.loadLog(),
                this.loadHistory(),
                this.loadBootTrend(),
                this.detectManager()
            ]);
            this.renderReadiness();
        } catch (e) {
            this.toast(this.t('loading_failed'), 'error');
        } finally {
            document.body.classList.remove('app-loading');
            this.showLoading(false);
        }
    }

    scriptRiskReasonLabel(reason) {
        const map = {
            'rm-rf-sensitive-path': this.t('script_risk_reason_rm_rf'),
            'find-delete-sensitive-path': this.t('script_risk_reason_find_delete'),
            'format-command': this.t('script_risk_reason_format'),
            'raw-block-write': this.t('script_risk_reason_dd'),
            'wipe-or-format-invocation': this.t('script_risk_reason_wipe')
        };
        return map[String(reason || '').trim()] || (reason || '--');
    }

    scriptRiskActionLabel(action) {
        const map = {
            'module-disabled': this.t('script_risk_action_module_disabled'),
            'script-blocked': this.t('script_risk_action_script_blocked')
        };
        return map[String(action || '').trim()] || (action || '--');
    }

    async loadScriptRiskAlert() {
        try {
            const raw = await this.exec(`cat "${this.scriptRiskAlertFile}" 2>/dev/null`);
            if (!raw || !raw.includes('DETECTED=')) {
                this.scriptRiskAlert = null;
                this.renderScriptRiskAlert();
                this.renderReadiness();
                return;
            }
            this.scriptRiskAlert = this.parseKV(raw);
            this.renderScriptRiskAlert();
            this.renderReadiness();
        } catch (e) {
            this.scriptRiskAlert = null;
            this.renderScriptRiskAlert();
            this.renderReadiness();
        }
    }

    renderScriptRiskAlert() {
        const card = this.qs('#script-risk-card');
        if (!card) return;
        const alert = this.scriptRiskAlert;
        if (!alert || alert.DETECTED !== '1') {
            card.classList.add('hidden');
            return;
        }
        card.classList.remove('hidden');
        this.setText('#script-risk-module', alert.MODULE_ID || '--');
        this.setText('#script-risk-reason', this.scriptRiskReasonLabel(alert.REASON));
        this.setText('#script-risk-action', this.scriptRiskActionLabel(alert.ACTION));
        this.setText('#script-risk-time', alert.DETECTED_AT ? this.formatTimeValue(alert.DETECTED_AT) : '--');
        this.setText('#script-risk-path', alert.SCRIPT_PATH || '--');

        const seenKey = `rescuex_seen_risk_${alert.DETECTED_AT || '0'}_${alert.MODULE_ID || 'unknown'}`;
        try {
            if (!localStorage.getItem(seenKey)) {
                localStorage.setItem(seenKey, '1');
                this.toast(this.t('script_risk_toast'), 'error', 5000);
            }
        } catch (_) {}
    }

    formatTimeValue(value) {
        const text = String(value || '').trim();
        if (/^[0-9]+$/.test(text)) {
            return this.formatTime(parseInt(text, 10));
        }
        return text || '--';
    }

    async loadConfig() {
        try {
            const raw = await this.exec(`cat "${this.confFile}" 2>/dev/null`);
            const cfg = this.parseKV(raw);
            this.config = cfg;
            this.setChecked('#cfg-enabled', cfg.ENABLED !== 'false');
            this.setVal('#cfg-threshold', cfg.REBOOT_THRESHOLD || 3);
            this.setVal('#cfg-timeout', cfg.BOOT_TIMEOUT_SEC || 90);
            this.setVal('#cfg-ota-timeout', cfg.OTA_TIMEOUT_SEC || 900);
            this.setVal('#cfg-grace', cfg.USER_REBOOT_GRACE_SEC || 30);
            this.setChecked('#cfg-log', cfg.LOG_ENABLED !== 'false');
            this.setChecked('#cfg-progressive', cfg.PROGRESSIVE_RESCUE !== 'false');
            this.setChecked('#cfg-auto-reenable', cfg.AUTO_REENABLE === 'true');
            this.setChecked('#cfg-dry-run', cfg.DRY_RUN === 'true');
            // v2.4: 补丁更新配置
            this.setVal('#cfg-patch-timeout', cfg.PATCH_UPDATE_TIMEOUT_SEC || 180);
            this.setVal('#cfg-patch-fail-threshold', cfg.PATCH_FAIL_THRESHOLD || 2);
            this.setChecked('#cfg-patch-auto-rollback', cfg.PATCH_AUTO_ROLLBACK !== 'false');
            // v2.5: 看门狗轮询间隔
            this.setVal('#cfg-watchdog-poll', cfg.WATCHDOG_POLL_INTERVAL_SEC || 2);
        } catch (e) {
            this.setDefaults();
        }
    }

    setDefaults() {
        this.config = {
            ENABLED: 'true', REBOOT_THRESHOLD: '3',
            BOOT_TIMEOUT_SEC: '90', OTA_TIMEOUT_SEC: '900',
            LOG_ENABLED: 'true', USER_REBOOT_GRACE_SEC: '30',
            PROGRESSIVE_RESCUE: 'true', AUTO_REENABLE: 'false', DRY_RUN: 'false'
        };
        this.setChecked('#cfg-enabled', true);
        this.setVal('#cfg-threshold', 3);
        this.setVal('#cfg-timeout', 90);
        this.setVal('#cfg-ota-timeout', 900);
        this.setVal('#cfg-grace', 30);
        this.setChecked('#cfg-log', true);
        this.setChecked('#cfg-progressive', true);
        this.setChecked('#cfg-auto-reenable', false);
        this.setChecked('#cfg-dry-run', false);
        this.setVal('#cfg-watchdog-poll', 2);
    }

    async getDashboardSnapshot(options = {}) {
        const force = !!options.force;
        const now = Date.now();
        if (!force && this.dashboardSnapshot && (now - this.dashboardSnapshotFetchedAt) < 1500) {
            return this.dashboardSnapshot;
        }
        if (!force && this.dashboardSnapshotPromise) {
            return this.dashboardSnapshotPromise;
        }
        const script = `MODDIR="${this.basePath}"; . "${this.basePath}/common.sh" 2>/dev/null
get_dashboard_snapshot`;
        this.dashboardSnapshotPromise = (async () => {
            const raw = await this.exec(script, EXEC_DEFAULT_TIMEOUT_MS);
            const parsed = this.parseKV(raw || '');
            this.dashboardSnapshot = parsed;
            this.dashboardSnapshotFetchedAt = Date.now();
            return parsed;
        })();
        try {
            return await this.dashboardSnapshotPromise;
        } finally {
            this.dashboardSnapshotPromise = null;
        }
    }

    async loadStatus(options = {}) {
        try {
            const snap = options.snapshot || await this.getDashboardSnapshot({ force: !!options.force });
            const s = snap;
            const extra = snap;
            const stats = snap;

            const result = s.LAST_BOOT_RESULT || 'UNKNOWN';
            const badge = this.qs('#status-badge');
            const heroStatus = this.qs('#hero-status');
            const heroMeta = this.qs('#hero-meta');

            const statusMap = {
                'SUCCESS': { text: 'badge_ok', cls: 'badge-ok', hero: 'status_ok', meta: 'status_ok_meta' },
                'RESCUED': { text: 'badge_rescued', cls: 'badge-warn', hero: 'status_rescued', meta: 'status_rescued_meta' },
                'BOOTING': { text: 'badge_booting', cls: 'badge-info', hero: 'status_booting', meta: 'status_booting_meta' },
                'MODULE_DISABLED': { text: 'badge_disabled', cls: 'badge-err', hero: 'status_disabled', meta: 'status_disabled_meta' },
                'INIT': { text: 'badge_init', cls: 'badge-info', hero: 'status_init', meta: 'status_init_meta' },
                'UNKNOWN': { text: 'badge_unknown', cls: 'badge-info', hero: 'status_unknown', meta: 'status_unknown_meta' }
            };
            const m = statusMap[result] || statusMap['UNKNOWN'];
            badge.textContent = this.t(m.text);
            badge.className = `badge ${m.cls}`;
            heroStatus.textContent = this.t(m.hero);
            heroMeta.textContent = this.t(m.meta);

            this.setText('#info-last-result', result);
            const failCount = parseInt(s.FAIL_COUNT) || 0;
            this.setText('#info-fail-count', failCount);
            this.setText('#info-ota', s.OTA_DETECTED === 'true' ? (this.lang === 'zh' ? '是' : 'YES') : (this.lang === 'zh' ? '否' : 'NO'));

            // 补丁更新状态（从合并命令结果中读取，无需额外 exec）
            const patchEl = this.qs('#info-patch');
            if (patchEl) {
                const patchDetected = s.PATCH_DETECTED === 'true' || extra.PATCH_FLAG === '1';
                patchEl.textContent = patchDetected ? (this.lang === 'zh' ? '是' : 'YES') : (this.lang === 'zh' ? '否' : 'NO');
                patchEl.className = 'value' + (patchDetected ? ' warn' : '');
            }
            const patchFailEl = this.qs('#info-patch-fail');
            if (patchFailEl) {
                const pfcNum = parseInt(extra.PATCH_FAIL_COUNT) || 0;
                patchFailEl.textContent = pfcNum;
                patchFailEl.className = 'value' + (pfcNum > 0 ? ' warn' : '');
            }

            const start = parseInt(s.BOOT_START) || 0;
            const end = parseInt(s.BOOT_END) || 0;
            const uptimeStart = parseInt(s.UPTIME_START) || 0;
            const uptimeEnd = parseInt(s.UPTIME_END) || 0;
            const duration = parseInt(s.BOOT_DURATION) || 0;
            const sec = this.t('seconds');
            if (duration > 0 && duration <= 3600) {
                this.setText('#info-boot-duration', `${duration}${sec}`);
            } else if (uptimeStart > 0 && uptimeEnd > 0 && uptimeEnd >= uptimeStart) {
                const upDur = uptimeEnd - uptimeStart;
                if (upDur >= 5 && upDur <= 3600) this.setText('#info-boot-duration', `${upDur}${sec}`);
                else this.setText('#info-boot-duration', this.t('boot_error'));
            } else if (start > 0 && end > 0 && end > start && (end - start) <= 3600) {
                this.setText('#info-boot-duration', `${end - start}${sec}`);
            } else if (start > 0 && end > 0) {
                this.setText('#info-boot-duration', this.t('clock_unsync'));
            } else {
                this.setText('#info-boot-duration', '--');
            }

            const rescueCount = parseInt(stats.RESCUED) || parseInt(s.RESCUE_COUNT) || 0;
            this.setText('#info-rescue-count', rescueCount);

            // 看门狗状态（从合并命令结果中读取，无需额外 exec）
            const wdPid = extra.WD_PID || '';
            const wdStatus = extra.WD_STATUS || 'nopid';
            if (wdPid && /^\d+$/.test(wdPid.trim()) && wdStatus === 'alive_ours') {
                this.setText('#info-watchdog', `${this.t('wd_running')} (PID ${wdPid.trim()})`);
            } else {
                this.setText('#info-watchdog', this.t('wd_idle'));
            }

            // 失败进度
            const threshold = parseInt(this.config.REBOOT_THRESHOLD) || 3;
            const pct = Math.min(100, (failCount / threshold) * 100);
            const fill = this.qs('#progress-fill');
            fill.style.width = `${pct}%`;
            fill.classList.toggle('danger', failCount >= threshold - 1);
            this.setText('#progress-text', `${failCount} / ${threshold}`);

            const failEl = this.qs('#info-fail-count');
            failEl.className = 'value' + (failCount >= threshold ? ' danger' : (failCount > 0 ? ' warn' : ' ok'));

            this.lastStatus = {
                result,
                failCount,
                watchdogAlive: wdStatus === 'alive_ours',
                patchDetected: s.PATCH_DETECTED === 'true' || extra.PATCH_FLAG === '1'
            };
            this.renderReadiness();
        } catch (e) {
            console.error('loadStatus failed:', e);
        }
    }

    async loadWhitelist() {
        // 白名单从 config 加载，模块选择器加载时勾选
    }

    // === 模块选择器 ===
    async loadModules() {
        try {
            // 读取白名单
            const wlRaw = await this.exec(`cat "${this.whitelistFile}" 2>/dev/null`);
            const wlSet = new Set();
            wlRaw.split('\n').forEach(line => {
                const l = line.replace(/#.*$/, '').trim();
                if (l && MODULE_ID_RE.test(l)) wlSet.add(l);
            });

            // 扫描已装模块（用 shell 批量输出，减少 RPC）
            const script = `for base in ${this.moduleBases.join(' ')}; do
  [ -d "\$base" ] || continue
  case "\$base" in *ksu*) mgr="KSU";; *ap*) mgr="APatch";; *) mgr="Magisk";; esac
  for d in "\$base"/*/; do
    [ -d "\$d" ] || continue
    m=\$(basename "\$d")
    [ "\$m" = "${this.selfId}" ] && continue
    [ -f "\$d/remove" ] && continue
    en="1"; [ -f "\$d/disable" ] && en="0"
    echo "\${m}|\${en}|\${mgr}"
  done
done`;
            const out = await this.exec(script);
            const modules = [];
            out.split('\n').forEach(line => {
                const parts = line.split('|');
                if (parts.length === 3 && MODULE_ID_RE.test(parts[0])) {
                    modules.push({ id: parts[0], enabled: parts[1] === '1', manager: parts[2], whitelisted: wlSet.has(parts[0]) });
                }
            });
            this.modulesCache = modules;
            this.renderModuleList(modules, wlSet);
        } catch (e) {
            this.qs('#module-list').innerHTML = `<div class="empty-state">${this.t('loading')}</div>`;
        }
    }

    renderModuleList(modules, wlSet) {
        const container = this.qs('#module-list');
        if (!modules || modules.length === 0) {
            container.innerHTML = `<div class="empty-state">${this.t('mod_no_modules')}</div>`;
            return;
        }
        // 全选/取消全选按钮
        let html = `
            <div class="section-actions" style="margin:0 0 8px;padding:0 4px;">
                <button class="btn btn-text btn-sm" data-action="selectAllModules">${this.t('select_all')}</button>
                <button class="btn btn-text btn-sm" data-action="deselectAllModules">${this.t('deselect_all')}</button>
            </div>`;
        const t = this.t.bind(this);
        modules.forEach(m => {
            const checked = wlSet.has(m.id) ? 'checked' : '';
            const ena = m.enabled ? '1' : '0';
            const tag = m.enabled ? `<span class="module-tag enabled">${this.t('mod_enabled')}</span>` : `<span class="module-tag disabled">${this.t('mod_disabled')}</span>`;
            const mgrTag = `<span class="module-tag manager">${m.manager}</span>`;
            html += `
                <label class="module-item">
                    <input type="checkbox" class="module-checkbox" data-mod-id="${this.escapeHtml(m.id)}" ${checked}>
                    <div class="module-info">
                        <div class="name">${this.escapeHtml(m.id)}</div>
                        <div class="meta">${mgrTag} ${tag}</div>
                    </div>
                    <button class="btn btn-text btn-sm mod-toggle" data-mod-id="${this.escapeHtml(m.id)}" data-mod-enabled="${ena}">${ena === '1' ? t('toggle_disable') : t('toggle_enable')}</button>
                </label>`;
        });
        container.innerHTML = html;
    }

    selectAllModules() {
        document.querySelectorAll('.module-checkbox').forEach(cb => cb.checked = true);
    }

    deselectAllModules() {
        document.querySelectorAll('.module-checkbox').forEach(cb => cb.checked = false);
    }

    async refreshModules() {
        this.showLoading(true);
        await this.loadModules();
        this.showLoading(false);
        this.toast(this.t('refreshed'), 'success');
    }

    async saveWhitelist() {
        const checked = [];
        document.querySelectorAll('.module-checkbox:checked').forEach(cb => {
            const id = cb.dataset.modId;
            if (id && MODULE_ID_RE.test(id)) checked.push(id);
        });
        const content = '# RescueX 白名单 - 自动生成\n' + checked.join('\n') + '\n';
        try {
            const b64 = utf8ToBase64(content);
            if (!/^[A-Za-z0-9+/=]*$/.test(b64)) {
                this.toast(this.t('invalid_config'), 'error');
                return;
            }
            const result = await this.exec(`printf '%s' '${b64}' | base64 -d > "${this.whitelistFile}" && echo OK`);
            if (result.includes('OK')) {
                await this.loadModules();
                this.toast(this.t('saved'), 'success');
            } else {
                // v2.6.0 F-BUG-4 加固：错误路径也尝试 loadModules，
                //   避免保存失败后 DOM 与文件状态脱节（例如部分写入场景）
                try { await this.loadModules(); } catch (_) {}
                this.toast(this.t('save_failed'), 'error');
            }
        } catch (e) {
            // v2.6.0 F-BUG-4：异常路径同样尝试刷新
            try { await this.loadModules(); } catch (_) {}
            this.toast(this.t('save_failed'), 'error');
        }
    }

    // === 已禁用模块列表 ===
    async loadDisabledModules() {
        try {
            const script = `for base in ${this.moduleBases.join(' ')}; do
  [ -d "\$base" ] || continue
  for d in "\$base"/*/; do
    [ -d "\$d" ] || continue
    m=\$(basename "\$d")
    [ "\$m" = "${this.selfId}" ] && continue
    [ -f "\$d/disable" ] && echo "\$m"
  done
done`;
            const out = await this.exec(script);
            const container = this.qs('#disabled-list');
            const modules = out.split('\n').filter(m => m && MODULE_ID_RE.test(m));
            if (modules.length === 0) {
                container.innerHTML = `<div class="empty-state">${this.t('mod_no_disabled')}</div>`;
                return;
            }
            let html = '';
            modules.forEach(m => {
                html += `
                    <div class="module-item">
                        <div class="module-info">
                            <div class="name">${this.escapeHtml(m)}</div>
                        </div>
                        <span class="module-tag disabled">${this.t('mod_disabled')}</span>
                    </div>`;
            });
            container.innerHTML = html;
        } catch (e) {
            this.qs('#disabled-list').innerHTML = `<div class="empty-state">${this.t('loading')}</div>`;
        }
    }

    // === 快照管理 ===
    async loadSnapshots() {
        try {
            const out = await this.exec(`MODDIR="${this.basePath}"; . "${this.basePath}/common.sh" 2>/dev/null && list_snapshots`);
            const container = this.qs('#snapshot-list');
            const snaps = out.split('\n').filter(s => s);
            if (snaps.length === 0) {
                container.innerHTML = `<div class="empty-state">${this.t('no_snapshots')}</div>`;
                return;
            }
            let html = '';
            snaps.forEach(s => {
                const name = s.split('/').pop();
                html += `
                    <div class="module-item">
                        <div class="module-info">
                            <div class="name">${this.escapeHtml(name)}</div>
                        </div>
                        <button class="btn btn-tonal btn-sm" data-action="restoreSnapshot" data-snap="${this.escapeHtml(s)}">${this.lang === 'zh' ? '恢复' : 'Restore'}</button>
                        <button class="btn btn-text btn-sm" data-action="deleteSnapshot" data-snap="${this.escapeHtml(s)}" style="color:var(--md-error)">${this.lang === 'zh' ? '删除' : 'Delete'}</button>
                    </div>`;
            });
            container.innerHTML = html;
        } catch (e) {
            this.qs('#snapshot-list').innerHTML = `<div class="empty-state">${this.t('no_snapshots')}</div>`;
        }
    }

    async takeSnapshot() {
        try {
            const result = await this.exec(`MODDIR="${this.basePath}"; . "${this.basePath}/common.sh" 2>/dev/null && manual_take_snapshot manual`);
            if (result.trim()) {
                this.toast(this.t('snapshot_taken'), 'success');
                this.loadSnapshots();
            } else {
                this.toast(this.t('snapshot_failed'), 'error');
            }
        } catch (e) {
            this.toast(this.t('snapshot_failed'), 'error');
        }
    }

    async restoreSnapshot(e) {
        const snapFile = e.target.dataset.snap;
        if (!this.isSafeSnapshotPath(snapFile)) return;
        const confirm = await this.confirmDialog(
            this.t('confirm_title'),
            this.lang === 'zh' ? '将恢复到该快照记录的模块状态，重启后生效。是否继续？' : 'Restore module states from this snapshot. Effective after reboot. Continue?',
            this.t('btn_confirm'), 'btn-filled'
        );
        if (!confirm) return;
        try {
            const result = await this.exec(`MODDIR="${this.basePath}"; . "${this.basePath}/common.sh" 2>/dev/null && manual_restore_snapshot "${snapFile}"`);
            if (result.includes('OK')) {
                this.toast(this.t('snapshot_restored'), 'success');
                await Promise.all([this.loadDisabledModules(), this.loadSuspectModules()]);
            } else {
                this.toast(this.t('snapshot_failed'), 'error');
            }
        } catch (e) {
            this.toast(this.t('snapshot_failed'), 'error');
        }
    }

    async deleteSnapshot(e) {
        const snapFile = e.target.dataset.snap;
        if (!this.isSafeSnapshotPath(snapFile)) return;
        const confirm = await this.confirmDialog(
            this.t('confirm_title'),
            this.t('confirm_clear'),
            this.t('btn_confirm'), 'btn-danger'
        );
        if (!confirm) return;
        try {
            await this.exec(`MODDIR="${this.basePath}"; . "${this.basePath}/common.sh" 2>/dev/null && manual_delete_snapshot "${snapFile}"`);
            this.toast(this.t('snapshot_deleted'), 'success');
            this.loadSnapshots();
        } catch (e) {
            this.toast(this.t('snapshot_failed'), 'error');
        }
    }

    async restoreBaseline() {
        const confirm = await this.confirmDialog(
            this.t('confirm_title'),
            this.t('confirm_restore_baseline'),
            this.t('btn_confirm'), 'btn-filled'
        );
        if (!confirm) return;
        try {
            const result = await this.exec(`MODDIR="${this.basePath}"; . "${this.basePath}/common.sh" 2>/dev/null && manual_restore_good_modules_baseline`);
            if (result.includes('CHANGED=')) {
                this.toast(this.t('baseline_restored'), 'success');
                await Promise.all([this.loadDisabledModules(), this.loadSuspectModules(), this.loadRescueLevel()]);
            } else {
                this.toast(this.t('snapshot_failed'), 'error');
            }
        } catch (e) {
            this.toast(this.t('snapshot_failed'), 'error');
        }
    }

    async clearScriptRiskAlert() {
        try {
            const result = await this.exec(`MODDIR="${this.basePath}"; . "${this.basePath}/common.sh" 2>/dev/null && manual_clear_script_risk_alert`);
            if (!/ALERT_CLEARED=1|ALERT_ALREADY_CLEAR=1/.test(result)) {
                this.toast(this.t('save_failed'), 'error');
                return;
            }
            this.scriptRiskAlert = null;
            this.renderScriptRiskAlert();
            this.renderReadiness();
            this.toast(this.t('script_risk_cleared'), 'success');
        } catch (e) {
            this.toast(this.t('save_failed'), 'error');
        }
    }

    // === 配置操作 ===
    toggleEnabled(e) {
        this.config.ENABLED = e.target.checked ? 'true' : 'false';
    }

    async saveConfig() {
        const threshold = parseInt(this.qs('#cfg-threshold').value) || 3;
        const timeout = parseInt(this.qs('#cfg-timeout').value) || 90;
        const otaTimeout = parseInt(this.qs('#cfg-ota-timeout').value) || 900;
        const grace = parseInt(this.qs('#cfg-grace').value) || 30;
        const enabled = this.qs('#cfg-enabled').checked ? 'true' : 'false';
        const log = this.qs('#cfg-log').checked ? 'true' : 'false';
        const progressive = this.qs('#cfg-progressive').checked ? 'true' : 'false';
        const autoReenable = this.qs('#cfg-auto-reenable').checked ? 'true' : 'false';
        const dryRun = this.qs('#cfg-dry-run').checked ? 'true' : 'false';
        // v2.4: 补丁更新配置
        const patchTimeout = parseInt(this.qs('#cfg-patch-timeout') ? this.qs('#cfg-patch-timeout').value : 180) || 180;
        const patchFailThreshold = parseInt(this.qs('#cfg-patch-fail-threshold') ? this.qs('#cfg-patch-fail-threshold').value : 2) || 2;
        const patchAutoRollback = this.qs('#cfg-patch-auto-rollback') ? this.qs('#cfg-patch-auto-rollback').checked : true;
        // v2.5: 看门狗轮询间隔
        const watchdogPollRaw = this.qs('#cfg-watchdog-poll') ? this.qs('#cfg-watchdog-poll').value : '2';
        const watchdogPoll = parseInt(watchdogPollRaw) || 2;

        const t = Math.max(1, Math.min(10, threshold));
        const to = Math.max(30, Math.min(600, timeout));
        const ota = Math.max(60, Math.min(1800, otaTimeout));
        const gr = Math.max(5, Math.min(300, grace));
        const pt = Math.max(60, Math.min(600, patchTimeout));
        const pft = Math.max(1, Math.min(5, patchFailThreshold));
        const wp = Math.max(1, Math.min(10, watchdogPoll));

        const lines = [
            `REBOOT_THRESHOLD=${t}`,
            `BOOT_TIMEOUT_SEC=${to}`,
            `OTA_TIMEOUT_SEC=${ota}`,
            `ENABLED=${enabled}`,
            `LOG_ENABLED=${log}`,
            `DRY_RUN=${dryRun}`,
            `PROGRESSIVE_RESCUE=${progressive}`,
            `AUTO_REENABLE=${autoReenable}`,
            `USER_REBOOT_GRACE_SEC=${gr}`,
            `PATCH_UPDATE_TIMEOUT_SEC=${pt}`,
            `PATCH_FAIL_THRESHOLD=${pft}`,
            `PATCH_AUTO_ROLLBACK=${patchAutoRollback ? 'true' : 'false'}`,
            `WATCHDOG_POLL_INTERVAL_SEC=${wp}`,
            ''
        ];
        try {
            // LOG-006: Atomic write (tmp + sync + mv) to prevent config corruption on power loss
            const cmd = `cd "${this.stateDir}" && {
cat > config.conf.tmp.$$ << 'RXCONF'
${lines.join('\n')}
RXCONF
sync config.conf.tmp.$$ 2>/dev/null
mv config.conf.tmp.$$ config.conf
} && echo OK`;
            const result = await this.exec(cmd);
            if (result.includes('OK')) {
                this.config = {
                    ENABLED: enabled, REBOOT_THRESHOLD: String(t),
                    BOOT_TIMEOUT_SEC: String(to), OTA_TIMEOUT_SEC: String(ota),
                    LOG_ENABLED: log, DRY_RUN: dryRun,
                    PROGRESSIVE_RESCUE: progressive, AUTO_REENABLE: autoReenable,
                    USER_REBOOT_GRACE_SEC: String(gr),
                    PATCH_UPDATE_TIMEOUT_SEC: String(pt),
                    PATCH_FAIL_THRESHOLD: String(pft),
                    PATCH_AUTO_ROLLBACK: patchAutoRollback ? 'true' : 'false',
                    WATCHDOG_POLL_INTERVAL_SEC: String(wp)
                };
                this.toast(this.t('saved'), 'success');
            } else {
                this.toast(this.t('save_failed'), 'error');
            }
        } catch (e) {
            this.toast(this.t('save_failed') + ': ' + (e.message || ''), 'error');
        }
    }

    // === 配置导入/导出 ===
    async exportConfig() {
        // v2.4: WebUI 容器不支持 Blob 下载，改用 shell 写入 /sdcard/Download + am start 分享
        try {
            const configRaw = await this.exec(`cat "${this.confFile}" 2>/dev/null`);
            const whitelistRaw = await this.exec(`cat "${this.whitelistFile}" 2>/dev/null`);
            const data = {
                version: '3.2.0',
                exported_at: new Date().toISOString(),
                config: this.parseKV(configRaw),
                whitelist: whitelistRaw
            };
            const json = JSON.stringify(data, null, 2);
            const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
            const filepath = `/sdcard/Download/rescuex-config-${ts}.json`;
            const b64 = utf8ToBase64(json);
            if (!/^[A-Za-z0-9+/=]*$/.test(b64)) {
                this.toast(this.t('export_failed'), 'error');
                return;
            }
            const result = await this.exec(`mkdir -p /sdcard/Download && printf '%s' '${b64}' | base64 -d > '${filepath}' && echo OK`);
            if (result.includes('OK')) {
                await this.exec(`am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file://'${filepath}' 2>/dev/null`);
                this.toast((this.lang === 'zh' ? '配置已保存到 ' : 'Config saved to ') + filepath, 'success', 5000);
            } else {
                this.toast(this.t('export_failed'), 'error');
            }
        } catch (e) {
            this.toast(this.t('export_failed'), 'error');
        }
    }

    async importConfig() {
        // v2.4: WebUI 容器 <input type=file> 可能不工作
        // 改为从 /sdcard/Download/rescuex-config.json 读取
        const filepath = '/sdcard/Download/rescuex-config.json';
        const confirm = await this.confirmDialog(
            this.t('import_config'),
            this.lang === 'zh'
                ? `将从 ${filepath} 读取配置并覆盖当前配置。请先用"导出配置"生成该文件，或手动放置配置文件到该路径。是否继续？`
                : `Will read config from ${filepath} and overwrite current. Use "Export" first to generate the file, or manually place it there. Continue?`,
            this.t('btn_confirm'), 'btn-filled'
        );
        if (!confirm) return;

        try {
            const text = await this.exec(`cat '${filepath}' 2>/dev/null`);
            if (!text) {
                this.toast(this.lang === 'zh' ? `未找到 ${filepath}` : `Not found: ${filepath}`, 'error');
                return;
            }
            let data;
            try {
                data = JSON.parse(text);
            } catch (e) {
                this.toast(this.t('config_import_failed'), 'error');
                return;
            }
            if (!data.config || typeof data.config !== 'object') {
                this.toast(this.t('config_import_failed'), 'error');
                return;
            }
            // v2.5 修复 Issue 4：字段级校验 + 范围 clamp，避免导入任意值的配置
            const cfg = data.config;
            const clamped = this._validateAndClampConfig(cfg);
            const lines = [];
            Object.keys(clamped).forEach(k => {
                lines.push(`${k}=${clamped[k]}`);
            });
            lines.push('');
            const configContent = lines.join('\n');
            const configB64 = utf8ToBase64(configContent);
            if (!/^[A-Za-z0-9+/=]*$/.test(configB64)) {
                this.toast(this.t('config_import_failed'), 'error');
                return;
            }
            const result1 = await this.exec(`printf '%s' '${configB64}' | base64 -d > "${this.confFile}" && echo OK`);

            // 白名单（同样做字符校验）
            let result2 = 'OK';
            if (data.whitelist) {
                // 仅允许字母数字 . _ - 和换行/注释
                const safeWl = String(data.whitelist)
                    .split('\n')
                    .map(l => {
                        // 保留注释行
                        const hashIdx = l.indexOf('#');
                        const comment = hashIdx >= 0 ? l.substring(hashIdx) : '';
                        const content = hashIdx >= 0 ? l.substring(0, hashIdx) : l;
                        const cleaned = content.replace(/[^A-Za-z0-9._-]/g, '').trim();
                        return cleaned || comment;
                    })
                    .filter(l => l)
                    .join('\n');
                const b64 = utf8ToBase64(safeWl + '\n');
                if (/^[A-Za-z0-9+/=]*$/.test(b64)) {
                    result2 = await this.exec(`printf '%s' '${b64}' | base64 -d > "${this.whitelistFile}" && echo OK`);
                } else {
                    result2 = '';
                }
            }

            if (result1.includes('OK') && result2.includes('OK')) {
                this.toast(this.t('config_imported'), 'success');
                await this.loadConfig();
                await this.loadModules();
            } else {
                this.toast(this.t('save_failed'), 'error');
            }
        } catch (e) {
            this.toast(this.t('config_import_failed'), 'error');
        }
    }

    // v2.5: 配置字段级校验与 clamp（修复 Issue 4）
    // 与 common.sh 的 read_config 范围保持一致
    _validateAndClampConfig(cfg) {
        const out = {};
        // 数值字段定义：[key, min, max, default]
        const numFields = [
            ['REBOOT_THRESHOLD', 1, 10, 3],
            ['BOOT_TIMEOUT_SEC', 30, 600, 90],
            ['OTA_TIMEOUT_SEC', 60, 1800, 900],
            ['USER_REBOOT_GRACE_SEC', 5, 300, 30],
            ['PATCH_UPDATE_TIMEOUT_SEC', 60, 600, 180],
            ['PATCH_FAIL_THRESHOLD', 1, 5, 2],
            ['WATCHDOG_POLL_INTERVAL_SEC', 1, 10, 2]
        ];
        numFields.forEach(([k, min, max, def]) => {
            let v = cfg[k];
            if (v === undefined || v === null) {
                out[k] = String(def);
                return;
            }
            // LOG-005: Reject negative values instead of silently stripping the minus sign
            let vStr = String(v).trim();
            if (vStr.startsWith('-')) {
                out[k] = String(def);
                return;
            }
            let n = parseInt(vStr.replace(/[^0-9]/g, ''));
            if (isNaN(n)) n = def;
            if (n < min) n = min;
            if (n > max) n = max;
            out[k] = String(n);
        });
        const boolDefaults = {
            ENABLED: 'true',
            LOG_ENABLED: 'true',
            DRY_RUN: 'false',
            PROGRESSIVE_RESCUE: 'true',
            AUTO_REENABLE: 'false',
            PATCH_AUTO_ROLLBACK: 'true'
        };
        Object.keys(boolDefaults).forEach(k => {
            if (cfg[k] === undefined || cfg[k] === null) {
                out[k] = boolDefaults[k];
                return;
            }
            let v = String(cfg[k]).toLowerCase().trim();
            out[k] = v === 'true' ? 'true' : 'false';
        });
        return out;
    }

    // === 手动操作 ===
    _buildModuleScript(action) {
        const basesStr = this.moduleBases.join(' ');
        if (action === 'disable') {
            return `WL_CONTENT="
\$(cat "${this.whitelistFile}" 2>/dev/null)
"
for base in ${basesStr}; do
  [ -d "\$base" ] || continue
  for d in "\$base"/*/; do
    [ -d "\$d" ] || continue
    m=\$(basename "\$d")
    [ "\$m" = "${this.selfId}" ] && continue
    case "\$m" in *[!A-Za-z0-9._-]*) continue ;; esac
    case "\$WL_CONTENT" in *"
\$m
"*) continue ;; esac
    [ -f "\$d/disable" ] && continue
    touch "\$d/disable" 2>/dev/null && echo "disabled:\$m"
  done
done`;
        } else {
            return `for base in ${basesStr}; do
  [ -d "\$base" ] || continue
  for d in "\$base"/*/; do
    [ -d "\$d" ] || continue
    m=\$(basename "\$d")
    [ "\$m" = "${this.selfId}" ] && continue
    case "\$m" in *[!A-Za-z0-9._-]*) continue ;; esac
    [ -f "\$d/disable" ] || continue
    rm -f "\$d/disable" 2>/dev/null && echo "enabled:\$m"
  done
done`;
        }
    }

    async disableAllModules() {
        const confirm = await this.confirmDialog(
            this.t('confirm_title'),
            this.t('confirm_disable_all'),
            this.t('btn_confirm'), 'btn-danger'
        );
        if (!confirm) return;
        this.toast(this.lang === 'zh' ? '正在禁用...' : 'Disabling...', '');
        this.showLoading(true);
        try {
            const out = await this.exec(this._buildModuleScript('disable'));
            const count = (out.match(/^disabled:/gm) || []).length;
            this.toast(this.t('disabled_count').replace('N', count), 'success');
            this.loadStatus();
            this.loadDisabledModules();
        } catch (e) {
            this.toast(this.t('save_failed'), 'error');
        }
        this.showLoading(false);
    }

    async reenableAllModules() {
        const confirm = await this.confirmDialog(
            this.t('confirm_title'),
            this.t('confirm_enable_all'),
            this.t('btn_confirm'), 'btn-filled'
        );
        if (!confirm) return;
        this.toast(this.lang === 'zh' ? '正在恢复...' : 'Enabling...', '');
        this.showLoading(true);
        try {
            const out = await this.exec(this._buildModuleScript('enable'));
            const count = (out.match(/^enabled:/gm) || []).length;
            this.toast(this.t('enabled_count').replace('N', count), 'success');
            this.loadStatus();
            this.loadDisabledModules();
        } catch (e) {
            this.toast(this.t('save_failed'), 'error');
        }
        this.showLoading(false);
    }

    // v2.4: 手动设置/清除补丁更新标记
    async togglePatchFlag() {
            const current = await this.exec(`cat "${this.stateDir}/patch_update_flag" 2>/dev/null`);
            if (current === '1') {
            // 清除标记
            const confirm = await this.confirmDialog(
                this.lang === 'zh' ? '清除补丁标记' : 'Clear Patch Flag',
                this.lang === 'zh'
                    ? '将清除补丁更新标记和补丁失败计数。通常在系统更新成功后自动清除。是否继续？'
                    : 'Will clear patch update flag and patch fail count. Usually auto-cleared on successful boot. Continue?',
                this.t('btn_confirm'), 'btn-filled'
                );
                if (!confirm) return;
                await this.exec(`. "${this.basePath}/common.sh" && manual_clear_patch_flag`);
                this.toast(this.lang === 'zh' ? '补丁标记已清除' : 'Patch flag cleared', 'success');
            } else {
            // 设置标记
            const confirm = await this.confirmDialog(
                this.lang === 'zh' ? '设置补丁标记' : 'Set Patch Flag',
                this.lang === 'zh'
                    ? '将手动设置补丁更新标记。下次启动时 RescueX 会使用补丁专属超时（默认 180 秒），失败时只回滚补丁不清整机。适用于手动系统更新、刷入 Magisk 模块后重启等场景。是否继续？'
                    : 'Will manually set patch update flag. Next boot will use patch-specific timeout (default 180s), and failures will only roll back patches, not wipe data. Use for manual system updates, flashing Magisk modules, etc. Continue?',
                this.t('btn_confirm'), 'btn-filled'
                );
                if (!confirm) return;
                await this.exec(`. "${this.basePath}/common.sh" && set_patch_flag`);
                this.toast(this.lang === 'zh' ? '补丁标记已设置，重启后生效' : 'Patch flag set, effective after reboot', 'success');
            }
            this.loadStatus();
    }

    async testWatchdog() {
        const confirm = await this.confirmDialog(
            this.t('confirm_title'),
            this.t('confirm_test_wd'),
            this.t('btn_confirm'), 'btn-danger'
        );
        if (!confirm) return;
        try {
            const script = `( sh "${this.basePath}/watchdog.sh" 10 >/dev/null 2>&1 < /dev/null & ) ; echo "started"`;
            await this.exec(script);
            this.toast(this.lang === 'zh' ? '测试看门狗已启动，10 秒后将触发' : 'Test watchdog started, triggers in 10s', 'warn');
        } catch (e) {
            this.toast(this.t('save_failed'), 'error');
        }
    }

    async rebootDevice() {
        const confirm = await this.confirmDialog(
            this.t('confirm_title'),
            this.t('confirm_reboot'),
            this.t('btn_confirm'), 'btn-danger'
        );
        if (!confirm) return;
        try {
            await this.exec('sync ; sleep 1 ; setprop sys.powerctl reboot');
            this.toast(this.lang === 'zh' ? '正在重启...' : 'Rebooting...', 'success');
        } catch (e) {
            this.toast(this.t('save_failed'), 'error');
        }
    }

    // === 诊断报告 ===
    async generateReport() {
        this.showLoading(true);
        // v2.7: 60s 超时下补充 "生成中..." 提示，避免用户误以为卡死
        this.toast(this.lang === 'zh' ? '生成中...' : 'Generating...', '', 60000);
        try {
            const script = `MODDIR="${this.basePath}"; . "${this.basePath}/common.sh" 2>/dev/null
generate_report`;
            const report = await this.exec(script, EXEC_REPORT_TIMEOUT_MS);
            if (!report) {
                // v2.6.0 F-BUG-8: 区分超时与空输出，给出更明确提示
                console.warn('[RescueX] generateReport: empty output (likely timeout or common.sh not found)');
                this.toast(this.lang === 'zh'
                    ? '报告生成失败：执行超时或 common.sh 不可达，请检查模块路径'
                    : 'Report failed: timeout or common.sh unreachable, check module path', 'error', 6000);
                return;
            }
            this.showTextModal(this.t('report_title'), report);
        } catch (e) {
            // v2.6.0 F-BUG-8: catch 块输出详细错误到 console 便于排障
            console.warn('[RescueX] generateReport error:', e);
            this.toast(this.lang === 'zh'
                ? '报告生成异常：' + (e && e.message ? e.message : '未知错误')
                : 'Report error: ' + (e && e.message ? e.message : 'unknown'), 'error', 6000);
        }
        this.showLoading(false);
    }

    async generateDecisionReport() {
        this.showLoading(true);
        this.toast(this.lang === 'zh' ? '生成中...' : 'Generating...', '', 60000);
        try {
            const report = await this.exec(`MODDIR="${this.basePath}"; . "${this.basePath}/common.sh" 2>/dev/null
manual_generate_rescue_decision_report`, EXEC_REPORT_TIMEOUT_MS);
            if (!report) {
                this.toast(this.t('snapshot_failed'), 'error', 6000);
                return;
            }
            this.showTextModal(this.t('decision_report_title'), report);
        } catch (e) {
            this.toast(this.t('snapshot_failed'), 'error', 6000);
        }
        this.showLoading(false);
    }

    showTextModal(title, report) {
        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay';
        const modal = document.createElement('div');
        modal.className = 'modal';
        modal.style.maxWidth = '560px';

        const h3 = document.createElement('h3');
        h3.textContent = title;

        const pre = document.createElement('pre');
        pre.className = 'log-view';
        pre.style.maxHeight = '400px';
        pre.textContent = report;

        const btns = document.createElement('div');
        btns.className = 'modal-buttons';

        const cancel = document.createElement('button');
        cancel.className = 'btn btn-text';
        cancel.textContent = this.t('btn_cancel');

        const copyBtn = document.createElement('button');
        copyBtn.className = 'btn btn-filled';
        copyBtn.textContent = this.t('copy');

        const downloadBtn = document.createElement('button');
        downloadBtn.className = 'btn btn-tonal';
        downloadBtn.textContent = this.t('export');

        btns.appendChild(cancel);
        btns.appendChild(copyBtn);
        btns.appendChild(downloadBtn);
        modal.appendChild(h3);
        modal.appendChild(pre);
        modal.appendChild(btns);
        overlay.appendChild(modal);
        document.body.appendChild(overlay);

        const close = () => overlay.remove();
        cancel.onclick = close;
        overlay.onclick = (e) => { if (e.target === overlay) close(); };
        copyBtn.onclick = async () => {
            try {
                await navigator.clipboard.writeText(report);
                this.toast(this.t('copied'), 'success');
            } catch (e) {
                // fallback
                const ta = document.createElement('textarea');
                ta.value = report;
                document.body.appendChild(ta);
                ta.select();
                document.execCommand('copy');
                document.body.removeChild(ta);
                this.toast(this.t('copied'), 'success');
            }
        };
        downloadBtn.onclick = async () => {
            // v2.4: WebUI 容器不支持 Blob 下载，改用 shell 写入 /sdcard/Download + am start 分享
            const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
            const filename = `rescuex-report-${ts}.txt`;
            const filepath = `/sdcard/Download/${filename}`;
            try {
                // 用 base64 编码避免特殊字符问题
                const b64 = utf8ToBase64(report);
                if (!/^[A-Za-z0-9+/=]*$/.test(b64)) {
                    this.toast(this.t('export_failed'), 'error');
                    return;
                }
                // 写入 /sdcard/Download
                const result = await this.exec(`mkdir -p /sdcard/Download && printf '%s' '${b64}' | base64 -d > '${filepath}' && echo OK`);
                if (result.includes('OK')) {
                    // 触发媒体扫描 + 用分享面板
                    await this.exec(`am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file://'${filepath}' 2>/dev/null; am start -a android.intent.action.SEND -t text/plain --android.intent.extra.STREAM file://'${filepath}' 2>/dev/null`);
                    this.toast((this.lang === 'zh' ? '已保存到 ' : 'Saved to ') + filepath, 'success', 5000);
                } else {
                    this.toast(this.t('export_failed'), 'error');
                }
            } catch (e) {
                this.toast(this.t('export_failed'), 'error');
            }
        };
    }

    // === 日志 ===
    async loadHistory() {
        try {
            const raw = await this.exec(`tail -n 50 "${this.historyFile}" 2>/dev/null`);
            this.qs('#boot-history').textContent = raw || (this.lang === 'zh' ? '暂无启动记录' : 'No history');
        } catch (e) {
            this.qs('#boot-history').textContent = this.lang === 'zh' ? '读取失败' : 'Read failed';
        }
    }

    async loadLog() {
        try {
            const raw = await this.exec(`tail -n 80 "${this.logFile}" 2>/dev/null`);
            const el = this.qs('#rescue-log');
            el.textContent = raw || (this.lang === 'zh' ? '暂无日志' : 'No logs');
            this.highlightLog(el);
        } catch (e) {
            this.qs('#rescue-log').textContent = this.lang === 'zh' ? '读取失败' : 'Read failed';
        }
    }

    highlightLog(el) {
        const text = el.textContent;
        if (!text) return;
        const lines = text.split('\n');
        const html = lines.map(line => {
            let cls = '';
            if (/警告|失败|错误|CRITICAL|ERROR|FAIL/i.test(line)) cls = 'log-line-error';
            else if (/超时|timeout|WARNING|WARN/i.test(line)) cls = 'log-line-warn';
            else if (/成功|完成|SUCCESS|OK/i.test(line)) cls = 'log-line-ok';
            else if (/启动|初始化|INFO|START/i.test(line)) cls = 'log-line-info';
            return cls ? `<span class="${cls}">${this.escapeHtml(line)}</span>` : this.escapeHtml(line);
        }).join('\n');
        el.innerHTML = html;
    }

    async detectManager() {
        const out = await this.exec(`[ -d /data/adb/ksu ] && if pm list packages 2>/dev/null | grep -qi sukisu; then if pm list packages 2>/dev/null | grep -q "com.dergoogler.mmrl\|com.dergoogler.mmrl.wx"; then echo "SukiSU Ultra (MMRL)"; else echo "SukiSU Ultra"; fi; else if pm list packages 2>/dev/null | grep -q "com.dergoogler.mmrl\|com.dergoogler.mmrl.wx"; then echo "KSU (MMRL)"; else echo KSU; fi; fi ; [ -d /data/adb/ap ] && echo APatch ; [ -d /data/adb/magisk ] && echo Magisk`);
        const managers = out.split('\n').filter(Boolean);
        this.setText('#info-manager', managers.join(' / ') || (this.lang === 'zh' ? '未知' : 'Unknown'));
    }

    switchTab(tab) {
        this.currentTab = tab;
        document.querySelectorAll('.tab').forEach(t => t.classList.toggle('active', t.dataset.tab === tab));
        this.qs('#rescue-log').classList.toggle('hidden', tab !== 'log');
        this.qs('#boot-history').classList.toggle('hidden', tab !== 'history');
    }

    startAutoRefresh() {
        if (this.refreshTimer) clearInterval(this.refreshTimer);
        this.refreshTimer = setInterval(async () => {
            if (!this.isLoading) {
                let dashboardSnapshot = null;
                try {
                    dashboardSnapshot = await this.getDashboardSnapshot({ force: true });
                } catch (_) {}
                this.loadStatus(dashboardSnapshot ? { snapshot: dashboardSnapshot } : {});
                // 日志 Tab 也自动刷新（频率较低）
                if (this.currentTab === 'log') this.loadLog();
                // v2.5: 统计面板每 ~30 秒刷新一次（每 6 个周期）
                this._statsCounter = (this._statsCounter || 0) + 1;
                if (this._statsCounter >= 6) {
                    this.loadStats(dashboardSnapshot ? { silent: true, snapshot: dashboardSnapshot } : { silent: true });
                    this.loadAuditLog();
                    this.loadBootTrend();
                    this.loadSuspectModules();
                    this.loadRescueLevel();
                    this.loadScriptRiskAlert();
                    this._statsCounter = 0;
                }
            }
        }, 5000);
    }

    async refreshLog() {
        this.showLoading(true);
        if (this.currentTab === 'log') await this.loadLog();
        else await this.loadHistory();
        this.showLoading(false);
        this.toast(this.t('refreshed'), 'success');
    }

    async copyLog() {
        const targetEl = this.currentTab === 'log' ? '#rescue-log' : '#boot-history';
        const text = this.qs(targetEl).textContent || '';
        if (!text || text === this.t('loading')) {
            this.toast(this.t('no_content'), 'warn');
            return;
        }
        try {
            if (navigator.clipboard && navigator.clipboard.writeText) {
                await navigator.clipboard.writeText(text);
                this.toast(this.t('copied'), 'success');
                return;
            }
        } catch (e) { /* fallback */ }
        try {
            const ta = document.createElement('textarea');
            ta.value = text;
            ta.style.cssText = 'position:fixed;top:-9999px;left:-9999px;opacity:0;';
            document.body.appendChild(ta);
            ta.select();
            const ok = document.execCommand('copy');
            document.body.removeChild(ta);
            if (ok) this.toast(this.t('copied'), 'success');
            else this.toast(this.t('copy_failed'), 'error');
        } catch (e) {
            this.toast(this.t('copy_failed'), 'error');
        }
    }

    async exportLog() {
        const targetEl = this.currentTab === 'log' ? '#rescue-log' : '#boot-history';
        const text = this.qs(targetEl).textContent || '';
        if (!text || text === this.t('loading')) {
            this.toast(this.t('no_content'), 'warn');
            return;
        }
        // v2.4: WebUI 容器不支持 Blob 下载，改用 shell 写入 /sdcard/Download + am start 分享
        try {
            const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
            const name = this.currentTab === 'log' ? `rescuex-log-${ts}.txt` : `rescuex-history-${ts}.txt`;
            const filepath = `/sdcard/Download/${name}`;
            const b64 = utf8ToBase64(text);
            if (!/^[A-Za-z0-9+/=]*$/.test(b64)) {
                this.toast(this.t('export_failed'), 'error');
                return;
            }
            const result = await this.exec(`mkdir -p /sdcard/Download && printf '%s' '${b64}' | base64 -d > '${filepath}' && echo OK`);
            if (result.includes('OK')) {
                await this.exec(`am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file://'${filepath}' 2>/dev/null`);
                this.toast((this.lang === 'zh' ? '已保存到 ' : 'Saved to ') + filepath, 'success', 5000);
            } else {
                this.toast(this.t('export_failed'), 'error');
            }
        } catch (e) {
            this.toast(this.t('export_failed'), 'error');
        }
    }

    async clearLog() {
        const target = this.currentTab === 'log' ? this.logFile : this.historyFile;
        const targetEl = this.currentTab === 'log' ? '#rescue-log' : '#boot-history';
        const confirm = await this.confirmDialog(
            this.t('confirm_title'),
            this.t('confirm_clear'),
            this.t('btn_confirm'), 'btn-danger'
        );
        if (!confirm) return;
        try {
            await this.exec(`: > "${target}"`);
            this.qs(targetEl).textContent = this.t('cleared');
            this.toast(this.t('cleared'), 'success');
        } catch (e) {
            this.toast(this.t('save_failed'), 'error');
        }
    }

    // === v2.5: 首次运行引导 ===
    async checkFirstRun() {
        try {
            const raw = await this.exec(`cat "${this.stateDir}/first_run" 2>/dev/null`);
            const val = (raw || '').trim();
            if (val === '1' || val === '2') {
                this.firstRun = parseInt(val);
                if (!this.onboardingShown) {
                    this.showOnboarding();
                }
            }
        } catch (e) { /* 忽略 */ }
    }

    showOnboarding() {
        if (this.onboardingShown) return;
        this.onboardingShown = true;

        const overlay = document.createElement('div');
        overlay.className = 'onboarding-overlay';

        const modal = document.createElement('div');
        modal.className = 'onboarding';

        const logo = document.createElement('div');
        logo.className = 'onboarding-logo';
        logo.textContent = 'R';

        const h2 = document.createElement('h2');
        h2.textContent = this.t('onboarding_title');

        const subtitle = document.createElement('div');
        subtitle.className = 'onboarding-subtitle';
        subtitle.textContent = this.t('onboarding_subtitle');

        // 步骤
        const steps = document.createElement('div');
        steps.className = 'onboarding-steps';
        const stepData = [
            ['1', 'onboarding_step1_title', 'onboarding_step1_desc'],
            ['2', 'onboarding_step2_title', 'onboarding_step2_desc'],
            ['3', 'onboarding_step3_title', 'onboarding_step3_desc'],
            ['4', 'onboarding_step4_title', 'onboarding_step4_desc'],
            ['5', 'onboarding_step5_title', 'onboarding_step5_desc'],
        ];
        // 若是升级（firstRun=2），额外显示新功能介绍
        if (this.firstRun === 2) {
            stepData.push(['★', 'onboarding_new_features', 'onboarding_new_features_desc']);
        }
        stepData.forEach(([num, titleKey, descKey]) => {
            const step = document.createElement('div');
            step.className = 'onboarding-step';
            const numEl = document.createElement('div');
            numEl.className = 'onboarding-step-num';
            numEl.textContent = num;
            const content = document.createElement('div');
            content.className = 'onboarding-step-content';
            const t = document.createElement('div');
            t.className = 'onboarding-step-title';
            t.textContent = this.t(titleKey);
            const d = document.createElement('div');
            d.className = 'onboarding-step-desc';
            d.textContent = this.t(descKey);
            content.appendChild(t);
            content.appendChild(d);
            step.appendChild(numEl);
            step.appendChild(content);
            steps.appendChild(step);
        });

        const actions = document.createElement('div');
        actions.className = 'onboarding-actions';
        const skipBtn = document.createElement('button');
        skipBtn.className = 'btn btn-text';
        skipBtn.textContent = this.t('onboarding_skip');
        const ackBtn = document.createElement('button');
        ackBtn.className = 'btn btn-filled';
        ackBtn.textContent = this.t('onboarding_ack');

        actions.appendChild(skipBtn);
        actions.appendChild(ackBtn);

        modal.appendChild(logo);
        modal.appendChild(h2);
        modal.appendChild(subtitle);
        modal.appendChild(steps);
        modal.appendChild(actions);
        overlay.appendChild(modal);
        document.body.appendChild(overlay);

        const ack = async () => {
            // 写入 onboarding_ack 标记，清除 first_run
            await this.exec(`echo 1 > "${this.stateDir}/onboarding_ack" && echo 0 > "${this.stateDir}/first_run"`);
            overlay.remove();
            // 升级用户额外提示查看新功能
            if (this.firstRun === 2) {
                this.toast(this.lang === 'zh' ? '欢迎升级到 v3.1.1 Beta！' : 'Welcome to v3.1.1 Beta!', 'success');
            }
        };
        ackBtn.onclick = ack;
        skipBtn.onclick = () => {
            // 跳过不写 ack，下次还会再弹（除非用户主动看完）
            overlay.remove();
            this.onboardingShown = false;
        };
    }

    // === v2.5: 启动统计面板 ===
    async loadStats(options = {}) {
        try {
            const stats = options.snapshot || await this.getDashboardSnapshot({ force: !!options.force });
            if (!stats || typeof stats.TOTAL === 'undefined') {
                throw new Error('invalid stats output');
            }
            const total = parseInt(stats.TOTAL) || 0;
            const success = parseInt(stats.SUCCESS) || 0;
            const rescued = parseInt(stats.RESCUED) || 0;
            const failed = parseInt(stats.FAILED) || 0;
            const rate = parseInt(stats.SUCCESS_RATE) || 0;
            const avgDur = parseInt(stats.AVG_DURATION) || 0;
            const lastRescue = parseInt(stats.LAST_RESCUE_TIME) || 0;
            const lastSuccess = parseInt(stats.LAST_SUCCESS_TIME) || 0;

            this.setText('#stat-success-rate', `${rate}%`);
            this.setText('#stat-avg-duration', avgDur > 0 ? `${avgDur}${this.t('seconds')}` : '--');
            this.setText('#stat-total', total);
            this.setText('#stat-rescued', rescued);
            this.setText('#stat-success', success);
            this.setText('#stat-failed', failed);
            this.setText('#stat-last-success', lastSuccess > 0 ? this.formatTime(lastSuccess) : this.t('never'));
            this.setText('#stat-last-rescue', lastRescue > 0 ? this.formatTime(lastRescue) : this.t('never'));

            // 颜色提示
            const rateEl = this.qs('#stat-success-rate');
            if (rateEl) {
                rateEl.className = 'stat-value ' + (rate >= 90 ? 'ok' : (rate >= 60 ? 'warn' : 'danger'));
            }
            const rescuedEl = this.qs('#stat-rescued');
            if (rescuedEl) {
                rescuedEl.className = 'stat-value ' + (rescued === 0 ? 'ok' : 'warn');
            }
        } catch (e) {
            // v2.6.0 F-BUG-7: 补充 console.warn 辅助排障，保留原 UI 重置 + toast 提示
            console.warn('[RescueX] loadStats failed:', e,
                '\n  basePath=', this.basePath,
                '\n  可能原因：common.sh 不在该路径（F-BUG-5）、exec 超时、compute_boot_stats 输出格式异常');
            this.setText('#stat-success-rate', '--%');
            this.setText('#stat-avg-duration', '--');
            this.setText('#stat-last-success', this.t('unknown_time'));
            this.setText('#stat-last-rescue', this.t('unknown_time'));
            if (!options.silent) this.toast(this.t('stats_unavailable'), 'warn');
        }
    }

    async refreshStats() {
        this.showLoading(true);
        await this.loadStats();
        this.showLoading(false);
        this.toast(this.t('refreshed'), 'success');
    }

    // v2.5: 时间戳格式化为相对时间
    formatTime(epoch) {
        if (!epoch || epoch <= 0) return this.t('never');
        const now = Math.floor(Date.now() / 1000);
        const diff = now - epoch;
        if (diff < 0) return this.t('unknown_time');
        if (diff < 60) return this.t('just_now');
        if (diff < 3600) return `${Math.floor(diff / 60)} ${this.t('minutes_ago')}`;
        if (diff < 86400) return `${Math.floor(diff / 3600)} ${this.t('hours_ago')}`;
        return `${Math.floor(diff / 86400)} ${this.t('days_ago')}`;
    }

    // === v2.5: 文档 Modal（功能介绍/隐私协议/使用须知）===
    _showDocModal(title, htmlContent) {
        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay';
        const modal = document.createElement('div');
        modal.className = 'doc-modal';
        const h2 = document.createElement('h2');
        h2.textContent = title;
        const body = document.createElement('div');
        // htmlContent 仅来自 showFeatures/showPrivacy/showUsage 中的硬编码文档。
        body.innerHTML = htmlContent;
        const actions = document.createElement('div');
        actions.className = 'doc-actions';
        const closeBtn = document.createElement('button');
        closeBtn.className = 'btn btn-filled';
        closeBtn.textContent = this.t('doc_close');
        actions.appendChild(closeBtn);
        modal.appendChild(h2);
        modal.appendChild(body);
        modal.appendChild(actions);
        overlay.appendChild(modal);
        document.body.appendChild(overlay);
        const close = () => overlay.remove();
        closeBtn.onclick = close;
        overlay.onclick = (e) => { if (e.target === overlay) close(); };
    }

    showFeatures() {
        const isZh = this.lang === 'zh';
        const html = isZh ? `
            <h3>核心保护</h3>
            <ul>
                <li><strong>连续重启检测</strong>：达到阈值（默认 3 次）自动禁用所有非白名单模块</li>
                <li><strong>开机超时看门狗</strong>：开机超过指定时长未完成，自动救砖并重启</li>
                <li><strong>渐进式救砖</strong>：第一次失败只禁用最近安装的模块，达到阈值才全禁</li>
                <li><strong>白名单保护</strong>：关键模块（字体、音效等）可加入白名单不被禁用</li>
            </ul>
            <h3>智能识别</h3>
            <ul>
                <li><strong>OTA 智能识别</strong>：检测底层 OTA 升级（属性 / recovery / BCB / update_engine），自动延长超时（默认 15 分钟）</li>
                <li><strong>补丁更新识别</strong>：区分 ColorOS/MIUI 等上层系统补丁与底层 OTA，独立超时与失败计数，达到阈值只做轻量回滚</li>
                <li><strong>用户重启识别</strong>：短时间内主动重启不计入失败次数</li>
                <li><strong>启动模式感知</strong>（v2.5）：Recovery / Fastbootd / Charger 模式自动跳过失败计数</li>
            </ul>
            <h3>高级特性</h3>
            <ul>
                <li><strong>DRY_RUN 模式</strong>：仅记录日志不实际禁用，方便验证逻辑</li>
                <li><strong>自动恢复</strong>（实验性）：救砖后下次启动自动恢复被禁用的模块</li>
                <li><strong>模块状态快照</strong>：手动创建快照，补丁回滚或误禁用后可一键恢复</li>
                <li><strong>诊断报告</strong>：一键生成含设备信息、模块状态、日志片段的纯文本报告</li>
                <li><strong>启动统计</strong>（v2.5）：成功率、平均耗时、救砖时间线</li>
                <li><strong>三级渐进式救砖</strong>（v3.0）：嫌疑禁用 → 全量+脚本锁定 → APP 解冻，逐级升级不遗漏任何可能</li>
                <li><strong>嫌疑模块追踪</strong>（v3.0）：启动成功后自动记录已知良好列表，下次失败精准对比定位新增/新启用模块</li>
                <li><strong>脚本目录锁定</strong>（v3.0）：全量救砖时同时锁定 service.d/post-fs-data.d 等目录的执行权限</li>
                <li><strong>APP 自动解冻</strong>（v3.0）：删除 package-restrictions.xml 解冻被 PM 冻结的关键应用</li>
            </ul>
            <h3>安全设计</h3>
            <ul>
                <li>状态原子写入（tmp+sync+rename，断电不损坏）</li>
                <li>看门狗独立进程，双 fork 脱离父进程</li>
                <li>kill 前按 cmdline 验证 PID，避免 PID 复用误杀</li>
                <li>看门狗自适应轮询（v2.5）：长超时场景自动放大间隔，减少 I/O</li>
                <li>WebUI 路径白名单校验、base64 编码传输、textContent 防 XSS</li>
                <li>最小权限：状态目录 0700，敏感文件 0600，脚本 0700</li>
            </ul>
        ` : `
            <h3>Core Protection</h3>
            <ul>
                <li><strong>Consecutive Reboot Detection</strong>: Disable all non-whitelisted modules after threshold (default 3)</li>
                <li><strong>Boot Timeout Watchdog</strong>: Auto-rescue and reboot if boot not completed in time</li>
                <li><strong>Progressive Rescue</strong>: First failure only disables recently installed modules</li>
                <li><strong>Whitelist Protection</strong>: Critical modules (fonts, audio, etc.) survive rescue</li>
            </ul>
            <h3>Smart Detection</h3>
            <ul>
                <li><strong>OTA Detection</strong>: Detects firmware OTA via props/recovery/BCB/update_engine, extends timeout (default 15 min)</li>
                <li><strong>Patch Update Detection</strong>: Distinguishes ColorOS/MIUI patches from OTA, independent timeout & rollback</li>
                <li><strong>User Reboot Recognition</strong>: Short reboots not counted as failures</li>
                <li><strong>Boot Mode Awareness</strong> (v2.5): Recovery/Fastbootd/Charger modes skip failure counting</li>
            </ul>
            <h3>Advanced</h3>
            <ul>
                <li><strong>DRY_RUN</strong>: Log-only mode for logic validation</li>
                <li><strong>Auto Re-enable</strong> (experimental): Restore disabled modules on next boot</li>
                <li><strong>Snapshots</strong>: Manual state snapshots for one-click rollback</li>
                <li><strong>Diagnostic Report</strong>: One-click text report with device info & logs</li>
                <li><strong>Boot Statistics</strong> (v2.5): Success rate, avg duration, rescue timeline</li>
                <li><strong>Three-Level Rescue</strong> (v3.0): Suspect disable → Full + Script Lock → APP Unfreeze</li>
                <li><strong>Suspect Module Tracking</strong> (v3.0): Auto-saves known-good list on success, diff-compares on failure</li>
                <li><strong>Script Directory Locking</strong> (v3.0): Lock service.d/post-fs-data.d permissions during full rescue</li>
                <li><strong>APP Auto-Unfreeze</strong> (v3.0): Delete package-restrictions.xml to unfreeze critical apps</li>
            </ul>
            <h3>Security</h3>
            <ul>
                <li>Atomic state writes (tmp+sync+rename)</li>
                <li>Independent watchdog process (double fork)</li>
                <li>PID verification via cmdline before kill</li>
                <li>Adaptive watchdog polling (v2.5)</li>
                <li>WebUI path whitelist, base64 transport, XSS prevention</li>
                <li>Least privilege: 0700 dirs, 0600 sensitive files, 0700 scripts</li>
            </ul>
        `;
        this._showDocModal(this.t('features_title'), html);
    }

    showPrivacy() {
        const isZh = this.lang === 'zh';
        const html = isZh ? `
            <div class="privacy-section">
                <h3>1. 数据收集声明</h3>
                <p>RescueX <strong>不收集、不上传、不分享</strong>任何用户数据。所有运行数据均存储在设备本地的 <code>/data/adb/modules/RescueX/webroot/state/</code> 目录下。</p>
            </div>
            <div class="privacy-section">
                <h3>2. 本地存储的数据</h3>
                <p>以下数据仅存储在设备本地，不会离开设备：</p>
                <ul>
                    <li><strong>配置文件</strong>（config.conf）：救砖参数（阈值、超时等）</li>
                    <li><strong>白名单</strong>（whitelist.conf）：用户指定的保护模块列表</li>
                    <li><strong>启动状态</strong>（boot_status）：上次启动结果、失败计数、救砖次数</li>
                    <li><strong>启动历史</strong>（boot_history）：最近 100 次启动记录（仅时间与结果，无内容）</li>
                    <li><strong>日志</strong>（rescue.log）：救砖操作日志（超 500KB 自动轮转，保留最后 200 行）</li>
                    <li><strong>快照</strong>（snapshots/）：模块启用/禁用状态快照</li>
                </ul>
            </div>
            <div class="privacy-section">
                <h3>3. 系统信息读取</h3>
                <p>为完成救砖功能，RescueX 会读取以下系统信息（仅本地处理，不上传）：</p>
                <ul>
                    <li>设备型号、Android 版本、内核版本（仅用于诊断报告）</li>
                    <li>系统属性（getprop）用于 OTA/补丁/启动模式检测</li>
                    <li>已安装模块列表（仅模块 ID，不读取模块内容）</li>
                    <li>LSPosed 禁用状态（v2.5，仅用于诊断）</li>
                </ul>
            </div>
            <div class="privacy-section">
                <h3>4. 网络行为</h3>
                <p>RescueX <strong>完全离线运行</strong>，不发起任何网络请求。WebUI 中的"导出配置/报告"功能通过 shell 写入 <code>/sdcard/Download/</code>，由用户自行管理。</p>
            </div>
            <div class="privacy-section">
                <h3>5. 卸载与数据清理</h3>
                <p>卸载模块时，<code>uninstall.sh</code> 会彻底清理所有状态文件、日志、快照与临时文件，不残留任何数据。</p>
            </div>
            <div class="privacy-section">
                <h3>6. 权限说明</h3>
                <p>RescueX 通过 root 权限运行（Magisk/KernelSU/APatch 提供），仅执行以下操作：</p>
                <ul>
                    <li>读写 <code>/data/adb/modules/</code> 下的模块 disable 标记</li>
                    <li>读取系统属性、/proc、/dev/block 信息</li>
                    <li>触发系统重启（仅救砖时）</li>
                </ul>
                <p>不会访问通讯录、短信、相册、位置等敏感数据。</p>
            </div>
        ` : `
            <div class="privacy-section">
                <h3>1. Data Collection</h3>
                <p>RescueX <strong>does not collect, upload, or share</strong> any user data. All runtime data is stored locally at <code>/data/adb/modules/RescueX/webroot/state/</code>.</p>
            </div>
            <div class="privacy-section">
                <h3>2. Locally Stored Data</h3>
                <ul>
                    <li><strong>Config</strong> (config.conf): Rescue parameters</li>
                    <li><strong>Whitelist</strong> (whitelist.conf): Protected modules</li>
                    <li><strong>Boot Status</strong> (boot_status): Last result, fail count, rescue count</li>
                    <li><strong>Boot History</strong> (boot_history): Last 100 boots (time + result only)</li>
                    <li><strong>Logs</strong> (rescue.log): Auto-rotates at 500KB, keeps last 200 lines</li>
                    <li><strong>Snapshots</strong> (snapshots/): Module state snapshots</li>
                </ul>
            </div>
            <div class="privacy-section">
                <h3>3. System Info Access</h3>
                <ul>
                    <li>Device model, Android version, kernel (for diagnostic report only)</li>
                    <li>System properties (getprop) for OTA/patch/boot mode detection</li>
                    <li>Installed module list (IDs only, not content)</li>
                    <li>LSPosed state (v2.5, diagnostic only)</li>
                </ul>
            </div>
            <div class="privacy-section">
                <h3>4. Network</h3>
                <p>RescueX <strong>runs fully offline</strong>. No network requests. Export features write to <code>/sdcard/Download/</code> via shell.</p>
            </div>
            <div class="privacy-section">
                <h3>5. Uninstall</h3>
                <p><code>uninstall.sh</code> completely removes all state, logs, snapshots, and temp files.</p>
            </div>
            <div class="privacy-section">
                <h3>6. Permissions</h3>
                <p>Runs as root (via Magisk/KernelSU/APatch). Only:</p>
                <ul>
                    <li>Reads/writes module disable flags in <code>/data/adb/modules/</code></li>
                    <li>Reads system props, /proc, /dev/block</li>
                    <li>Triggers reboot (only on rescue)</li>
                </ul>
                <p>Does NOT access contacts, SMS, gallery, location, or other sensitive data.</p>
            </div>
        `;
        this._showDocModal(this.t('privacy_title'), html);
    }

    showUsage() {
        const isZh = this.lang === 'zh';
        const html = isZh ? `
            <h3>⚠ 使用前必读</h3>
            <p>本模块涉及<strong>禁用系统模块</strong>和<strong>触发重启</strong>，使用前请务必：</p>
            <ol>
                <li><strong>备份重要数据</strong>：虽然救砖逻辑设计为只禁用模块不清数据，但极端情况下仍可能需要恢复出厂设置。</li>
                <li><strong>在测试设备上验证</strong>：首次使用建议先在非主力设备上测试，确认逻辑符合预期。</li>
                <li><strong>开启 DRY_RUN 模式</strong>：首次使用时勾选 DRY_RUN，仅记录日志不实际禁用，观察日志确认逻辑无误后再正式启用。</li>
            </ol>

            <h3>📋 推荐配置流程</h3>
            <ol>
                <li>安装模块后重启设备</li>
                <li>打开 WebUI，完成首次引导</li>
                <li>开启 <code>DRY_RUN</code> 模式，保存配置</li>
                <li>重启设备，观察 <code>rescue.log</code> 是否正常记录启动过程</li>
                <li>确认无误后，关闭 DRY_RUN，根据需要调整阈值与超时</li>
                <li>将关键模块（字体、音效等）加入白名单</li>
                <li>拍一张当前模块状态快照，作为恢复基线</li>
            </ol>

            <h3>🔧 参数调优建议</h3>
            <ul>
                <li><strong>连续重启阈值</strong>：保守用户设为 5，激进用户设为 2（更快救砖但更易误触发）</li>
                <li><strong>开机超时</strong>：慢速设备建议 120-180 秒，旗舰设备 60-90 秒即可</li>
                <li><strong>用户重启宽限期</strong>：频繁调试模块的用户建议设为 60-120 秒</li>
                <li><strong>看门狗轮询间隔</strong>：默认 2 秒足够；长超时场景会自动放大（v2.5），无需手动调整</li>
            </ul>

            <h3>🚨 故障排查</h3>
            <p><strong>救砖未触发：</strong></p>
            <ul>
                <li>检查 <code>config.conf</code> 中 <code>ENABLED=true</code></li>
                <li>检查 <code>rescue.log</code> 是否有 post-fs-data 启动记录</li>
                <li>确认失败次数达到阈值</li>
            </ul>
            <p><strong>误触发救砖：</strong></p>
            <ul>
                <li>调大 <code>USER_REBOOT_GRACE_SEC</code></li>
                <li>开启 <code>DRY_RUN</code> 验证逻辑</li>
                <li>调高 <code>REBOOT_THRESHOLD</code></li>
            </ul>
            <p><strong>系统更新后误触发：</strong></p>
            <ul>
                <li>确认 <code>detect_ota</code> / <code>detect_patch_update</code> 能识别你的 ROM</li>
                <li>适当调大 <code>OTA_TIMEOUT_SEC</code> 或 <code>PATCH_UPDATE_TIMEOUT_SEC</code></li>
            </ul>

            <h3>⚠️ 免责声明</h3>
            <p>本模块作者<strong>不对因使用本模块导致的任何数据丢失或设备损坏负责</strong>。使用即表示你已理解并接受风险。</p>
            <p>如遇救砖后仍无法启动，可尝试：</p>
            <ol>
                <li>进入 Recovery，手动删除 <code>/data/adb/modules/问题模块/disable</code> 之外的所有 disable 标记</li>
                <li>或在 Recovery 中删除 RescueX 模块目录</li>
                <li>极端情况下需恢复出厂设置</li>
            </ol>
        ` : `
            <h3>⚠ Before You Start</h3>
            <p>This module <strong>disables system modules</strong> and <strong>triggers reboots</strong>. Before use:</p>
            <ol>
                <li><strong>Backup important data</strong>: Although rescue logic only disables modules, factory reset may be needed in extreme cases.</li>
                <li><strong>Test on non-primary device</strong>: Validate behavior before deploying to your main device.</li>
                <li><strong>Enable DRY_RUN first</strong>: Log-only mode to verify logic before enabling for real.</li>
            </ol>

            <h3>📋 Recommended Setup</h3>
            <ol>
                <li>Install module, reboot</li>
                <li>Open WebUI, complete onboarding</li>
                <li>Enable <code>DRY_RUN</code>, save config</li>
                <li>Reboot, check <code>rescue.log</code> for normal startup logging</li>
                <li>If OK, disable DRY_RUN, tune thresholds</li>
                <li>Add critical modules (fonts, audio) to whitelist</li>
                <li>Take a snapshot as recovery baseline</li>
            </ol>

            <h3>🔧 Tuning Tips</h3>
            <ul>
                <li><strong>Reboot Threshold</strong>: Conservative = 5, Aggressive = 2</li>
                <li><strong>Boot Timeout</strong>: Slow devices 120-180s, flagships 60-90s</li>
                <li><strong>Grace Period</strong>: Frequent module testers: 60-120s</li>
                <li><strong>Poll Interval</strong>: Default 2s is fine; auto-scales for long timeouts (v2.5)</li>
            </ol>

            <h3>🚨 Troubleshooting</h3>
            <p><strong>Rescue not triggered:</strong></p>
            <ul>
                <li>Check <code>ENABLED=true</code> in config.conf</li>
                <li>Check rescue.log for post-fs-data entries</li>
                <li>Confirm fail count reaches threshold</li>
            </ul>
            <p><strong>False rescue trigger:</strong></p>
            <ul>
                <li>Increase <code>USER_REBOOT_GRACE_SEC</code></li>
                <li>Enable <code>DRY_RUN</code> to verify</li>
                <li>Increase <code>REBOOT_THRESHOLD</code></li>
            </ul>

            <h3>⚠️ Disclaimer</h3>
            <p>The author is <strong>NOT responsible for any data loss or device damage</strong> resulting from use of this module. Use at your own risk.</p>
        `;
        this._showDocModal(this.t('usage_title'), html);
    }

    // === v2.7: 救砖审计日志 ===
    async loadAuditLog() {
        try {
            const raw = await this.exec(`cat "${this.stateDir}/rescue_audit.log" 2>/dev/null`, EXEC_DEFAULT_TIMEOUT_MS);
            const el = this.qs('#audit-log-content');
            if (!el) return;
            if (!raw || raw.trim() === '') {
                el.textContent = this.t('no_audit');
                return;
            }
            // Convert epoch timestamps to readable time
            const lines = raw.split('\n').filter(l => l.trim());
            const converted = lines.map(line => {
                const match = line.match(/^\[(\d+)\]\s*(.*)/);
                if (match && /^\d{10}$/.test(match[1])) {
                    const d = new Date(parseInt(match[1]) * 1000);
                    const timeStr = d.toLocaleString(this.lang === 'zh' ? 'zh-CN' : 'en-US');
                    return `[${timeStr}] ${match[2]}`;
                }
                return line;
            });
            el.textContent = converted.join('\n');
        } catch (e) {
            console.warn('loadAuditLog failed:', e);
        }
    }

    async refreshAuditLog() {
        await this.loadAuditLog();
        this.toast(this.t('refreshed'), 'success');
    }

    async copyAuditLog() {
        const el = this.qs('#audit-log-content');
        if (!el) return;
        const text = el.textContent || '';
        if (!text || text === this.t('no_audit')) {
            this.toast(this.t('no_content'), 'warn');
            return;
        }
        try {
            if (navigator.clipboard && navigator.clipboard.writeText) {
                await navigator.clipboard.writeText(text);
                this.toast(this.t('copied'), 'success');
                return;
            }
        } catch (e) { /* fallback */ }
        try {
            const ta = document.createElement('textarea');
            ta.value = text;
            ta.style.cssText = 'position:fixed;top:-9999px;left:-9999px;opacity:0;';
            document.body.appendChild(ta);
            ta.select();
            document.execCommand('copy');
            document.body.removeChild(ta);
            this.toast(this.t('copied'), 'success');
        } catch (e) {
            this.toast(this.t('copy_failed'), 'error');
        }
    }

    // === v2.7: 单模块启用/禁用切换 ===
    async toggleModule(modId, enable) {
        const action = enable ? 'enable' : 'disable';
        try {
            // Source common.sh to use toggle_single_module function
            const cmd = `. "${this.basePath}/common.sh" && toggle_single_module "${modId}" ${action}`;
            const result = await this.exec(cmd, EXEC_DEFAULT_TIMEOUT_MS);
            this.toast(enable ? `${modId} ${this.lang === 'zh' ? '已启用' : 'enabled'}` : `${modId} ${this.lang === 'zh' ? '已禁用' : 'disabled'}`);
            // Refresh module lists
            await Promise.all([this.loadModules(), this.loadDisabledModules()]);
        } catch (e) {
            this.toast(this.t('save_failed'), 'error');
        }
    }

    // === v2.7: 导出完整状态 ===
    async exportFullState() {
        try {
            const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
            const filepath = `/sdcard/Download/rescuex-full-state-${ts}.txt`;
            const cmd = `. "${this.basePath}/common.sh" && export_full_state "${filepath}"`;
            const result = await this.exec(cmd, EXEC_DEFAULT_TIMEOUT_MS);
            if (result.includes(filepath)) {
                await this.exec(`am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file://'${filepath}' 2>/dev/null`);
                this.toast((this.lang === 'zh' ? '已保存到 ' : 'Saved to ') + filepath, 'success', 5000);
            } else {
                this.toast(this.t('export_failed'), 'error');
            }
        } catch (e) {
            this.toast(this.t('export_failed'), 'error');
        }
    }

    // === v2.7.1: 自定义目录权限 ===
    async loadCustomDirs() {
        try {
            const raw = await this.exec(`cat "${this.customDirsFile}" 2>/dev/null`);
            const el = this.qs('#custom-dirs-list');
            if (!el) return;
            const entries = [];
            if (raw && raw.trim()) {
                raw.trim().split('\n').forEach(line => {
                    const parts = line.trim().split(/\s+/);
                    if (parts.length >= 2) {
                        const path = this.normalizeCustomDirPath(parts[0]);
                        entries.push({ path, perms: parts[1], valid: this.isSafeCustomDirPath(path) });
                    }
                });
            }
            this._customDirs = entries;
            this._renderCustomDirs();
            this.renderReadiness();
        } catch (e) {
            console.warn('loadCustomDirs failed:', e);
        }
    }

    _renderCustomDirs() {
        const el = this.qs('#custom-dirs-list');
        if (!el) return;
        const entries = this._customDirs || [];
        if (entries.length === 0) {
            el.innerHTML = `<div class="empty-state">${this.t('no_custom_dirs')}</div>`;
            return;
        }
        let html = '';
        entries.forEach((e, i) => {
            html += `<div class="custom-dir-row${e.valid === false ? ' invalid' : ''}">
                <input type="text" class="dir-path" value="${this.escapeHtml(e.path)}" placeholder="${this.t('dir_path')}">
                <select class="dir-perms">
                    <option value="770" ${e.perms === '770' ? 'selected' : ''}>770</option>
                    <option value="755" ${e.perms === '755' ? 'selected' : ''}>755</option>
                    <option value="700" ${e.perms === '700' ? 'selected' : ''}>700</option>
                    <option value="750" ${e.perms === '750' ? 'selected' : ''}>750</option>
                </select>
                <button class="btn-icon-del" data-action="removeCustomDir" data-index="${i}">&times;</button>
                ${e.valid === false ? `<div class="custom-dir-error">${this.escapeHtml(this.t('custom_dir_invalid'))}</div>` : ''}
            </div>`;
        });
        el.innerHTML = html;
    }

    addCustomDir() {
        if (!this._customDirs) this._customDirs = [];
        this._customDirs.push({ path: '', perms: '770', valid: true });
        this._renderCustomDirs();
    }

    async removeCustomDir(e, target) {
        const idx = parseInt(target.dataset.index);
        if (isNaN(idx) || !this._customDirs) return;
        this._customDirs.splice(idx, 1);
        this._renderCustomDirs();
    }

    async saveCustomDirs() {
        const rows = document.querySelectorAll('#custom-dirs-list .custom-dir-row');
        const entries = [];
        rows.forEach(row => {
            const pathInput = row.querySelector('.dir-path');
            const permsSelect = row.querySelector('.dir-perms');
            const path = this.normalizeCustomDirPath((pathInput && pathInput.value) || '');
            const perms = permsSelect ? permsSelect.value : '770';
            if (path) entries.push(`${path} ${perms}`);
        });
        this._customDirs = entries.map(e => {
            const parts = e.split(/\s+/);
            const path = this.normalizeCustomDirPath(parts[0]);
            return { path, perms: parts[1] || '770', valid: this.isSafeCustomDirPath(path) };
        });
        const invalid = this._customDirs.filter(e => e.valid === false).length;
        try {
            const safeEntries = this._customDirs.filter(e => e.valid).map(e => `${e.path} ${e.perms}`);
            const content = safeEntries.join('\n') || '';
            const b64 = utf8ToBase64(content + (content ? '\n' : ''));
            if (!/^[A-Za-z0-9+/=]*$/.test(b64)) {
                this.toast(this.t('save_failed'), 'error');
                return;
            }
            const result = await this.exec(`TMP_FILE="${this.stateDir}/.custom_dirs.upload.$$" && printf '%s' '${b64}' | base64 -d > "$TMP_FILE" && . "${this.basePath}/common.sh" && save_custom_dirs_file "$TMP_FILE" && rm -f "$TMP_FILE"`);
            if (result.includes('SAVED=')) {
                this.toast(this.t('saved'), 'success');
                if (invalid > 0) {
                    this.toast(this.t('custom_dir_rejected').replace('N', String(invalid)), 'warn', 5000);
                }
                await this.loadCustomDirs();
            } else {
                this.toast(this.t('save_failed'), 'error');
            }
        } catch (e) {
            this.toast(this.t('save_failed'), 'error');
        }
    }

    // === v2.7: 启动耗时趋势 ===
    async loadBootTrend() {
        try {
            const raw = await this.exec(`cat "${this.historyFile}" 2>/dev/null | grep SERVICE | tail -n 9`, EXEC_DEFAULT_TIMEOUT_MS);
            const el = this.qs('#boot-trend');
            if (!el) return;
            if (!raw || raw.trim() === '') {
                el.textContent = '--';
                return;
            }
            const lines = raw.trim().split('\n');
            let entries = [];
            for (const line of lines) {
                const durMatch = line.match(/duration=(\d+)s/);
                const timeMatch = line.match(/^\[(\d+)\]/);
                if (!durMatch) continue;
                const dur = parseInt(durMatch[1]);
                if (dur <= 0 || dur > 3600) continue;
                let label = '';
                if (timeMatch && /^\d{10}$/.test(timeMatch[1])) {
                    const d = new Date(parseInt(timeMatch[1]) * 1000);
                    label = `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`;
                }
                entries.push({ dur, label, raw: line });
            }
            if (entries.length === 0) {
                el.textContent = '--';
                return;
            }
            const maxDur = Math.max(...entries.map(e => e.dur));
            let html = '';
            for (const e of entries) {
                const pct = maxDur > 0 ? Math.round((e.dur / maxDur) * 100) : 100;
                const cls = e.dur >= 120 ? 'slow' : 'normal';
                html += `<div class="boot-trend-bar-wrap">
                    <span class="boot-trend-value">${e.dur}s</span>
                    <div class="boot-trend-bar ${cls}" style="height:${pct}%"></div>
                    <span class="boot-trend-label">${e.label}</span>
                </div>`;
            }
            el.innerHTML = html;
        } catch (e) {
            console.warn('loadBootTrend failed:', e);
        }
    }

    // === v3.0.1: 嫌疑模块追踪面板 ===
    async loadSuspectModules() {
        try {
            const modulesRaw = await this.exec(`. "${this.basePath}/common.sh" && list_all_modules | cut -d'|' -f1,2`, EXEC_DEFAULT_TIMEOUT_MS);
            const currentModules = modulesRaw.split('\n').map(line => line.trim()).filter(Boolean).map(line => {
                const parts = line.split('|');
                return { id: parts[0], enabled: parts[1] === '1' };
            }).filter(item => item.id);
            const currentModuleIds = new Set(currentModules.map(item => item.id));
            const enabledCount = currentModules.filter(item => item.enabled).length;
            const totalCount = currentModules.length;
            this.setText('#info-good-modules', enabledCount);
            this.goodModuleStats = { enabled: enabledCount, total: totalCount };

            // Load suspect log
            const suspectRaw = await this.exec(`cat "${this.stateDir}/suspect_modules.log" 2>/dev/null`);
            const el = this.qs('#suspect-list');
            if (!el) return;

            if (!suspectRaw || suspectRaw.trim() === '' || suspectRaw.trim().startsWith('#')) {
                el.innerHTML = `<div class="empty-state">${totalCount > 0 ? (this.lang === 'zh' ? '暂无嫌疑记录（已知良好模块已建立）' : 'No suspects (good module list is established)') : this.t('loading')}</div>`;
                this.setText('#info-suspect-count', 0);
                this.renderReadiness();
                return;
            }

            const suspects = suspectRaw.split('\n').filter(l => l.trim() && !l.trim().startsWith('#')).filter(line => {
                const clean = line.replace(/^[?+:]/, '').trim();
                return clean && currentModuleIds.has(clean);
            });
            const certain = suspects.filter(s => !s.startsWith('?') && !s.startsWith('+'));
            const stateChanged = suspects.filter(s => s.startsWith('+'));
            const uncertain = suspects.filter(s => s.startsWith('?'));

            this.setText('#info-suspect-count', certain.length + stateChanged.length);

            if (suspects.length === 0) {
                el.innerHTML = `<div class="empty-state">${this.lang === 'zh' ? '无嫌疑模块' : 'No suspect modules'}</div>`;
                this.renderReadiness();
                return;
            }

            let html = '';
            certain.forEach(s => {
                const name = this.escapeHtml(s);
                html += `<div class="suspect-module-item">
                    <span class="suspect-icon">&#9888;</span>
                    <div class="suspect-info"><div class="suspect-name">${name}</div></div>
                    <span class="module-tag disabled">${this.lang === 'zh' ? '嫌疑' : 'Suspect'}</span>
                </div>`;
            });
            stateChanged.forEach(s => {
                const name = this.escapeHtml(s.substring(1)); // strip + prefix
                html += `<div class="suspect-module-item" style="opacity:0.85;">
                    <span class="suspect-icon">&#8635;</span>
                    <div class="suspect-info"><div class="suspect-name">${name}</div></div>
                    <span class="suspect-uncertain-tag">${this.lang === 'zh' ? '状态变化' : 'Changed'}</span>
                </div>`;
            });
            uncertain.forEach(s => {
                const name = this.escapeHtml(s.substring(1)); // strip ? prefix
                html += `<div class="suspect-module-item suspect-uncertain">
                    <span class="suspect-icon">?</span>
                    <div class="suspect-info"><div class="suspect-name">${name}</div></div>
                    <span class="suspect-uncertain-tag">${this.lang === 'zh' ? '参考' : 'Ref'}</span>
                </div>`;
            });
            el.innerHTML = html;
            this.renderReadiness();
        } catch (e) {
            console.warn('loadSuspectModules failed:', e);
        }
    }

    // === v3.0.1: 救砖级别展示 ===
    async loadRescueLevel() {
        try {
            const raw = await this.exec(`cat "${this.stateDir}/rescue_level" 2>/dev/null`);
            const level = parseInt(raw) || 0;
            const badge = this.qs('#rescue-level-badge');
            if (!badge) return;

            const levelLabels = {
                0: this.t('rescue_level_0'),
                1: this.t('rescue_level_1'),
                2: this.t('rescue_level_2')
            };
            const levelClasses = {
                0: 'rescue-level-badge-l0',
                1: 'rescue-level-badge-l1',
                2: 'rescue-level-badge-l2'
            };

            badge.textContent = levelLabels[level] || this.t('rescue_level_label');
            badge.className = `badge ${levelClasses[level] || 'badge-info'}`;
            this.rescueLevel = level;
            this.renderReadiness();
        } catch (e) {
            console.warn('loadRescueLevel failed:', e);
        }
    }

    async saveGoodModules() {
        try {
            const result = await this.exec(`. "${this.basePath}/common.sh" && manual_save_good_modules`);
            if (result) {
                this.toast(this.t('good_modules_saved') + (result !== '0' ? ` (${result})` : ''), 'success');
                await Promise.all([this.loadSuspectModules(), this.loadRescueLevel()]);
            } else {
                this.toast(this.t('save_failed'), 'error');
            }
        } catch (e) {
            this.toast(this.t('save_failed'), 'error');
        }
    }

    async clearSuspectLog() {
        try {
            await this.exec(`. "${this.basePath}/common.sh" && clear_suspect_log`);
            this.toast(this.t('suspect_cleared'), 'success');
            await this.loadSuspectModules();
        } catch (e) {
            this.toast(this.t('save_failed'), 'error');
        }
    }

    async resetRescueLevel() {
        try {
            await this.exec(`. "${this.basePath}/common.sh" && reset_rescue_level_state`);
            this.toast(this.t('rescue_level_reset'), 'success');
            await this.loadRescueLevel();
        } catch (e) {
            this.toast(this.t('save_failed'), 'error');
        }
    }

    // === v3.0.1: APP 解冻 ===
    async unfreezeApps() {
        const confirm = await this.confirmDialog(
            this.t('confirm_title'),
            this.t('unfreeze_confirm'),
            this.t('btn_confirm'), 'btn-danger'
        );
        if (!confirm) return;
        this.showLoading(true);
        try {
            const result = await this.exec(`. "${this.basePath}/common.sh" && manual_unfreeze_apps`);
            if (result.includes('DONE')) {
                this.toast(this.t('unfreeze_done'), 'success');
            } else {
                this.toast(this.t('unfreeze_skip'), 'warn');
            }
        } catch (e) {
            this.toast(this.t('save_failed'), 'error');
        }
        this.showLoading(false);
    }

    // === v3.0.1: 锁定脚本目录 ===
    async lockScriptDirs() {
        const confirm = await this.confirmDialog(
            this.t('confirm_title'),
            this.t('lock_scripts_confirm'),
            this.t('btn_confirm'), 'btn-danger'
        );
        if (!confirm) return;
        this.showLoading(true);
        try {
            const result = await this.exec(`. "${this.basePath}/common.sh" && manual_lock_script_dirs`);
            this.toast(this.t('lock_scripts_done'), 'success');
        } catch (e) {
            this.toast(this.t('save_failed'), 'error');
        }
        this.showLoading(false);
    }

    // === Modal ===
    confirmDialog(title, message, okText, okClass) {
        return new Promise(resolve => {
            const overlay = document.createElement('div');
            overlay.className = 'modal-overlay';
            const modal = document.createElement('div');
            modal.className = 'modal';
            const h3 = document.createElement('h3');
            h3.textContent = title;
            const p = document.createElement('p');
            p.textContent = message;
            const btns = document.createElement('div');
            btns.className = 'modal-buttons';
            const cancel = document.createElement('button');
            cancel.className = 'btn btn-text';
            cancel.textContent = this.t('btn_cancel');
            const ok = document.createElement('button');
            ok.className = `btn ${okClass || 'btn-filled'}`;
            ok.textContent = okText || this.t('btn_confirm');
            btns.appendChild(cancel);
            btns.appendChild(ok);
            modal.appendChild(h3);
            modal.appendChild(p);
            modal.appendChild(btns);
            overlay.appendChild(modal);
            document.body.appendChild(overlay);

            const close = (result) => { overlay.remove(); resolve(result); };
            cancel.onclick = () => close(false);
            ok.onclick = () => close(true);
            overlay.onclick = (e) => { if (e.target === overlay) close(false); };
            // 键盘支持
            overlay.tabIndex = -1;
            overlay.focus();
            overlay.onkeydown = (e) => {
                if (e.key === 'Enter') close(true);
                else if (e.key === 'Escape') close(false);
            };
            setTimeout(() => ok.focus(), 50);
        });
    }
}

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => new RescueXUI());
} else {
    new RescueXUI();
}

})();
