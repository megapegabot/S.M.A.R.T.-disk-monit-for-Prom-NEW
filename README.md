# smartmon
[fork S.M.A.R.T-disk-monitoring-for-Prometheus](https://github.com/micha37-martins/S.M.A.R.T-disk-monitoring-for-Prometheus) 

Update:
- **add type SSD**
- **add support SMART NVME**
```
# NVME metrics
critical_warning [0x00=0, 0x01=1, 0x02=2, ....] read /file/SMART+Attribute+NVMe+SSD.pdf
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
warning__comp._temperature_time
critical_comp._temperature_time
```
* edit labels smartmon metrics{disk} on metrics{device} 
* edit generate values metrics{disk="/dev/sda"} on metrics{disk="sda"}

This allows you to set flexible trigger settings.

```
# PromQL query
# add type disk in node_disk_read_bytes_total(node_exporter)
node_disk_read_bytes_total * on (instance, device) group_left (type) smartmon_device_info
```

# S.M.A.R.T.-disk-monitoring-for-Prometheus text_collector

Prometheus `node_exporter` `text_collector` for S.M.A.R.T disk values

Following dashboards are designed for this exporter:

https://grafana.com/dashboards/10530

https://grafana.com/dashboards/10531

## Purpose
This text_collector is a customized version of the S.M.A.R.T. `text_collector` example from `node_exporter` github repo:
https://github.com/prometheus/node_exporter/tree/master/text_collector_examples

## Requirements
- Prometheus
- node_exporter
  - text_collector enabled for node_exporter
- Grafana = 6.2
- smartmontools = 7

## Set up
To enable text_collector set the following flag for `node_exporter`:
- `--collector.textfile.directory`
run command with `/var/lib/node_exporter/textfile_collector`
To get an up to date version of smartmontools it could be necessary to compile it:
https://www.smartmontools.org/wiki/Download#Installfromthesourcetarball

- check by executing `smartctl --version`

- make smartmon.sh executable

- save it under `/usr/local/bin/smartmon.sh`

To enable the text_collector on your system add the following as cronjob.
It will execute the script every five minutes and save the result to the `text_collector` directory.

Example for UBUNTU `crontab -e`:

`*/5 * * * * /usr/local/bin/smartmon.sh > /var/lib/node_exporter/textfile_collector/smart_metrics.prom`

## How to add specific S.M.A.R.T. attributes
If you are missing some attributes you can extend the text_collector.
Add the desired attributes to `smartmon_attrs` array in `smartmon.sh`.

You get a list of your disks privided attributes by executing:
`sudo 	smartctl -i -H /dev/<sdx>`
`sudo 	smartctl -A /dev/<sdx>`
