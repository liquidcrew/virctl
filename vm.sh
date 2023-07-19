#!/bin/bash

###############
# GLOBAL VARS #
###############

# Options
force=false  # Ask for confirmation.

# Paths
sp="$(dirname $(readlink -f $0))"  # Absolute path of this script.
sn="$(basename $0)"                # Filename of this script.
conf="$sp/${sn%.*}.yaml"           # Configuration file path.

# Message colors
c_green="\e[0;32m"
c_yellow="\e[0;33m"
c_red="\e[0;31m"
c_bold="\e[1m"
c_def="\e[0m"


#############
# FUNCTIONS #
#############

# Asks for confirmation before running an action.
# Doesn't ask if 'force=false'.
function confirm {
    local msg="$1"
    if ! "$force"; then
        read -p 'Press "Enter" to continue or "Ctrl + C" to cancel'
        echo
    fi
}


# Prints user given message to 'stderr' in yellow and continues execution.
function warning {
    local msg="$1"
    >&2 echo -e "${c_yellow}Warning: $msg${c_def}"
}

# Prints user given message to 'stderr' in red and continues execution.
function error {
    local msg="$1"
    >&2 echo -e "${c_red}Error: $msg${c_def}"
}


# Prints user given message to 'stderr' in red and exits with errors.
function panic {
    local msg="$1"
    >&2 echo -e "${c_red}Error: $msg${c_def}"
    exit 1
}


# Validates that the user given data is correct.
function validate {
    [[ -z "$1" ]] && { error 'Argument missing.'; help 'error'; }
    [[ ! "$1" =~ ^(deploy|undeploy|redeploy|start|stop|restart|status|shell-vm|shell-ssh|help)$ ]] \
    && { error "Invalid action: '$1'"; help 'error'; }
    [[ ! -f "$conf" ]] && { error "Missing configuration file '$conf'"; help 'error'; }
}


# Reads configuration file and calculates runtime variables.
function load_conf {
    eval $(yq -r 'to_entries[] | "\(.key)=\(.value | @sh)"' "$conf")
    addr=$(yq -r '.ethernets.eth0.addresses[0]' "$sp/cloud-init/network-config.yaml" | cut -d/ -f1)
    user_name=$(yq -r '.users[1].name' "$sp/cloud-init/user-data.yaml")
    vd_tpl="$sp/images/$(basename "$vd_src")"  # Path of vdisk template file.
    vd_dst="$sp/images/$name.qcow2"            # Path of VM's vdisk file.
}


# Connects to the VM and waits until `cloud-init` finishes. 
function wait_cloud_init {
    echo -n '• Waiting for SSH to be available on the VM '
    while ! check_ssh; do echo -n '.'; sleep 1; done; echo
    echo -n '• Waiting for cloud-init to finish on the VM '
    sshx 'cloud-init status --wait'
}


# Checks that the virtual machine exists.
function is_vm {
    virsh list --name --all | grep '^'$name'$' &> /dev/null
}


# Checks that the virtual machine is running.
function is_vm_up {
    is_vm && virsh list --name | grep '^'$name'$' &> /dev/null
}


# Prints VM's description.
function desc_vm {
    vnc_addr=$(virsh vncdisplay "$name")
    vnc_addr=${vnc_addr:="auto"}

    cat <<EOF
  - Name:       "$name"
  - OS Type:    "$os"
  - CPU(s):     "$cpu"
  - Max memory: "$mem_mb MB"
  - Vdisk size: "$vd_gb GB"
  - Hostname:   "$name"
  - IP addr:    "$addr"
  - VNC addr:   "$vnc_addr"

EOF
}


# Creates SSH keys in workspace if needed.
function ssh_keypair_create {
    local ssh_key_dir="$sp/ssh-keys"

    if [[ ! -f  "${ssh_key_dir}/id_ed25519" ]]; then
        echo '• Creating new SSH key pair'
        mkdir -p "$ssh_key_dir"
        ssh-keygen -q \
            -t ed25519 -P '' \
            -f "${ssh_key_dir}/id_ed25519" \
            -C "${user_name}@${name}"
    
        local ssh_pub_key=$(cat "${ssh_key_dir}/id_ed25519.pub")
        yq -w 999 -yi \
            ".users[1].ssh_authorized_keys = \"$ssh_pub_key\"" \
            "$sp/cloud-init/user-data.yaml" && \
        sed  -i '1i #cloud-config' "$sp/cloud-init/user-data.yaml"
    fi
}


