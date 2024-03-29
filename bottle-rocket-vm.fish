#!/usr/bin/fish

# Options using ENV VAR
set -q BRVM_NAME; set BRVM_NAME "bottlerocket1"
# https://github.com/bottlerocket-os/bottlerocket/blob/develop/PROVISIONING-METAL.md#fetch-the-bottlerocket-image-for-bare-metal
set -q BRVM_BOTTLE_SPEC; or set BRVM_BOTTLE_SPEC "https://cache.bottlerocket.aws/root.json"
set -q BRVM_BOTTLE_SPEC_SHA512; or set BRVM_BOTTLE_SPEC_SHA512 "a3c58bc73999264f6f28f3ed9bfcb325a5be943a782852c7d53e803881968e0a4698bd54c2f125493f4669610a9da83a1787eb58a8303b2ee488fa2a3f7d802f"
set -q BRVM_ARCH; or set BRVM_ARCH "x86_64"
set -q BRVM_VERSION; or set BRVM_VERSION "v1.12.0"
set -q BRVM_VARIANT; or set BRVM_VARIANT "metal-k8s-1.23"
set -q BRVM_METADATA_DATE; or set BRVM_METADATA_DATE "2020-07-07"
set -q BRVM_SSHKEY_PREFIX; or set BRVM_SSHKEY_PREFIX "bottlerocket"
set -q BRVM_NETWORKFILE; or set BRVM_NETWORKFILE "net.toml"
set -q BRVM_USERDATAFILE; or set BRVM_USERDATAFILE "user-data.toml"
set -q BRVM_WORKINGDIR; or set BRVM_WORKINGDIR "./vm-build.noback"
set -q BRVM_SSH_PORTNAT; or set BRVM_SSH_PORTNAT "2222"
set -q BRVM_WAIT_FOR_VM_UP; or set BRVM_WAIT_FOR_VM_UP "60"


# Global config
set BRVM_IMAGE "bottlerocket-$BRVM_VARIANT-$BRVM_ARCH-$BRVM_VERSION.img"
set LOG_MSG_COLORS "yes"

function usage
    echo '
'(status filename)'
    [-h | --help] [-n | --next-steps]

Create a BottleRocket VM with virtualbox

It was inspired in [btiernay/create-mac-bottlerocket-virtualbox-vm.sh]https://gist.github.com/btiernay/5e4d62b126f28962cd008094e867e9a2

Options
    -h Display current text and exit
    -n Display next steps tutorial only and exit

Configuration properties are passed using env vars. Allowed environment variables with default values are:
'
    cat (status filename) | grep -P '^set -q[^;]+; or' | sed -e 's/set -q [^;]*; or set //g' -e 's/ /=/g'

    echo ''

end

function log
    set -l level $argv[1]
    set -l levels "(**)" "(++)" "(--)" "(··)"
    set -l colorMods "\033[32;1m" "\033[34;1m" "\033[35m" "\033[37;1m"
    set -l levelStr "(  )"
    set -l colorMod ""
    if test $level -eq 0
      set levelStr "(!!)"
      set colorMod "\033[33;5;1m"
    else if test $level -lt 0
      set levelStr "(EE)"
      set colorMod "\033[31;1m"
    else if test $level -lt 5
      set levelStr $levels[$level]
      set colorMod $colorMods[$level]
    end

    if test $LOG_MSG_COLORS = "yes"
      set levelStr $colorMod$levelStr'\033[0m'
      echo -e $levelStr' '$argv[2]
    else
      echo $levelStr' '$argv[2]
    end
end

function checkCommands
    log 1 "Checking required commands"
    for c in "VBoxManage" "unlz4" "ssh-keygen" "cargo" "losetup" "sudo" "sha512sum" "ssh" "scp"
        log 2 "$c"
        if not type -q "$c"
            echo "(EE) command $c not found. Aborting"
            exit 1
        end
    end
end

function workinDir
    log 1 "Preparing working directory"
    set BRVM_OLDWORKDIR "$PWD"
    log 2 "Ensuring $BRVM_WORKINGDIR directory exists"
    mkdir -p $BRVM_WORKINGDIR
    log 2 "Changing to $BRVM_WORKINGDIR directory"
    cd $BRVM_WORKINGDIR
end

function installTools
    log 1 "Installing required tools"
    log 2 "tuftool"
    cargo install tuftool
end

function vmImage
    log 1 "VM image"

    log 2 "Downloading spec"
    curl -sSLo root.json "$BRVM_BOTTLE_SPEC"

    log 3 "Checking sha512 hash code"
    echo "$BRVM_BOTTLE_SPEC_SHA512 root.json" > root.json.sha512
    sha512sum -c root.json.sha512; or exit 1

    log 2 "Fetching image"
    $HOME/.cargo/bin/tuftool download image --target-name "$BRVM_IMAGE.lz4" \
        --root ./root.json \
        --metadata-url "https://updates.bottlerocket.aws/$BRVM_METADATA_DATE/$BRVM_VARIANT/$BRVM_ARCH/" \
        --targets-url "https://updates.bottlerocket.aws/targets/"

    log 2 "Extracting image"
    unlz4 "image/$BRVM_IMAGE.lz4"
    mv "image/$BRVM_IMAGE" .
    rm -rf image/
end

function configureVM
    log 1 "VM configuration"

    log 2 "New ssh key"
    yes | ssh-keygen -q -t rsa -N '' -f $BRVM_SSHKEY_PREFIX >/dev/null 2>&1

    log 2 "Bottelrocket config files"
    log 3 "$BRVM_NETWORKFILE"
    echo '
