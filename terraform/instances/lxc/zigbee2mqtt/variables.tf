variable "zigbee2mqtt_template_file_id" {
  type        = string
  description = "Shared Proxmox template used for the Zigbee2MQTT LXC."
  default     = "unraid:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
}

variable "zigbee2mqtt_target_node" {
  type        = string
  description = "Proxmox node that hosts the Zigbee2MQTT LXC."
  default     = "pve1"
}