# Removes SSH keys from workspace.
function ssh_keypair_remove {
    local ssh_key_dir="$sp/ssh-keys"

    if [[ $(ssh-keygen -F "$addr") ]]; then
        echo "• Removing VM's public SSH key from ~/.ssh/known_hosts"
        ssh-keygen -R "$addr" &> /dev/null
    fi

    if [[ -f  "$ssh_key_dir/id_ed25519.pub" ]]; then
        echo '• Removing public SSH key'
        rm -f "$ssh_key_dir/id_ed25519.pub"
    fi

    if [[ -f  "$ssh_key_dir/id_ed25519" ]]; then
        echo '• Removing private SSH key'
        rm -f "$ssh_key_dir/id_ed25519"
    fi

    echo "• Removing user's public key from 'cloud-init/user-data.yaml'" 
    yq -yi ".users[1].ssh_authorized_keys = \"\"" "$sp/cloud-init/user-data.yaml" && \
    sed  -i '1i #cloud-config' "$sp/cloud-init/user-data.yaml"
}


# Checks that the VM is reachable via SSH.
function check_ssh {
    nc -z "$addr" 22;
}


# Sends a command to the VM through SSH.
function sshx {
    local cmd="$1"
    ssh -o LogLevel=ERROR \
        -o StrictHostKeyChecking=no \
        -i "$sp/ssh-keys/id_ed25519" \
        -p 22 \
        "$user_name@$addr" \
        "$cmd"
}


# Creates a directory at the user given path.
function create_dir {
    local path="$1"  # Directory path
    [[ -e "$path" ]] && [[ ! -d "$path" ]] && panic "Path $path exists but it's not a directory"
    [[ ! -e "$path" ]] && mkdir "$path"
}


# Downloads the virtual disk template.
function vdisk_tpl_get {
    create_dir "$(dirname "$vd_tpl")"
    if [[ ! -f "$vd_tpl" ]]; then
        echo "• Downloading vdisk template '$(basename "$vd_src")'"
        wget -c -q \
          --read-timeout=3 \
          --show-progress --progress=bar \
          "$vd_src" -O "$vd_tpl" \
        || { rm -rf "$vd_tpl" &> /dev/null; panic 'Download failed'; }
    fi
}


# Prints the size of a virtual disk image
function vdisk_size {
    local path="$1"
    local vd_bytes=$(qemu-img info -U --output=json "$path" | jq '.["virtual-size"]')
    echo "$vd_bytes / 1024^3" | bc
}


# Creates the vdisk for the virtual machine.
function vdisk_vm_create {
    if [[ ! -f "$vd_dst" ]]; then
        local vd_tpl_gb="$(vdisk_size "$vd_tpl")"

        echo "• Creating vdisk '$name.qcow2' for the VM"
        create_dir $(dirname "$vd_dst")

        if [[ $vd_tpl_gb -gt $vd_gb ]]; then
            vd_gb=$vd_tpl_gb
            warning "Vdisk template bigger than expected"
            warning "New size for VM vdisk is $vd_gb GB"
        fi

        cp "$vd_tpl" "$vd_dst"

        if [[ $vd_gb -gt $vd_tpl_gb ]]; then
            echo "• Resizing vdisk '$name.qcow2' to $vd_gb GB"
            qemu-img resize "$vd_dst" "${vd_gb}G" > /dev/null
        fi
    fi
}


# Removes the vdisk of the virtual machine.
function vdisk_vm_remove {
    [[ -f $vd_dst ]] && { echo '• Removing vdisk'; rm -f "$vd_dst" &> /dev/null; }
}


# Creates the virtual machine.
function vm_create {
    echo "• Creating VM '$name'"

    # Enable cloud-init support if one the required files exist into 'cloud-init' directory.
    local cloud_init_arg
    for file in 'meta-data' 'network-config' 'user-data'; do
        local path="${sp}/cloud-init/${file}.yaml"
        [[ ! -f "${path}" ]] && panic "Missing cloud-init file : $file"
        cloud_init_arg+=$([[ -n "$cloud_init_arg" ]] && echo ',')
        cloud_init_arg+="${file}=${path}"
    done

    # Set mac address selector in network-config.
    yq -yi ".ethernets.eth0.match.macaddress = \"$mac_addr\"" cloud-init/network-config.yaml

    # Create virtual machine.
    virt-install \
        --name "$name" \
        --cpu host \
        --vcpus $cpu  \
        --memory $mem_mb \
        --graphics none \
        --os-variant "$os" \
        --disk "$vd_dst",format=qcow2,bus=virtio,size="$vd_gb" \
        --network bridge="$bridge",model=virtio,mac="$mac_addr" \
        --cloud-init "$cloud_init_arg" \
        --import \
        --check disk_size=off \
        --noautoconsole | sed -e '/^[[:space:]]*$/d' \
    || panic 'VM creation failed'
}


