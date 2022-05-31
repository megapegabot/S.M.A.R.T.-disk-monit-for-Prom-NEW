#!/bin/bash
# Script informed by the collectd monitoring script for smartmontools (using smartctl)
# by Samuel B. <samuel_._behan_(at)_dob_._sk> (c) 2012
#
# Update by Stanislav Rychkov <github:megapegabot> 2022
# add support NVME, SSD + SMART NVME



parse_smartctl_attributes_awk="$(
  cat <<'SMARTCTLAWK'
$1 ~ /^ *[0-9]+$/ && $2 ~ /^[a-zA-Z0-9_-]+$/ {
  gsub(/-/, "_");
  printf "%s_value{%s,smart_id=\"%s\"} %d\n", $2, labels, $1, $4
  printf "%s_worst{%s,smart_id=\"%s\"} %d\n", $2, labels, $1, $5
  printf "%s_threshold{%s,smart_id=\"%s\"} %d\n", $2, labels, $1, $6
  printf "%s_raw_value{%s,smart_id=\"%s\"} %e\n", $2, labels, $1, $10
}
SMARTCTLAWK
)"

smartmon_attrs="$(
  cat <<'SMARTMONATTRS'
airflow_temperature_cel
command_timeout
current_pending_sector
end_to_end_error
erase_fail_count
g_sense_error_rate
hardware_ecc_recovered
host_reads_mib
host_reads_32mib
host_writes_mib
host_writes_32mib
load_cycle_count
media_wearout_indicator
multi_zone_error_rate
wear_leveling_count
nand_writes_1gib
offline_uncorrectable
percent_lifetime_remain
power_cycle_count
power_off_retract_count
power_on_hours
program_fail_count
raw_read_error_rate
reallocated_event_count
reallocated_sector_ct
reallocate_nand_blk_cnt
reported_uncorrect
sata_downshift_count
seek_error_rate
spin_retry_count
spin_up_time
start_stop_count
temperature_case
temperature_celsius
temperature_internal
total_lbas_read
total_lbas_written
total_host_sector_write
udma_crc_error_count
unsafe_shutdown_count
workld_host_reads_perc
workld_media_wear_indic
workload_minutes
SMARTMONATTRS
)"

smartmon_nvme_attrs="$(
cat << 'nvme'
critical_warning
temperature
available_spare
available_spare_threshold
percentage_used
data_units_read
data_units_written
host_read_commands
host_write_commands
controller_busy_time
power_cycles
power_on_hours
unsafe_shutdowns
media_and_data_integrity_errors
error_information_log_entries
warning__comp_temperature_time
critical_comp_temperature_time
nvme
)"


parse_smartctl_nvme_attributes_awk="$(
  cat <<'SMARTCTLAWK'
$0 ~ /^.*:/ {
 split($0,a,":"); gsub(" ", "_", a[1]); gsub("\\.", "", a[1]);
 if (a[2] ~ /,/) { gsub(",", "", a[2]); }
 #printf "%d\n",  a[2]
 printf "%s_value{%s} %d\n", a[1], labels, a[2]

}
SMARTCTLAWK
)"


smartmon_nvme_attrs="$(echo ${smartmon_nvme_attrs} | xargs | tr ' ' '|')"
parse_smartctl_nvme_attributes() {
  local disk="$1"
  local disk_type="$2"
  local labels="device=\"${disk}\",type=\"${disk_type}\""
  local vars="$(echo "${smartmon_nvme_attrs}" | xargs | tr ' ' '|')"
  sed 's/^ \+//g' |
  awk -v labels="${labels}" "${parse_smartctl_nvme_attributes_awk}" 2>/dev/null |
  tr A-Z a-z |
  grep -E "(${smartmon_nvme_attrs})"
}



smartmon_attrs="$(echo ${smartmon_attrs} | xargs | tr ' ' '|')"
parse_smartctl_attributes() {
  local disk="$1"
  local disk_type="$2"
  local labels="device=\"${disk}\",type=\"${disk_type}\""
  local vars="$(echo "${smartmon_attrs}" | xargs | tr ' ' '|')"
  sed 's/^ \+//g' |
    awk -v labels="${labels}" "${parse_smartctl_attributes_awk}" 2>/dev/null |
    tr A-Z a-z |
    grep -E "(${smartmon_attrs})"
}

