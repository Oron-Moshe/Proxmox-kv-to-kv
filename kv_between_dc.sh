#!/bin/bash

source_hostname=$(hostname | cut -c1-6)

welcome() {
echo -e "\e[4;34mKV to KV between Datacenters\e[0m"
echo -e "Before you starting the script:"
echo -e "\e[1;33mcreate a rule in the DESTINATION datacenter firewall before starting the copy.\e[0m"
echo -e "\e[1;31mGet permission from the infrastructure team if you copy between datacenters in IL.\e[0m"
}


get_inputs() {
    while true; do
        read -p "Enter the SOURCE VM ID (numbers only): " source_vmid
        if [[ $source_vmid =~ ^[0-9]+$ ]]; then
            break
        else
            echo -e "\e[31mInvalid input. Please enter numbers only.\e[0m"
        fi
    done

    while true; do
        read -p "Enter the DESTINATION VM ID (numbers only): " destination_vmid
        if [[ $destination_vmid =~ ^[0-9]+$ ]]; then
            break
        else
            echo -e "\e[31mInvalid input. Please enter numbers only.\e[0m"
        fi
    done

    read -p "Enter the DESTINATION VM Name: " destination_vmname

	while true; do
		read -p "Enter the DESTINATION hostname (e.g.: kv0555): " destination_hostname
		if [[ $destination_hostname =~ ^kv[0-9]{4}$ && ${#destination_hostname} -eq 6 ]]; then
			break
		else
			echo -e "\e[31mInvalid input. The hostname must be exactly 6 characters long, start with 'kv', and end with 4 digits (e.g.: kv0555).\e[0m"
		fi
	done

    while true; do
        read -p "Enter the DESTINATION host IP: " destination_hostip
        if [[ $destination_hostip =~ ^[0-9.]+$ ]]; then
            break
        else
            echo -e "\e[31mInvalid input. Please enter a valid IP.\e[0m"
        fi
    done

    echo -e "\e[32mInputs collected successfully:\e[0m"
	echo "SOURCE Hostname: $source_hostname"
    echo "SOURCE VM ID: $source_vmid"
    echo "DESTINATION VM ID: $destination_vmid"
    echo "DESTINATION VM Name: $destination_vmname"
    echo "DESTINATION Hostname: $destination_hostname"
    echo "DESTINATION Host IP: $destination_hostip"
}

check_destination_vm() {
    echo -e "\n\e[34m=== Checking Destination VM Configuration ===\e[0m"
    echo "Connecting to $destination_hostip to verify config file..."
    ssh -o StrictHostKeyChecking=no root@"$destination_hostip" \
        "grep -q 'name: $destination_vmname' /etc/pve/qemu-server/${destination_vmid}.conf"

    if [[ $? -eq 0 ]]; then
        echo -e "\e[32mSuccess:\e[0m 'name: $destination_vmname' was found in /etc/pve/qemu-server/${destination_vmid}.conf"
    else
        echo -e "\e[31mWarning:\e[0m 'name: $destination_vmname' was NOT found in /etc/pve/qemu-server/${destination_vmid}.conf"
        exit 1
    fi
}

confirmation() {
    local conf_file="/etc/pve/qemu-server/${source_vmid}.conf"

    if [[ ! -f "$conf_file" ]]; then
        echo "Error: Config file not found at $conf_file"
        exit 1
    fi

    local source_vmname
    source_vmname="$(grep '^name:' "$conf_file" | sed 's/^name:\s*//')"

    echo "Source VM name:       $source_vmname"
    echo "Destination VM name:  $destination_vmname"
    read -rp "Do you want to continue? (y/n) " answer

    if [[ "$answer" != "y" ]]; then
        echo "aborting."
        exit 1
    fi
}

list_files_in_storage() {
    echo -e "\n\e[34m=== Checking Local Storage Directory ===\e[0m"

    local storage_dir="/storage/${source_hostname}_storage1/images/${source_vmid}"
    
    if [[ ! -d "$storage_dir" ]]; then
        echo -e "\e[31mERROR:\e[0m The directory $storage_dir does not exist."
        echo "Please verify the path or that the VM ID is correct."
        return 1 
    fi

    echo "Files found in $storage_dir:"
    mapfile -t file_list < <(ls -1 "$storage_dir")
    
    if [[ ${#file_list[@]} -eq 0 ]]; then
        echo -e "\e[33mNo files found in $storage_dir.\e[0m"
        return 0
    fi

    for i in "${!file_list[@]}"; do
        echo "$((i+1)). ${file_list[$i]}"
    done

    echo ""
    echo "Type the number of the file you want to choose (1-${#file_list[@]}),"
    echo "or type 'all' to select *all* files in this directory."
    read -p "Your choice: " user_choice

    if [[ "$user_choice" == "all" ]]; then
        chosen_path="${storage_dir}/*"
        echo "You chose ALL files: $chosen_path"
    else
        if [[ "$user_choice" =~ ^[0-9]+$ ]] && 
           (( user_choice >= 1 && user_choice <= ${#file_list[@]} )); then
            local selected_file="${file_list[$((user_choice - 1))]}"
            chosen_path="${storage_dir}/${selected_file}"
            echo "You chose: $chosen_path"
        else
            echo -e "\e[31mInvalid choice.\e[0m No file selected!"
            exit 1
        fi
    fi
}

run_scp() {
    scp -r ${chosen_path} root@${destination_hostip}:/storage/${destination_hostname}_storage1/images/${destination_vmid}/
}

main() {
	welcome
	get_inputs
    check_destination_vm
    confirmation
    list_files_in_storage
    run_scp
}

main
