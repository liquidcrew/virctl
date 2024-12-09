# Virctl: Virtualization As Code

*Virctl* is a tool for system developers to deploy *QEMU/KVM*-based virtual machines on-demand easy and quickly.

The emergence of tools like *libvirt* and *cloud-init* has facilitated an ecosystem with better standardization and easier automation. With *libvirt*, you can automate the management of hosts and disk images based on different virtualization technologies using scripts. On the other hand, *cloud-init* offers a standardized way to configure operating systems during their initial boot. *cloud-init* is widely used in virtual machine images from major public and private cloud providers. The combination of these technologies has made it possible to create *Virctl*.

You can think of *Virctl* as a framework that includes business logic and predefined configurations that you can customize. Simply execute the [virctl.sh](virctl.sh) file, which contains all the business logic. Each instance of this repository supports only one virtual machine. To manage multiple virtual machines you can clone this repo several times. Then, you will be able to manage each virtual machine from the respective directory.

## ✔️ Dependencies

- [CPU with virtualization support](https://www.linux-kvm.org/page/Processor_support).

- [Virtualización enabled in host machine's UEFI/BIOS](https://bce.berkeley.edu/enabling-virtualization-in-your-pc-bios.html).

- [OS with Linux kernel](https://en.wikipedia.org/wiki/List_of_Linux_distributions) and [KVM module](https://www.linux-kvm.org/page/FAQ#What_kernel_version_does_it_work_with.3F).

- [Bridge utils](https://www.linuxfromscratch.org/blfs/view/cvs/basicnet/bridge-utils.html): Utilities for configuring the Linux ethernet bridge.

- [QEMU](https://www.qemu.org/): Machine emulator and virtualizer.

- [libguestfs](https://www.libguestfs.org/): Toolset for accessing and modifying VM images.

- [Libvirt](https://libvirt.org/): Toolkit to manage virtualization platforms.

- [virt-install](https://github.com/virt-manager/virt-manager/blob/main/virt-install  ): Toolkit to manage virtualization platforms.

- [yq](https://github.com/kislyuk/yq): Implementation of yq written by Andrey Kislyuk.

### Dependency installation in GNU/Linux:

Follow the instructions for your *GNU/Linux* distribution to install the dependencies.

#### ArchLinux | EndeavourOS | Manjaro:

```shell
sudo pacman -Syu bridge-utils qemu-base libguestfs libvirt virt-install yq
sudo setfacl -m u:libvirt-qemu:rx ~
sudo usermod -a -G libvirt $(whoami)
sudo bash -c 'export LIBVIRT_DEFAULT_URI="qemu:///system" > ~/.zhsenv'
source ~/.zhsenv
virsh net-autostart default
virsh net-start default
```

## 🚀 Quick start

> 💡 *Virctl* comes pre-configured so you can use it right now.️ It assumes that you have a network bridge named `virbr0` with the IP address `192.168.122.1`.

Deploy a virtual machine:

```
./virctl.sh deploy
```

Connect to the virtual machine:

```
./virctl.sh shell-ssh
```

Details of the pre-configured virtual machine:

| Name         | debian-vm          |
| ------------ | ------------------ |
| OS           | Debian 11          |
| CPUs         | 1                  |
| Memory       | 512 MB             |
| Disk size    | 4 GB               |
| User         | tux                |
| Password     | P4ssW0rd..         |
| Auth methods | Password, SSH keys |
| IP address   | 192.168.122.122    |
| SSH port     | 22                 |

## 📖 Usage

Run the `virctl.sh` script with with the `help` action to show the usage documentation:

```
❯ ./virctl.sh help
help: ./virctl.sh <action>
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
Example: ./virctl.sh deploy
```

## 🪛 Configuration

The various features of the virtual machine are configured in different files within the repository. This is because *Virctl* leverages the *cloud-init* feature included in the cloud images for virtual machines.

Below, you will find information on how to configure the most important features of the virtual machine through different use cases.

### Virtual hardware and OS

The virtual hardware of the VM, such as the number of processors, the bridge device name or the size of assigned RAM memory, can be defined in the configuration file [virctl.yaml](virctl.yaml). The URI from which the virtual disk template will be downloaded is also defined here. It's a YAML-formatted file that accepts the following fields:

| Field    | Value type | Value description                                       |
| -------- | ---------- | ------------------------------------------------------- |
| name     | String     | Name to use as VM name and hostname                     |
| os       | String     | Short ID of OS. List of valid values: `osinfo-query os` |
| cpu      | Integer    | Number of CPUs                                          |
| mem_mb   | Integer    | Megabytes of RAM memory                                 |
| vd_gb    | Integer    | Size in gigabytes for the virtual disk of the VM        |
| vd_src   | String     | Remote URI of the virtual disk image template file      |
| bridge   | String     | Name of the bridge device to connect the VM             |
| mac_addr | String     | MAC address for VM's ethernet interface                 |

### Users

The settings for system users, such as password, public key, home directory, or shell, are defined in the [cloud-init/user-data.yaml](cloud-init/user-data.yaml) file. Within this file, there is an object called `users` that contains a list of all system users and their configurations. The first user is always `default`, which is the regular user included in the virtual disk image templates. The next user in the list is the one used by *Virctl* to interact with the virtual machine. When the virtual machine is deployed, SSH keys are generated for this user, and the value of its `ssh_authorized_keys` field is overwritten with the content of the newly created public key. This field is defined as an empty string when the virtual machine is undeployed. You can find more configurations in [this example](https://cloudinit.readthedocs.io/en/latest/reference/examples.html#including-users-and-groups). Please note that the configuration must follow the [cloud-config syntax](https://cloudinit.readthedocs.io/en/latest/explanation/format.html#cloud-config-data).

### System software

You can install additional software using the package manager provided by the operating system. This software is installed when the virtual machine is deployed. The configuration for the package manager and the packages to be installed is defined in the [cloud-init/user-data.yaml](cloud-init/user-data.yaml) file. You can refer to [this example](https://cloudinit.readthedocs.io/en/latest/reference/examples.html#install-arbitrary-packages) to learn more. Please note that the configuration must follow the [cloud-config syntax](https://cloudinit.readthedocs.io/en/latest/explanation/format.html#cloud-config-data).

### Network configuration

Network configurations, such as IP address, gateway, and DNS servers, among others, are defined in the [cloud-init/network-config.yaml](cloud-init/network-config.yaml) file. The value of the `macaddress` field is automatically set (Using the value of the `mac_addr` field of [virctl.yaml](virctl.yaml)) when the virtual machine is deployed and it's defined as an empty string when the virtual machine is undeployed. You can refer to [this example](https://cloudinit.readthedocs.io/en/latest/reference/network-config-format-v2.html#examples) or read the [network-config documentation](https://cloudinit.readthedocs.io/en/latest/reference/network-config.html) to learn more.

### Hostname

The hostname is defined in the [cloud-init/meta-data.yaml](cloud-init/meta-data.yaml) file. The valid fields for this file are the same as those used by the [EC2 metadata service](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html#instance-metadata-ex-2) in AWS. You can refer to [this example](https://cloudinit.readthedocs.io/en/latest/reference/datasources/nocloud.html#example-meta-data) or read the [file formats documentation](https://cloudinit.readthedocs.io/en/latest/reference/datasources/nocloud.html#file-formats) to learn more.

### Run commands on first boot

If you need to run specific commands from a terminal during the virtual machine deployment, you can define them in the [cloud-init/user-data.yaml](cloud-init/user-data.yaml) file. You can refer to [this example](https://cloudinit.readthedocs.io/en/latest/reference/examples.html#run-commands-on-first-boot) to learn more. Please note that the configuration must follow the [cloud-config syntax](https://cloudinit.readthedocs.io/en/latest/explanation/format.html#cloud-config-data).

### Additional configurations

Documentation has [more examples](https://cloudinit.readthedocs.io/en/latest/reference/examples.html) available for different use cases.

### Cloud config syntax validation

You don't need to deploy a new virtual machine every time you want to validate configuration files based on *cloud-config* syntax, in this case, the [cloud-init/user-data.yaml](cloud-init/user-data.yaml) file. The *cloud-init* program allows you to check the syntax correctness and provides additional information in case of errors.

If you want to use *cloud-init* to validate the files, you will need to install it according to the documentation provided by your Linux-based operating system. I haven't included it in the [Requirements](#Requirements) section because *cloud-init* is not strictly necessary for *Virctl* to work.

Run the following command to validate *cloud-config* formatted files:

```
cloud-init schema --config-file <file-name>
```

## 🔌 Compatibility

> 💡 Please note that these are the tested images, and *Virctl* may also work with other compatible images.

*Virctl* has been tested with the following images:

- [AlmaLinux 9 GenericCloud AMD64](https://alma.mirror.ate.info/9.1/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2)

- [Debian GNU/Linux 11 Bullseye Generic AMD64](https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2)

- [Ubuntu Server 22.04 LTS (Jammy Jellyfish) CloudImg AMD64](https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64-disk-kvm.img)

- [Arch Linux 20230627.160762 CloudImg AMD64](https://gitlab.archlinux.org/archlinux/arch-boxes/-/jobs/160762/artifacts/raw/output/Arch-Linux-x86_64-cloudimg-20230627.160762.qcow2)
