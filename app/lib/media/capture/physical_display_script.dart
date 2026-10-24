/// 短启动命令只收取脚本；完整脚本和后续协议共用原始 ADB 流。
/// 在分隔行之前不执行脚本，也不修改被控设备。
const physicalDisplayBootstrap = r'''program=
complete=
while IFS= read -r line; do
    if [ "$line" = '__INTEROP_DISPLAY_PROGRAM_END__' ]; then complete=1; break; fi
    program="$program$line
"
done
[ "$complete" = 1 ] || exit 40
eval "$program"''';

/// 物理显示属于应用窗口；远端记录独立于任何一代视频捕获。
String physicalDisplayProgram({
  required String owner,
  required int width,
  required int height,
}) {
  _validateOwner(owner);
  if (width < 320 || width > 4096 || height < 320 || height > 4096) {
    throw ArgumentError('物理显示宽高必须在 320 至 4096 之间。');
  }
  return '''$_common
expected_owner='$owner'
desired_width=$width
desired_height=$height
$_main''';
}

/// 恢复也通过短启动命令和标准输入发送，不能内联进 Android 21 的 OPEN。
String recoverPhysicalDisplayCommand(String owner) {
  _validateOwner(owner);
  return '''$_common
expected_owner='$owner'
$_recovery''';
}

/// 在同一远端锁内发现当前租约，调用方确认精确 owner 后才允许恢复。
/// 没有发现回执便不会执行恢复；发现后重试必须改用精确 owner 的恢复命令。
String recoverCurrentPhysicalDisplayCommand(String request) {
  _validateOwner(request);
  return '''$_common
expected_owner='$request'
$_recoverCurrent''';
}

/// 主机已持有恢复终态后才确认回收，避免每次窗口永久遗留远端回执。
/// 确认丢失可重试；这条命令不执行或推定显示恢复。
String acknowledgePhysicalDisplayCommand(String owner) {
  _validateOwner(owner);
  return '''$_common
expected_owner='$owner'
$_acknowledge''';
}

void _validateOwner(String owner) {
  if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(owner)) {
    throw ArgumentError.value(owner, 'owner', '显示租约标识必须为 32 位小写十六进制。');
  }
}

String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";

// 每个请求先拥有独立记录，再允许 worker 发布身份和接收 GO。
// 即使父 shell 在发布前死亡，恢复者也可封存请求；迟到 worker 无权执行。
const _worker = r'''lease=$1
token=$2
request=$3
expected_gate=$4
desired=$5
parent_pid=$6
parent_started=$7
restore=$8
trap '' HUP INT TERM USR1 USR2 PIPE
parent_alive() {
    IFS= read -r stat < "/proc/$parent_pid/stat" || return 1
    fields=${stat##*) }; set -- $fields
    case "$1" in Z|X|x|'') return 1 ;; esac
    shift 19 || return 1
    [ "$1" = "$parent_started" ]
}
allowed() {
    [ ! -e "$request/abort" ] || return 1
    IFS= read -r current < "$lease/current" || return 1
    [ "$current" = "$token" ] || return 1
    IFS= read -r held < "$lease/gate/holder" || return 1
    [ "$held" = "$expected_gate" ] || return 1
    if [ "$restore" != 1 ]; then [ ! -e "$lease/owners/$token/closing" ] || return 1; fi
}
allowed && parent_alive || exit 41
IFS= read -r stat < "/proc/$$/stat" || exit 45
fields=${stat##*) }; set -- $fields; shift 19 || exit 45
printf '%s:%s\n' "$$" "$1" > "$request/identity.tmp" || exit 43
mv "$request/identity.tmp" "$request/identity" || exit 43
while :; do
    allowed && parent_alive || exit 41
    go=
    if [ -f "$request/go" ]; then IFS= read -r go < "$request/go"; fi
    if [ "$go" = "$expected_gate" ]; then break; fi
    sleep .01
done
allowed || exit 41
exec wm size "$desired"''';

final _common =
    '''$_commonBeforeWorker
worker_program=${_quote(_worker)}
$_commonAfterWorker''';

