#!/usr/bin/fish

# CONSTANTS
set DEFAULT_IMAGE "ubuntu:20.04"
set DEFAULT_STORAGE "docker"
set APT_PACKAGES "ca-certificates" "curl" "gnupg" "lsb-release" "fish" "neovim"
set -q INSTALL_EPEL_RELEASE || set INSTALL_EPEL_RELEASE "epel-release"
set -q INSTALL_REDHAT_LSB_CORE || set INSTALL_REDHAT_LSB_CORE "redhat-lsb-core"
set DNF_PACKAGES "ca-certificates" "tar" "sshpass" "curl" "gnupg" "fish" "neovim" "openssh-server"
set YUM_PACKAGES "ca-certificates" "curl" "gnupg" "fish" "neovim" "openssh-server"
set STORAGE_TYPE "btrfs"
set LOG_MSG_COLORS "yes"

function usage
    echo 'lxc-with-docker.fish
            [-h | --help]
            -cCONT_NAME | --container-name=CONT_NAME
            [-iIMAGE_NAME | --image=IMAGE_NAME]
            [-sSTORAGE_NAME | --storage-name=STORAGE_NAME]
            [-vVOL_NAME | --volume-name=VOL_NAME]
            [-dDEV_NAME | --device-name=DEV_NAME]
            [-uUSER_NAME | --user-name=USER_NAME]
            [-pPASSWORD | --password=PASSWORD]
            [--apt]
            [--dnf]
            [--yum]
            [--login]'

    echo '
Create a lxc container with CONT_NAME and image IMAGE_NAME and attach a VOL_NAME created in STORAGE_NAME of type btrfs

The VOL_NAME is attached to CONT_NAME as device with DEV_NAME name

If USER_NAME is defined then a user is created in the container identified by PASSWORD.

Other config:

    --apt. Install '(string join ', ' $APT_PACKAGES)' packages in the container with apt
    --dnf. Install '$INSTALL_EPEL_RELEASE', '(string join ', ' $DNF_PACKAGES)' packages in the container with dnf
    --yum. Install '$INSTALL_EPEL_RELEASE', '(string join ', ' $YUM_PACKAGES)' packages in the container with dnf
    --login. Enable to login with USER_NAME user when deployment will finish. It requires USER_NAME and PASSWORD are defined.
'
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

function createStorage
    log 1 'Storage: '$argv[1]
    log 2 'Checking if '$argv[1]' exists'
    if lxc storage list -f csv | grep -Pe '^'$argv[1]',' 2>&1 >/dev/null
        log 0 $argv[1]' found. Skiping'
        return
    end

    log 2 'Creating '$argv[1]' storage of '$STORAGE_TYPE' type'
    lxc storage create $argv[1] $STORAGE_TYPE
end

function createVol
    log 1 'Volume: '$argv[1]
    log 2 'Checking if '$argv[1]' exists in '$argv[2]
    if lxc storage volume list $argv[2] -f csv | grep -P '^[^,]+,'$argv[1]',' 2>&1 >/dev/null
        log 0 $argv[1]' found. Skipping'
        return
    end

    log 1 'Creating '$argv[1]' volume in '$argv[2]' storage'
    lxc storage volume create $argv[2] $argv[1]
end

function createContainer
    log 1 'Container: '$argv[1]
    log 2 'Checking if '$argv[1]' container exists'
    if lxc list $argv[1] -f csv | grep -P '^.+' 2>&1 >/dev/null
        log 0 $argv[1]' found. Nothing to do'
        exit 2
    end

    log 2 'Creating '$argv[1]' container with '$argv[2]' image'
    lxc launch $argv[2] $argv[1]
end

function attachVolume
    log 1 'Attaching volume as disk in '$argv[1]
    log 2 'Checking if devide '$argv[2]' is attached in '$argv[1]
    if lxc config device list | grep -P '^.+' 2>&1 >/dev/null
        log 0 $argv2' device found in '$argv[1]'. Skiping.'
        return
    end

    log 2 'Attaching '$argv[4]' (from '$argv[3]') to '$argv[1]' in /var/lib/docker with '$argv[2]' name'
    lxc config device add $argv[1] $argv[2] disk pool=$argv[3] source=$argv[4] path=/var/lib/docker
end

function configContainer
    log 1 'Configuring '$argv[1]
    log 2 'Config set to '$argv[1]
    lxc config set $argv[1] \
        security.nesting=true \
        security.syscalls.intercept.mknod=true \
        security.syscalls.intercept.setxattr=true

    log 2 'Restarting '$argv[1]
    lxc restart $argv[1]
    log 3 'Waiting 5 seconds to ensure container is restarted'
    sleep 5
end