parse_smartctl_scsi_attributes() {
  local disk="$1"
  local disk_type="$2"
  local labels="device=\"${disk}\",type=\"${disk_type}\""
  while read line; do
    attr_type="$(echo "${line}" | tr '=' ':' | cut -f1 -d: | sed 's/^ \+//g' | tr ' ' '_')"
    attr_value="$(echo "${line}" | tr '=' ':' | cut -f2 -d: | sed 's/^ \+//g' | tr ',' '.')"
    case "${attr_type}" in
    number_of_hours_powered_up_) power_on="$(echo "${attr_value}" | awk '{ printf "%e\n", $1 }')" ;;
    Current_Drive_Temperature) temp_cel="$(echo ${attr_value} | cut -f1 -d' ' | awk '{ printf "%e\n", $1 }')" ;;
    Blocks_read_from_cache_and_sent_to_initiator_) lbas_read="$(echo ${attr_value} | awk '{ printf "%e\n", $1 }')" ;;
    Accumulated_start-stop_cycles) power_cycle="$(echo ${attr_value} | awk '{ printf "%e\n", $1 }')" ;;
    Elements_in_grown_defect_list) grown_defects="$(echo ${attr_value} | awk '{ printf "%e\n", $1 }')" ;;
    esac
  done
  [ ! -z "$power_on" ] && echo "power_on_hours_raw_value{${labels},smart_id=\"9\"} ${power_on}"
  [ ! -z "$temp_cel" ] && echo "temperature_celsius_raw_value{${labels},smart_id=\"194\"} ${temp_cel}"
  [ ! -z "$lbas_read" ] && echo "total_lbas_read_raw_value{${labels},smart_id=\"242\"} ${lbas_read}"
  [ ! -z "$power_cycle" ] && echo "power_cycle_count_raw_value{${labels},smart_id=\"12\"} ${power_cycle}"
  [ ! -z "$grown_defects" ] && echo "grown_defects_count_raw_value{${labels},smart_id=\"12\"} ${grown_defects}"
}

parse_smartctl_info() {
  local -i smart_available=0 smart_enabled=0 smart_healthy=0
  local disk="$1" disk_type="$2"
  local model_family='' device_model='' serial_number='' fw_version='' vendor='' product='' revision='' lun_id=''
  while read line; do
    info_type="$(echo "${line}" | cut -f1 -d: | tr ' ' '_')"
    info_value="$(echo "${line}" | cut -f2- -d: | sed 's/^ \+//g' | sed 's/"/\\"/')"
    case "${info_type}" in
    Model_Family) model_family="${info_value}" ;;
    Device_Model) device_model="${info_value}" ;;
    Serial_Number) serial_number="${info_value}" ;;
    Firmware_Version) fw_version="${info_value}" ;;
    Vendor) vendor="${info_value}" ;;
    Product) product="${info_value}" ;;
    Revision) revision="${info_value}" ;;
    Logical_Unit_id) lun_id="${info_value}" ;;
    esac
    if [[ "${device_model}" =~ 'SSD' || "${device_model}" =~ 'ssd' ]]; then
	disk_type="ssd";
    fi
    if [[ "${info_type}" == 'SMART_support_is' ]]; then
      case "${info_value:0:7}" in
      Enabled) smart_enabled=1 ;;
      Availab) smart_available=1 ;;
      Unavail) smart_available=0 ;;
      esac
    fi
    if [[ "${info_type}" == 'SMART_overall-health_self-assessment_test_result' ]]; then
      case "${info_value:0:6}" in
      PASSED) smart_healthy=1 ;;
      esac
    elif [[ "${info_type}" == 'SMART_Health_Status' ]]; then
      case "${info_value:0:2}" in
      OK) smart_healthy=1 ;;
      esac
    fi
  done
  echo "device_info{device=\"${disk}\",type=\"${disk_type}\",vendor=\"${vendor}\",product=\"${product}\",revision=\"${revision}\",lun_id=\"${lun_id}\",model_family=\"${model_family}\",device_model=\"${device_model}\",serial_number=\"${serial_number}\",firmware_version=\"${fw_version}\"} 1"
  echo "device_smart_available{device=\"${format_disk}\",type=\"${disk_type}\"} ${smart_available}"
  echo "device_smart_enabled{device=\"${format_disk}\",type=\"${disk_type}\"} ${smart_enabled}"
  echo "device_smart_healthy{device=\"${format_disk}\",type=\"${disk_type}\"} ${smart_healthy}"
}