const _commonBeforeWorker = r'''lease=/data/local/tmp/interop-display-0
gate_identity=
gate_held=
sequence=0
valid_owner() {
    [ "${#1}" = 32 ] || return 1
    case "$1" in *[!0-9a-f]*) return 1 ;; esac
}
valid_size() {
    case "$1" in reset) return 0 ;; ''|*[!0-9x]*|x*|*x) return 1 ;; esac
    width=${1%x*}; height=${1#*x}
    case "$width:$height" in *x*|*[!0-9:]*) return 1 ;; esac
    [ "$width" -gt 0 ] && [ "$height" -gt 0 ]
}
error() { printf '%s\n' "__DISPLAY_ERROR__$expected_owner:$1" >&2; }
read_file() { IFS= read -r value < "$1"; }
# 标识与版本只接受单个完整行，不将尾随内容截断为有效身份。
read_exact_file() {
    [ -f "$1" ] && [ ! -L "$1" ] || return 1
    {
        IFS= read -r value || return 1
        extra=
        if IFS= read -r extra || [ -n "$extra" ]; then return 1; fi
    } < "$1"
    return 0
}
write_file() {
    printf '%s\n' "$2" > "$1.tmp-$$" && mv "$1.tmp-$$" "$1"
}
# 0 为同一活进程，1 为已退出或 PID 已复用，2 为无法核验。
identity_alive() {
    identity=$1
    pid=${identity%%:*}; started=${identity#*:}
    case "$pid:$started" in *[!0-9:]*|:*|*:|*:*:*) return 2 ;; esac
    if ! IFS= read -r stat < "/proc/$pid/stat"; then
        [ ! -d "/proc/$pid" ] && return 1
        return 2
    fi
    fields=${stat##*) }; set -- $fields
    case "$1" in Z|X|x) return 1 ;; '') return 2 ;; esac
    shift 19 || return 2
    [ "$1" = "$started" ] && return 0
    return 1
}
own_identity() {
    IFS= read -r stat < "/proc/$$/stat" || return 1
    fields=${stat##*) }; set -- $fields; shift 19 || return 1
    own_started=$1
    case "$own_started" in ''|*[!0-9]*) return 1 ;; esac
    gate_identity="$expected_owner:$$:$own_started"
}
ensure_root() {
    if mkdir "$lease" 2>/dev/null; then
        mkdir "$lease/owners" || return 1
        write_file "$lease/format" interop-display-v1 || return 1
    fi
    [ -d "$lease" ] && [ ! -L "$lease" ] || return 1
    read_file "$lease/format" && [ "$value" = interop-display-v1 ] || return 1
    [ -d "$lease/owners" ] && [ ! -L "$lease/owners" ]
}
publish_gate() {
    write_file "$lease/gate/holder" "$gate_identity" || return 1
    gate_held=1
}
release_gate() {
    if [ "$gate_held" = 1 ] && read_file "$lease/gate/holder" && [ "$value" = "$gate_identity" ]; then
        rm -f "$lease/gate/holder"
        rmdir "$lease/gate" 2>/dev/null
    fi
    gate_held=
}
take_gate() {
    [ ! -e "$lease/reaper" ] && [ ! -L "$lease/reaper" ] || return 1
    if mkdir "$lease/gate" 2>/dev/null; then
        publish_gate || return 1
        # 陈旧锁回收者可能在 mkdir 之前取得封存权；此时不能执行任何修改。
        if [ -e "$lease/reaper" ] || [ -L "$lease/reaper" ]; then release_gate; return 1; fi
        return 0
    fi
    [ -d "$lease/gate" ] && [ ! -L "$lease/gate" ] || return 1
    read_file "$lease/gate/holder" || return 1
    observed=$value
    old_identity=${observed#*:}
    valid_owner "${observed%%:*}" || return 1
    identity_alive "$old_identity"; state=$?
    [ "$state" = 1 ] || return 1
    # 两个回收者不能通过先比较再删除，误删对方或后继的新锁。
    # 匿名或死亡的回收者不自动猜测性接管，保留未知责任。
    mkdir "$lease/reaper" 2>/dev/null || return 1
    if ! read_file "$lease/gate/holder" || [ "$value" != "$observed" ]; then
        rmdir "$lease/reaper"; return 1
    fi
    identity_alive "$old_identity"; state=$?
    if [ "$state" != 1 ]; then rmdir "$lease/reaper"; return 1; fi
    rm -f "$lease/gate/holder" && rmdir "$lease/gate" || { rmdir "$lease/reaper"; return 1; }
    if ! mkdir "$lease/gate" 2>/dev/null; then rmdir "$lease/reaper"; return 1; fi
    publish_gate || { rmdir "$lease/reaper"; return 1; }
    rmdir "$lease/reaper" || return 1
}
read_override() {
    override=reset
    report=$(wm size) || return 1
    physical=
    while IFS= read -r line; do
        case "$line" in
            'Physical size: '*) physical=${line#'Physical size: '} ;;
            'Override size: '*) override=${line#'Override size: '} ;;
        esac
    done <<INTEROP_SIZE
$report
INTEROP_SIZE
    [ -n "$physical" ] && valid_size "$physical" && valid_size "$override"
}
natural_size() {
    report=$(dumpsys input) || return 1
    rotation=
    while IFS= read -r line; do
        case "$line" in
            *'Viewport:'*displayId=0,*orientation=*|*'Viewport '*displayId=0,*orientation=*)
                rotation=${line#*orientation=}; rotation=${rotation%%,*}; break ;;
        esac
    done <<INTEROP_ROTATION
$report
INTEROP_ROTATION
    case "$rotation" in
        0|2) natural=$desired_width'x'$desired_height ;;
        1|3) natural=$desired_height'x'$desired_width ;;
        *) return 1 ;;
    esac
}
record_for() {
    token=$1
    valid_owner "$token" || return 1
    record="$lease/owners/$token"
    [ -d "$record" ] && [ ! -L "$record" ] || return 1
    read_exact_file "$record/owner" && [ "$value" = "$token" ]
}
read_done() {
    [ -f "$record/done" ] || return 1
    read_exact_file "$record/done" || return 1
    case "$value" in restored|preserved) outcome=$value ;; *) return 1 ;; esac
}
emit_done() { printf '__DISPLAY_DONE__%s:%s\n' "$token" "$outcome"; }
drain_requests() {
    [ -d "$record/requests" ] || return 1
    for request in "$record"/requests/*; do
        [ -e "$request" ] || continue
        [ -d "$request" ] && [ ! -L "$request" ] || return 1
        : > "$request/abort" || return 1
        # 没有身份就不可能得到 GO；迟到发布仍受 abort 和当前 owner 限制。
        if [ ! -f "$request/identity" ]; then continue; fi
        read_file "$request/identity" || return 1
        worker_identity=$value
        attempts=0
        while :; do
            identity_alive "$worker_identity"; state=$?
            [ "$state" = 1 ] && break
            [ "$state" = 0 ] || return 1
            [ "$attempts" -lt 100 ] || return 1
            attempts=$((attempts + 1)); sleep .05
        done
    done
}
''';

