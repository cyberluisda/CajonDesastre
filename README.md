# CajonDesastre

It is formed by a set of useful tools and scripts that are not enough weight to form a own project

# Tools

## `lxc-with-docker.fish`

Fish-shell script to create a Linux Container (lxd) with filesystem compatible with Docker. Thats you will be able to install docker into the container. Run `./lxc-with-docker.fish -h` for more information

`lxd` must be installed and configured in your system. Snap version of lxd it is the recommended one.

**Example**:

```sh
./lxc-with-docker.fish -cdemo --dnf -uuser -puser1234 -iimages:almalinux/8 --login
```
