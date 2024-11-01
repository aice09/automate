#!/bin/bash

# Function to install GlusterFS on CentOS/RHEL
install_glusterfs_centos() {
    sudo yum update -y
    sudo yum install -y epel-release
    sudo yum install -y glusterfs-server
    sudo systemctl start glusterd
    sudo systemctl enable glusterd
}

# Function to install GlusterFS on Ubuntu
install_glusterfs_ubuntu() {
    sudo apt update -y
    sudo apt install -y glusterfs-server
    sudo systemctl start glusterd
    sudo systemctl enable glusterd
}

# Function to setup GlusterFS client
setup_glusterfs_client() {
    read -p "Enter the server IP to mount the volume: " SERVER_IP
    read -p "Enter the volume name to mount: " MOUNT_VOLUME
    MOUNT_POINT="/mnt/$MOUNT_VOLUME"

    # Create mount point and mount the volume
    sudo mkdir -p "$MOUNT_POINT"
    sudo mount -t glusterfs "$SERVER_IP:/$MOUNT_VOLUME" "$MOUNT_POINT"

    # Verification if mounted properly
    if mount | grep "on $MOUNT_POINT type glusterfs" > /dev/null; then
        echo "Successfully mounted $MOUNT_VOLUME at $MOUNT_POINT."
    else
        echo "Failed to mount $MOUNT_VOLUME."
    fi

    # Optionally add to fstab for auto-mounting
    read -p "Do you want to add the mount to /etc/fstab for auto-mounting? (y/n): " ADD_TO_FSTAB
    if [[ "$ADD_TO_FSTAB" == "y" ]]; then
        echo "$SERVER_IP:/$MOUNT_VOLUME $MOUNT_POINT glusterfs defaults,_netdev 0 0" | sudo tee -a /etc/fstab
        echo "Added to /etc/fstab."
    fi

    echo "GlusterFS client setup completed."
}

# Function to install GlusterFS on a remote server
install_glusterfs_on_remote() {
    SERVER_IP=$1
    read -p "Enter the SSH username for $SERVER_IP: " SSH_USER
    read -s -p "Enter the SSH password for $SERVER_IP: " SSH_PASS
    echo

    # Use sshpass to handle password authentication
    sshpass -p "$SSH_PASS" ssh "$SSH_USER@$SERVER_IP" << 'EOF'
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            OS_NAME=$ID
            case "$OS_NAME" in
                centos)
                    sudo yum update -y
                    sudo yum install -y epel-release
                    sudo yum install -y glusterfs-server
                    ;;
                rhel)
                    sudo yum update -y
                    sudo yum install -y epel-release
                    sudo yum install -y glusterfs-server
                    ;;
                ubuntu)
                    sudo apt update -y
                    sudo apt install -y glusterfs-server
                    ;;
                *)
                    echo "Unsupported OS: $OS_NAME. Exiting."
                    exit 1
                    ;;
            esac
            sudo systemctl start glusterd
            sudo systemctl enable glusterd
        else
            echo "Unsupported OS. Exiting."
            exit 1
        fi
EOF
}

# Detect the OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$ID
else
    echo "Unsupported OS. Exiting."
    exit 1
fi

# Ask if setting up client or server
read -p "Do you want to set up a GlusterFS client or server? (client/server): " SETUP_TYPE

if [[ "$SETUP_TYPE" == "server" ]]; then
    # Install GlusterFS on the primary server based on the OS
    case "$OS_NAME" in
        centos)
            install_glusterfs_centos
            ;;
        rhel)
            install_glusterfs_centos
            ;;
        ubuntu)
            install_glusterfs_ubuntu
            ;;
        *)
            echo "Unsupported OS: $OS_NAME. Exiting."
            exit 1
            ;;
    esac

    # Ask for the number of servers
    read -p "How many servers do you want to set up? (1 or more): " SERVER_COUNT
    if ! [[ "$SERVER_COUNT" =~ ^[1-9][0-9]*$ ]]; then
        echo "Invalid number of servers. Please enter a positive integer."
        exit 1
    fi

    # Create an array to hold server IP addresses
    SERVER_IPS=()
    
    for ((i=1; i<=SERVER_COUNT; i++)); do
        read -p "Enter the IP address of server $i: " SERVER_IP
        SERVER_IPS+=("$SERVER_IP")
    done

    # Install GlusterFS on each remote server
    for SERVER_IP in "${SERVER_IPS[@]}"; do
        install_glusterfs_on_remote "$SERVER_IP"
    done

    # Ask if setup is by cluster or individual
    read -p "Is the setup by cluster or individual? (cluster/individual): " CLUSTER_TYPE

    # Create the GlusterFS volume
    if [[ "$CLUSTER_TYPE" == "cluster" ]]; then
        read -p "Enter the volume name: " VOLUME_NAME
        read -p "Enter the brick path (e.g., /data/glusterfs/brick1): " BRICK_PATH
        
        # Create brick directory on each server
        for IP in "${SERVER_IPS[@]}"; do
            ssh "$IP" "sudo mkdir -p $BRICK_PATH"
        done

        # Create the volume with replicas
        VOLUME_COMMAND="sudo gluster volume create $VOLUME_NAME replica $SERVER_COUNT "
        for IP in "${SERVER_IPS[@]}"; do
            VOLUME_COMMAND+="$IP:$BRICK_PATH "
        done
        eval "$VOLUME_COMMAND"

        sudo gluster volume start "$VOLUME_NAME"
        echo "GlusterFS volume '$VOLUME_NAME' created successfully."
    else
        read -p "Enter the volume name: " VOLUME_NAME
        read -p "Enter the brick path (e.g., /data/glusterfs/brick1): " BRICK_PATH
        
        # Create brick directory on the first server
        ssh "${SERVER_IPS[0]}" "sudo mkdir -p $BRICK_PATH"

        # Create the volume
        sudo gluster volume create "$VOLUME_NAME" "${SERVER_IPS[0]}:$BRICK_PATH"
        sudo gluster volume start "$VOLUME_NAME"
        echo "GlusterFS volume '$VOLUME_NAME' created successfully."
    fi

    # Verification of setup
    echo "Verifying the GlusterFS setup..."
    sudo gluster volume info
    echo "GlusterFS server setup completed."

elif [[ "$SETUP_TYPE" == "client" ]]; then
    # Setup GlusterFS client
    if [[ "$OS_NAME" == "centos" || "$OS_NAME" == "rhel" ]]; then
        sudo yum install -y glusterfs
    elif [[ "$OS_NAME" == "ubuntu" ]]; then
        sudo apt install -y glusterfs-client
    else
        echo "Unsupported OS for client setup. Exiting."
        exit 1
    fi
    setup_glusterfs_client
else
    echo "Invalid option. Exiting."
    exit 1
fi

echo "GlusterFS setup process completed."