const _commonAfterWorker = r'''run_worker() {
    desired=$1
    restoring=$2
    sequence=$((sequence + 1))
    request="$record/requests/$$-$own_started-$sequence"
    mkdir "$request" || return 1
    /system/bin/sh -c "$worker_program" interop-wm "$lease" "$token" "$request" "$gate_identity" "$desired" "$$" "$own_started" "$restoring" >&2 &
    worker_pid=$!
    attempts=0
    while :; do
        if read_file "$request/identity" 2>/dev/null; then
            case "$value" in "$worker_pid":*) break ;; *) return 1 ;; esac
        fi
        [ "$attempts" -lt 200 ] || return 1
        attempts=$((attempts + 1)); sleep .01
    done
    write_file "$request/go" "$gate_identity" || return 1
    wait "$worker_pid" || return 1
    # wait 已证实该精确 worker 结束；迟到交付的请求仍保留，成功请求及时回收。
    rm -rf "$request"
}
restore_record() {
    read_file "$lease/current" && [ "$value" = "$token" ] || return 1
    read_file "$record/main" || return 1
    main_identity=$value
    if [ "$main_identity" != "$$:$own_started" ]; then
        identity_alive "$main_identity"; state=$?
        [ "$state" = 1 ] || return 1
    fi
    : > "$record/closing" || return 1
    drain_requests || return 1
    read_file "$record/original" || return 1
    original=$value; valid_size "$original" || return 1
    read_file "$record/target" || return 1
    target=$value; valid_size "$target" || return 1
    pending=
    if [ -f "$record/pending" ]; then
        read_file "$record/pending" || return 1
        pending=$value; valid_size "$pending" || return 1
    fi
    read_file "$record/ran" || return 1
    ran=$value
    case "$ran" in 0|1) ;; *) return 1 ;; esac
    read_override || return 1
    outcome=preserved
    if [ "$override" = "$original" ]; then
        outcome=restored
    elif [ "$ran" = 1 ] && { [ "$override" = "$target" ] || [ "$override" = "$pending" ]; }; then
        run_worker "$original" 1 || return 1
        read_override && [ "$override" = "$original" ] || return 1
        outcome=restored
    elif [ -n "$pending" ]; then
        # 系统可能截断或改变请求值，不能把未核验的写入误认成外部修改。
        # 保留基线和 pending；无法证明来源时既不覆盖当前值，也不发布 DONE。
        return 1
    fi
    # 恢复/外部修改核验完成后才发布持久终态，丢回执可读同一结果。
    write_file "$record/done" "$outcome"
}
recover_previous() {
    record_for "$1" || return 1
    if [ -e "$record/done" ] || [ -L "$record/done" ]; then
        read_done; return $?
    fi
    restore_record
}
apply_size() {
    natural_size || return 1
    if [ -f "$record/closing" ]; then return 1; fi
    read_file "$record/target" || return 1
    target=$value
    read_override || return 1
    # 首次 RUN 也必须核对 START 时的基线，不能覆盖等待授权期间的外部修改。
    [ "$override" = "$target" ] || return 1
    # Android 21 会逐轴截断到物理尺寸两倍；在发送前拒绝已知会被改写的请求。
    physical_width=${physical%x*}; physical_height=${physical#*x}
    natural_width=${natural%x*}; natural_height=${natural#*x}
    [ "$natural_width" -le "$((physical_width * 2))" ] &&
    [ "$natural_height" -le "$((physical_height * 2))" ] || return 1
    write_file "$record/pending" "$natural" || return 1
    write_file "$record/ran" 1 || return 1
    run_worker "$natural" 0 || return 1
    read_override && [ "$override" = "$natural" ] || return 1
    write_file "$record/target" "$natural" || return 1
    rm -f "$record/pending"
}
''';