output_format_awk="$(
  cat <<'OUTPUTAWK'
BEGIN { v = "" }
v != $1 {
  print "# HELP smartmon_" $1 " SMART metric " $1;
  print "# TYPE smartmon_" $1 " gauge";
  v = $1
}
{print "smartmon_" $0}
OUTPUTAWK
)"

format_output() {
  sort |
    awk -F'{' "${output_format_awk}"
}

smartctl_version="$(/usr/sbin/smartctl -V | head -n1 | awk '$1 == "smartctl" {print $2}')"

echo "smartctl_version{version=\"${smartctl_version}\"} 1" | format_output

if [[ "$(expr "${smartctl_version}" : '\([0-9]*\)\..*')" -lt 6 ]]; then
  exit
fi

device_list="$(/usr/sbin/smartctl --scan-open | awk '/^\/dev/{print $1 "|" $3}')"



get_type_disk(){
  local disk="$1" disk_type="$2"
  if [[ $disk_type =~ "nvme" ]]; then echo "nvme"; return; fi
  while read line; do
    info_type="$(echo "${line}" | cut -f1 -d: | tr ' ' '_')"
    info_value="$(echo "${line}" | cut -f2- -d: | sed 's/^ \+//g' | sed 's/"/\\"/')"
    case "${info_type}" in Device_Model) device_model="${info_value}" ;; esac
   done
   if [[ "${device_model}" =~ 'SSD' || "${device_model}" =~ 'ssd' ]]; then disk_type="ssd"; fi
   echo $disk_type
}


for device in ${device_list}; do
  disk="$(echo ${device} | cut -f1 -d'|')"
  type="$(echo ${device} | cut -f2 -d'|')"
  type_disk="$(/usr/sbin/smartctl -i -H -d "${type}" "${disk}" | get_type_disk "${disk}" "${type}")"
  format_disk="$(echo "${disk}" | sed 's/.*\///')"
  active=1
  echo "smartctl_run{device=\"${format_disk}\",type=\"${type_disk}\"}" "$(TZ=UTC date '+%s')"
  # Check if the device is in a low-power mode
  /usr/sbin/smartctl -n standby -d "${type}" "${disk}" > /dev/null || active=0
  echo "device_active{device=\"${format_disk}\",type=\"${type_disk}\"}" "${active}"
  # Skip further metrics to prevent the disk from spinning up
  test ${active} -eq 0 && continue
  # Get the SMART information and health
  /usr/sbin/smartctl -i -H -d "${type}" "${disk}" | parse_smartctl_info "${format_disk}" "${type}"
  # Get the SMART attributes
  case ${type_disk} in
  ssd) /usr/sbin/smartctl -A -d "${type}" "${disk}" | parse_smartctl_attributes "${format_disk}" "${type_disk}" ;;
  nvme) /usr/sbin/smartctl -A -d "${type}" "${disk}" | parse_smartctl_nvme_attributes "${format_disk}" "${type}" ;;
  sat) /usr/sbin/smartctl -A -d "${type}" "${disk}" | parse_smartctl_attributes "${format_disk}" "${type}" ;;
  sat+megaraid*) /usr/sbin/smartctl -A -d "${type}" "${disk}" | parse_smartctl_attributes "${format_disk}" "${type}" ;;
  scsi) /usr/sbin/smartctl -A -d "${type}" "${disk}" | parse_smartctl_scsi_attributes "${format_disk}" "${type}" ;;
  megaraid*) /usr/sbin/smartctl -A -d "${type}" "${disk}" | parse_smartctl_scsi_attributes "${format_disk}" "${type}" ;;
  *)
    echo "disk type is not sat, scsi or megaraid but ${type}"
    exit
    ;;
  esac
done | format_output