version = 2
[enp0s3]
# See https://github.com/bottlerocket-os/bottlerocket/issues/842#issuecomment-1368107955
dhcp4 = true
' > "$BRVM_NETWORKFILE"

    log 3 "$BRVM_USERDATAFILE"
    set -l authorizedKeys (echo '{"ssh":{"authorized-keys":["'(cat $BRVM_SSHKEY_PREFIX.pub)'"]}}' | base64 -w 0)
    echo '
[settings.host-containers.admin]
# https://github.com/bottlerocket-os/bottlerocket#admin-container
enabled = true
# https://github.com/bottlerocket-os/bottlerocket-admin-container#authenticating-with-the-admin-container
user-data = "'$authorizedKeys'"
[settings.kubernetes]
# https://github.com/bottlerocket-os/bottlerocket-admin-container#authenticating-with-the-admin-container
standalone-mode = true
' > "$BRVM_USERDATAFILE"

end

function injectImageConfig
    log 1 "Injecting custom config in the Image"
    sudo mkdir /mnt/brvm
    set -l loopDevice (losetup -f)
    sudo losetup -P $loopDevice (realpath "$BRVM_IMAGE")
    sudo mount $loopDevice'p12' /mnt/brvm
    sudo cp "$BRVM_USERDATAFILE" /mnt/brvm
    sudo cp "$BRVM_NETWORKFILE" /mnt/brvm
    sudo umount -d $loopDevice'p12'
    sudo losetup -d $loopDevice
    sudo rm -fr /mnt/brvm
end

function createVM
    log 1 "Creating VM with VirtualBox"

    log 2 "Converting img to vdi disk"
    set -l vdiDisk (basename "$BRVM_IMAGE" .img)".vdi"
    if test -f $vdiDisk
        echo "(WW) Old $vdiDisk detected, REMOVING!"
        rm -f $vdiDisk
    end
    VBoxManage convertfromraw --format VDI $BRVM_IMAGE $vdiDisk

    log 2 "Registering vm as $BRVM_NAME"
    if test -d $BRVM_NAME
        echo "(WW) $BRVM_NAME vm found. REMOVING!"
        rm -fr $BRVM_NAME
    end
    VBoxManage createvm --name $BRVM_NAME --ostype Linux26_64 --register --basefolder $PWD

    log 2 "Customize options"
    log 3 "ioapic on"
    VBoxManage modifyvm $BRVM_NAME --ioapic on
    log 3 "memory 1024, vram 128"
    VBoxManage modifyvm $BRVM_NAME --memory 1024 --vram 128
    log 3 "nic1 in nat mode"
    VBoxManage modifyvm $BRVM_NAME --nic1 nat

    log 2 "Configure disk"
    VBoxManage storagectl $BRVM_NAME --name "SATA Controller" --add sata --controller IntelAhci
    VBoxManage storageattach $BRVM_NAME --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium  $PWD/$vdiDisk

    log 2 "SSH Port forwarding $BRVM_SSH_PORTNAT->22"
    VBoxManage modifyvm $BRVM_NAME --natpf1 "ssh,tcp,,$BRVM_SSH_PORTNAT,,22"
end

function startVM
    log 1 "First VM starting"
    VBoxManage startvm $BRVM_NAME --type headless

    log 2 "Saving VM info in $BRVM_NAME.txt"
    VBoxManage showvminfo $BRVM_NAME --machinereadable > $BRVM_NAME.txt

    log 2 "Waiting $BRVM_WAIT_FOR_VM_UP seconds to ensure VM was started"
    sleep $BRVM_WAIT_FOR_VM_UP

    log 2 "Running sudo sheltie"
    ssh -i ./$BRVM_SSHKEY_PREFIX -p $BRVM_SSH_PORTNAT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t ec2-user@127.0.0.1 "sudo sheltie"

    log 2 "Shutingdown VM"
    VBoxManage controlvm $BRVM_NAME acpipowerbutton
end

function nextSteps
    log 1 "Next steps"
    echo '
Now you can start the VM using VirtualBox GUI or Cli:

    VBoxManage startvm '$BRVM_NAME' --type headless

    To stop the VM you can use:

        VBoxManage controlvm '$BRVM_NAME' acpipowerbutton

Next command connect to the VM using ssh:

    ssh -i '$BRVM_WORKINGDIR/$BRVM_SSHKEY_PREFIX' -p '$BRVM_SSH_PORTNAT' -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t ec2-user@127.0.0.1

When you are logged in the VM you can enter in bottlerocket admin mode with:

    sudo sheltie

And now you will be able to start containers using ctr (containerd.io). For example to run echo-server

    ctr image pull docker.io/ealen/echo-server:latest
    ctr run -d --net-host docker.io/ealen/echo-server:latest test-echo

    If you enable port-forwarding from your 8080 to 80 in the VirtualBox config for '$BRVM_NAME' VM, you can test the
    service from your host with:

        curl http://localhost:8080

NOTE that --cni is not enabled because threre is not any CNI plugin installed by default. See for more info:

    * https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins
    * https://github.com/containerd/containerd/blob/main/script/setup/install-cni
    * https://github.com/containernetworking/plugins/tree/master/plugins/meta/portmap
'
end

argparse \
    'h/help' \
    'n/next-steps' \
-- $argv

if set -q _flag_h
    usage
    exit 0
end

if set -q _flag_n
    nextSteps
    exit 0
end

checkCommands
workinDir; or exit 1
installTools; or exit 1
vmImage; or exit 1
configureVM; or exit 1
injectImageConfig; or exit 1
createVM; or exit 1
startVM; or exit 1
nextSteps


if test "$BRVM_OLDWORKDIR" != ""
    cd $BRVM_OLDWORKDIR
end