const _main = r'''IFS= read -r start || exit 40
[ "$start" = "START:$expected_owner" ] || exit 40
own_identity || { error identity_unknown; exit 45; }
ensure_root || { error lease_unknown; exit 43; }
take_gate || { error lease_busy; exit 41; }
trap 'release_gate' EXIT
previous=
if [ -f "$lease/current" ]; then
    read_file "$lease/current" || { error lease_unknown; exit 43; }
    previous=$value
    if ! recover_previous "$previous"; then error recovery_unconfirmed; exit 43; fi
fi
token=$expected_owner
record="$lease/owners/$token"
if [ -e "$record" ]; then error owner_reused; exit 41; fi
mkdir "$record" && mkdir "$record/requests" || { error lease_unknown; exit 43; }
read_override || { error baseline_unknown; exit 43; }
original=$override
natural_size || { error rotation_unknown; exit 44; }
write_file "$record/owner" "$token" &&
write_file "$record/main" "$$:$own_started" &&
write_file "$record/original" "$original" &&
write_file "$record/target" "$original" &&
write_file "$record/ran" 0 &&
write_file "$lease/current" "$token" || { error lease_unknown; exit 43; }
finishing=
finish() {
    status=$1
    [ "$finishing" != 1 ] || exit 43
    finishing=1
    trap - EXIT
    trap '' HUP INT TERM USR1 USR2 PIPE
    token=$expected_owner
    record="$lease/owners/$token"
    if restore_record; then
        release_gate
        emit_done || :
        exit "$status"
    fi
    release_gate
    error cleanup_unconfirmed
    exit 43
}
trap 'finish $?' EXIT
trap 'finish 129' HUP USR1
trap 'finish 130' INT
trap 'finish 143' TERM
trap 'finish 141' PIPE
printf '__DISPLAY_OWNER__%s:%s:%s\n' "$token" "$$" "$own_started"
IFS= read -r run || exit 0
[ "$run" = "RUN:$token" ] || {
    [ "$run" = "STOP:$token" ] && exit 0
    error invalid_run; exit 40
}
apply_size || { error apply_unconfirmed; exit 43; }
printf '__DISPLAY_READY__%s:%s:%s\n' "$token" "$desired_width" "$desired_height"
last_resize_sequence=0
while IFS= read -r action; do
    case "$action" in
        "STOP:$token") exit 0 ;;
        "RESIZE:$token:"*)
            resize=${action#"RESIZE:$token:"}
            resize_sequence=${resize%%:*}; dimensions=${resize#*:}
            case "$resize_sequence" in ''|0*|*[!0-9]*) error invalid_sequence; exit 40 ;; esac
            [ "$resize_sequence" -gt "$last_resize_sequence" ] || { error invalid_sequence; exit 40; }
            last_resize_sequence=$resize_sequence
            desired_width=${dimensions%%:*}; desired_height=${dimensions#*:}
            case "$desired_width:$desired_height" in *[!0-9:]*|:*|*:|*:*:*) error invalid_size; exit 40 ;; esac
            [ "$desired_width" -ge 320 ] && [ "$desired_width" -le 4096 ] &&
            [ "$desired_height" -ge 320 ] && [ "$desired_height" -le 4096 ] || { error invalid_size; exit 40; }
            apply_size || { error resize_unconfirmed; exit 43; }
            printf '__DISPLAY_SIZE__%s:%s:%s:%s\n' "$token" "$resize_sequence" "$desired_width" "$desired_height"
            ;;
        *) error invalid_action; exit 40 ;;
    esac
done
exit 0''';