# Removes the virtual machine
function vm_remove {
    stop 
    if is_vm; then
        echo '• Removing VM'
        virsh undefine "$name" --managed-save --snapshots-metadata | sed -e '/^[[:space:]]*$/d'
        yq -yi ".ethernets.eth0.match.macaddress = \"\"" cloud-init/network-config.yaml
    fi
}


# Creates the VM and the vdisk.
function deploy {
    is_vm && panic 'VM already deployed'
    echo -e "\nYou're going to ${c_green}${c_bold}deploy${c_def} this VM:"
    desc_vm
    ! "$force" && confirm
    vdisk_tpl_get; vdisk_vm_create; ssh_keypair_create; vm_create
    wait_cloud_init &&\
    virsh snapshot-create "$name" &&\
    echo -e "$(cat <<EOF

VM "$name" deployed successfully
To open the virtual serial console: ${c_bold}$0 shell-vm${c_def}
To connect to the SSH service: ${c_bold}$0 shell-ssh${c_def}
EOF
)" \
    || echo panic "VM deployment failed"
}


# Removes the VM and the vdisk.
function undeploy {
    echo -e "\nYou're going to ${c_red}${c_bold}undeploy${c_def} this VM:"
    desc_vm
    ! "$force" && confirm; vm_remove; vdisk_vm_remove
    ssh_keypair_remove
}


# Recreates the VM and the vdisk. 
function redeploy {
    undeploy 
    deploy
}


# Starts the VM.
function start {
    is_vm_up && panic 'VM already started'
    echo '• Starting VM'; virsh start $name | sed -e '/^[[:space:]]*$/d'
}


# Stops the VM.
function stop {
    echo '• Stopping VM'
    is_vm_up && virsh destroy $name | sed -e '/^[[:space:]]*$/d' || echo "Domain 'opennebula' already destroyed"
}


# Restarts the VM.
function restart {
  stop; start
}


# Shows the VM status.
function status {
    if is_vm; then
        if [[ -f "$vd_dst" ]]; then
            local vd_size=$(vdisk_size $vd_dst)
        else
            local vd_gb="${c_red}N/A (Vdisk missing)${c_def}"
            local vd_dst="${c_red}N/A (Vdisk missing)${c_def}"
        fi

        virsh dominfo $name | sed -e '/^[[:space:]]*$/d' -e 's/^/  - /'
        echo "  - Vdisk size:     $vd_size GB"
        echo "  - Vdisk path:     $vd_dst"
    else
        echo '  - State:          undeployed'
    fi

    [[ ! -f "$vd_tpl" ]] && local vd_tpl="${c_red}N/A (Vdisk missing)${c_def}"
    echo "  - Vdisk template: $vd_tpl"
}


# Attaches to VM's serial console.
function shell-vm {
    ! is_vm_up && panic 'VM is stopped'
    virsh console $name
}


# Connect to VM's SSH service.
function shell-ssh {
  ! is_vm_up && panic 'VM is stopped'
  ssh -i $sp/ssh-keys/id_ed25519 "${user_name}@${addr}"
}


# Prints help and exits with error if required.
function help {
    [[ "$1" == "error" ]] && local is_err=true

    cat <<EOF
help: $0 <action>
Valid actions are:
  - deploy [force]: Create the VM and the vdisk.
  - undeploy [force]: Remove the VM and the vdisk.
  - redeploy [force]: Recreate the VM and the vdisk.
  - start: Start the VM.
  - stop: Stop the VM.
  - restart: Restart the VM.
  - status: Show the VM status.
  - shell-vm: Attach to VM's serial console.
  - shell-ssh: Connect to VM's SSH service.
  - help: Prints help.
Example: $0 deploy
EOF
    $is_err && exit 1
}


########
# MAIN #
########

validate $@
action="$1"
[[ "$2" == "force" ]] && force=true
load_conf
"$action"
