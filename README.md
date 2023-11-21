# CajonDesastre

It is formed by a set of useful tools and scripts that are not enough weight to form a own project


# `lxc-with-docker.fish`

Fish-shell script to create a Linux Container (lxd) with filesystem compatible with Docker. Thats you will be able to install docker into the container. Run `./lxc-with-docker.fish -h` for more information

`lxd` must be installed and configured in your system. Snap version of lxd it is the recommended one.

**Example**:

```sh
./lxc-with-docker.fish -cdemo --dnf -uuser -puser1234 -iimages:almalinux/8 --login
```

# `bottle-rocket-vm.fish`

Script and tools to create a BottleRocket VM with virtualbox inspired in [btiernay/create-mac-bottlerocket-virtualbox-vm.sh]https://gist.github.com/btiernay/5e4d62b126f28962cd008094e867e9a2

gist fork: [cyberluisda/create-mac-bottlerocket-virtualbox-vm.sh](https://gist.github.com/cyberluisda/73e68b744a20f1a78465ca1f6e37e393)

VM data will be created in `./vm-build.noback` by default

Run `./bottle-rocket-vm.fish -h` for more info

**Example**

```sh
./bottle-rocket-vm.fish
```