const _recovery = r'''own_identity || { error identity_unknown; exit 45; }
[ -d "$lease" ] && [ ! -L "$lease" ] || { error lease_missing; exit 43; }
read_file "$lease/format" && [ "$value" = interop-display-v1 ] || { error lease_unknown; exit 43; }
record_for "$expected_owner" || { error owner_unknown; exit 43; }
if [ -e "$record/done" ] || [ -L "$record/done" ]; then
    read_done || { error done_unknown; exit 43; }
    emit_done; exit 0
fi
take_gate || { error lease_busy; exit 41; }
trap 'release_gate' EXIT
record_for "$expected_owner" && restore_record || { error cleanup_unconfirmed; exit 43; }
emit_done
exit 0''';

const _acknowledge =
    r'''emit_ack() { printf '__DISPLAY_ACK__%s\n' "$expected_owner"; }
if [ ! -e "$lease" ]; then emit_ack; exit 0; fi
[ -d "$lease" ] && [ ! -L "$lease" ] || { error lease_unknown; exit 43; }
read_file "$lease/format" && [ "$value" = interop-display-v1 ] || { error lease_unknown; exit 43; }
if [ ! -e "$lease/owners/$expected_owner" ]; then
    if [ -f "$lease/current" ]; then
        read_file "$lease/current" || { error lease_unknown; exit 43; }
        [ "$value" != "$expected_owner" ] || { error owner_unknown; exit 43; }
    fi
    emit_ack
    exit 0
fi
own_identity || { error identity_unknown; exit 45; }
take_gate || { error lease_busy; exit 41; }
trap 'release_gate' EXIT
record_for "$expected_owner" && read_done || { error done_unconfirmed; exit 43; }
if [ -f "$lease/current" ]; then
    read_file "$lease/current" || { error lease_unknown; exit 43; }
    # 先清当前引用，崩溃时残留 DONE 仍能再次精确确认；不可遗留悬空当前引用。
    if [ "$value" = "$expected_owner" ]; then rm -f "$lease/current" || exit 43; fi
fi
rm -rf "$record" || { error cleanup_unconfirmed; exit 43; }
emit_ack
exit 0''';

// 发现与恢复之间保持同一 gate。授权丢失或流关闭只释放 gate，不猜测旧责任。
const _recoverCurrent = r'''if [ ! -e "$lease" ] && [ ! -L "$lease" ]; then
    printf '__DISPLAY_CURRENT__%s:empty\n' "$expected_owner"
    exit 0
fi
[ -d "$lease" ] && [ ! -L "$lease" ] || exit 43
read_exact_file "$lease/format" && [ "$value" = interop-display-v1 ] || exit 43
[ -d "$lease/owners" ] && [ ! -L "$lease/owners" ] || exit 43
own_identity && take_gate || { error busy_or_unknown; exit 41; }
trap 'release_gate' EXIT
trap 'exit 43' HUP INT TERM PIPE
if [ ! -e "$lease/current" ] && [ ! -L "$lease/current" ]; then
    printf '__DISPLAY_CURRENT__%s:empty\n' "$expected_owner"
    exit 0
fi
[ -f "$lease/current" ] && [ ! -L "$lease/current" ] || exit 43
read_exact_file "$lease/current" && record_for "$value" || { error invalid_current; exit 43; }
if [ -e "$record/done" ] || [ -L "$record/done" ]; then
    read_exact_file "$record/done" || exit 43
    case "$value" in restored|preserved) ;; *) exit 43 ;; esac
fi
# 严格验证 main/worker 与基线由原 restore_record 完成；在此之前不改覆盖。
printf '__DISPLAY_CURRENT__%s:%s\n' "$expected_owner" "$token"
IFS= read -r authorization || exit 43
[ "$authorization" = "RECOVER:$expected_owner:$token" ] || exit 43
if ! read_done; then restore_record || { error restore_unconfirmed; exit 43; }; fi
emit_done
exit 0''';
