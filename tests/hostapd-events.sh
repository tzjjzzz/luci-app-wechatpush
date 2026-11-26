#!/usr/bin/env bash
# Run from the repository root with bash and jq.
source <(sed '$d' root/usr/share/wechatpush/wechatpush)
dir=$(mktemp -d) || exit 1
trap 'rm -rf "$dir"' EXIT
mkdir "$dir/ap-notify"
mkfifo "$dir/pipe" "$dir/tokens" || exit 1
exec 8<>"$dir/pipe" 5<>"$dir/tokens"
echo >&5
if [[ -n $jqbin ]]; then jq(){ "$jqbin" -b "$@"; }; fi
fail(){ echo "FAIL: $*" >&2; exit 1; }
translate(){ local fmt=$1; shift; printf "$fmt" "$@"; }
ap_streams_healthy(){ return 0; }
ensure_ap_listeners(){ :; }
ubus(){ echo "$*" >>"$dir/ubus"; return 1; }
op_ssh(){ echo "$*" >>"$dir/ssh"; return 1; }
getmac(){ jq -r --arg ip "$1" '.devices[]|select(.ip==$ip)|.mac' "$devices_json"; }
getname(){ echo phone; }
getinterface(){ echo br-lan; }
blackwhitelist(){ return 0; }
disturb(){ return 0; }
named(){ echo "$1"; }
usage(){ :; }
current_device(){ :; }
diy_send(){ printf '%s\n' "$1" >>"$dir/messages"; }
getgateway(){ :; }; getmiwifi(){ :; }; getmikrotik(){ :; }; getwireguard(){ :; }
logfile=$dir/log; devices_json=$dir/devices; tmp_devices_json=$dir/devices.tmp; lock_file=$dir/lock
log_scan=1
declare -A ap_log_batch ap_lease_retry ap_source ap_iface ap_dirty ap_departure ap_health ap_mac ap_band ap_ip_hint ap_radio_band tx_previous tx_active
ap_listener=$BASHPID; ap_refresh_at=100000; ap_incomplete=0
offline_detect_method=hostapd_listen; notification_online=1; notification_offline=1
sleeptime=2; down_timeout=1; up_timeout=1; timeout_retry_count=1
mac1=02:00:00:00:00:01; ip1=192.0.2.1; wired=192.0.2.2
event(){ printf '@%s daemon.info hostapd: %s: AP-STA-%s %s\n' "$1" "$2" "$3" "$mac1"; }
echo '{"devices":[]}' >"$devices_json"
ap_ip_hint[$mac1]=$ip1
record_ap_event "$(event routerA wlan0 CONNECTED)"; apply_ap_events
jq -e '.devices[0].hostapd_source=="routerA"' "$devices_json" >/dev/null || fail join
[[ $(wc -l <"$dir/messages") = 1 ]] || fail join-notified
# Duplicate events and an old BSS departure after a roam.
{
 for ((i=0;i<150;i++)); do event routerA wlan0 DISCONNECTED; event routerA wlan0 CONNECTED; done
 event routerB wlan0 CONNECTED; event routerA wlan0 DISCONNECTED
} >&8 &
producer=$!
wait_ap_events
wait "$producer"
jq -e '.devices[0].hostapd_source=="routerB" and .devices[0].status=="online"' "$devices_json" >/dev/null || fail roam
[[ $(wc -l <"$dir/messages") = 1 && ! -e $dir/ubus && ! -e $dir/ssh ]] || fail burst
echo 'PASS 302 station events, cross-AP roam, no duplicate push or AP queries'
# Distinct clients roam together; all rows survive the batched DB update.
for ((i=3;i<=34;i++)); do
	printf -v station '02:00:00:00:00:%02x' "$i"
	printf '%s %s\n' "$station" "192.0.2.$i"
done >"$dir/stations"
jq -Rn --slurpfile db "$devices_json" '$db[0] | .devices += [inputs | split(" ") |
	{mac:.[0],ip:.[1],status:"online",hostapd_source:"routerA"}]' <"$dir/stations" >"$dir/new" && mv "$dir/new" "$devices_json"
while read -r station addr; do
	record_ap_event "@routerB daemon.info hostapd: wlan1: AP-STA-CONNECTED $station"
	record_ap_event "@routerA daemon.info hostapd: wlan0: AP-STA-DISCONNECTED $station"
done <"$dir/stations"
apply_ap_events
jq -e '(.devices|length)==33 and all(.devices[]; .hostapd_source=="routerB")' "$devices_json" >/dev/null || fail simultaneous-roams
[[ $(wc -l <"$dir/messages") = 1 && ! -e $dir/ubus && ! -e $dir/ssh ]] || fail simultaneous-push
jq --arg ip "$ip1" '.devices |= map(select(.ip==$ip))' "$devices_json" >"$dir/new" && mv "$dir/new" "$devices_json"
while read -r station addr; do unset 'ap_source[$station]' 'ap_iface[$station]' 'ap_mac[$addr]'; done <"$dir/stations"
echo 'PASS 32 simultaneous client roams without queries or notifications'
# Release a slow wired probe only once the actual notification dispatcher runs.
run_with_tag(){
 if [[ ${!#} = "$wired" ]]; then
  : >"$dir/probing"
  for ((k=0;k<200;k++)); do
   [[ $(wc -l <"$dir/messages") -gt 1 ]] && return 1
   sleep .1
  done
  touch "$dir/probe-timed-out"
 fi
 return 1
}
always_check_ip_list=$wired
(
 for ((i=0;i<150;i++)); do [[ -f $dir/probing ]] && break; sleep .1; done
 event routerB wlan0 DISCONNECTED >&8
) &
sender=$!
echo "#mac,ip,in,out,total" >"$dir/usage.db"
echo "$mac1,$ip1,0,123,123" >>"$dir/usage.db"
first
wait "$sender"
[[ ! -f $dir/probe-timed-out && -f $dir/probing ]] || fail blocked-notification
[[ $(wc -l <"$dir/messages") = 2 ]] || fail departure-notified
jq -e '.devices==[]' "$devices_json" >/dev/null || fail offline
sed -i 's/123/456/g' "$dir/usage.db"; collect_tx_activity
[[ -z ${tx_active[$ip1]} ]] || fail stale-upload
[[ ! -e $dir/ubus && ! -e $dir/ssh ]] || fail event-rescan
echo 'PASS disconnect pushed during slow wired probe, old upload baseline discarded'