function installPkgs
    log 1 'Installing packages in container'
    if test $argv[1] != ''
        log 2 'Installing '(string join ' ' $APT_PACKAGES)' with apt in '$argv[3]
        log 3 'Updating apt cache'
        lxc exec $argv[3] -- apt update
        lxc exec $argv[3] -- apt install -y $APT_PACKAGES

    end

    if test $argv[2] != ''
        log 2 'Installing '(string join ' ' $DNF_PACKAGES)' with dnf in '$argv[3]
        if test $INSTALL_EPEL_RELEASE != ""
            log 3 'Installing '$INSTALL_EPEL_RELEASE
            lxc exec $argv[3] -- dnf install -y $INSTALL_EPEL_RELEASE
        end
        if test $INSTALL_REDHAT_LSB_CORE != ""
            log 3 'Installing '$INSTALL_REDHAT_LSB_CORE
            lxc exec $argv[3] -- dnf install -y $INSTALL_REDHAT_LSB_CORE
        end
        lxc exec $argv[3] -- dnf install -y $DNF_PACKAGES
    end

    if test $argv[4] != ''
        log 2 'Installing '(string join ' ' $YUM_PACKAGES)' with dnf in '$argv[3]
        if test $INSTALL_EPEL_RELEASE != ""
            if lxc exec $argv[3] -- cat /etc/os-release | grep -Pe'^ID="amzn"' >/dev/null 2>&1
                log 3 'Amazon Linux distro detected. Install epel-release with amazon-linux-extras command'
                lxc exec $argv[3] -- amazon-linux-extras install epel -y
            else
                log 3 'Installing '$INSTALL_EPEL_RELEASE
                lxc exec $argv[3] -- yum install -y $INSTALL_EPEL_RELEASE
            end
        end
        if test $INSTALL_REDHAT_LSB_CORE != ""
            log 3 'Installing '$INSTALL_REDHAT_LSB_CORE
            lxc exec $argv[3] -- yum install -y $INSTALL_REDHAT_LSB_CORE
        end
        lxc exec $argv[3] -- yum install -y $YUM_PACKAGES
    end
end

function createUser
    log 1 'User: '$argv[1]
    if test $argv[1] = ''
        log 0 'Username is empty. Skipping'
    else

        if test $argv[2] = ''
            log -1 'Password empty user is not created.'
            return
        end

        set -l shell "/bin/bash"
        if lxc exec $argv[3] -- /bin/bash -c 'type -t "fish"' >/dev/null
            set shell "/usr/bin/fish"
        end

        log 2 'Creating '$argv[1]' user, with '$shell' shell'
        lxc exec $argv[3] -- useradd -m -s $shell $argv[1]

        log 2 'Setting password for '$argv[1]' user'
        echo "$argv[1]:$argv[2]" | lxc exec $argv[3] -- chpasswd

        log 2 'Adding '$argv[1]' to sudoers'
        if lxc exec $argv[3] -- cat /etc/sudoers | grep -Pe '^#includedir /etc/sudoers.d' >/dev/null 2>&1
            log 3 'includedir /etc/sudoers.d configured in sudoers'
        else
            mkdir -p /etc/sudoers.d
            chmod 740 /etc/sudoers.d
            lxc exec $argv[3] -- /bin/bash -c "echo '#includedir /etc/sudoers.d' > /etc/sudoers"
        end
        echo $argv[1]' ALL=(ALL) NOPASSWD: ALL' | lxc exec $argv[3] -- tee /etc/sudoers.d/50-$argv[1] > /dev/null
        lxc exec $argv[3] -- chmod 640 '/etc/sudoers.d/50-'$argv[1]

        log 0 'You are able to run lxc exec '$argv[2]' -- login '$argv[1]
    end
end

function logIn
    log 1 'Login: '$argv[2]
    if test "$argv[1]" != ""
        log 2 'Login in container '$argv[2]' with '$argv[1]' user'
        lxc exec $argv[2] -- login $argv[1]
    end
end

argparse \
        'h/help' \
        'c/container-name=' \
        'i/image=?' \
        's/storage-name=?' \
        'v/volume-name=?' \
        'd/device-name=?' \
        'u/user-name=?' \
        'p/password=?' \
        'apt' \
        'dnf' \
        'yum' \
        'login' \
    -- $argv

if set -q _flag_h
    usage
    exit 0
end
# Default values
if not set -q _flag_c
    echo '(EE) cotainer-name is mandatory'
    usage
    exit 1
end

# Default values
if test "$_flag_i" = ''
    set _flag_i $DEFAULT_IMAGE
end

if test "$_flag_s" = ''
    set _flag_s $DEFAULT_STORAGE
end
# By default the volume is the same as the container
if test "$_flag_v" = ''
    set _flag_v "$_flag_c"
end
# By default the attached device name is the same as the container
if test "$_flag_d" = ''
    set _flag_d "$_flag_c"
end

createContainer $_flag_c $_flag_i
createStorage $_flag_s
createVol $_flag_v $_flag_s
attachVolume $_flag_c $_flag_d $_flag_s $_flag_v
configContainer $_flag_c
installPkgs "$_flag_apt" "$_flag_dnf" $_flag_c "$_flag_yum"
createUser "$_flag_u" "$_flag_p" $_flag_c
if test "$_flag_login" != ''
    logIn "$_flag_u" $_flag_c
end