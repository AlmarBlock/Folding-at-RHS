# Folding-at-RHS
This repository includes all the tools required to create and manage the Folding@Home servers of RHS.

## Management of the Server Cluster
- All cluster control is done through the official web portal: https://v8-4.foldingathome.org  
- The login information required for this site is stored at the school.  
- New machines should be added automatically if all configurations were set up correctly.

## Creating a new Server-ISO
To create a new ISO image that can be used to set up new servers, follow these steps:

### Prerequisites
- A working Debian 12 (Bookworm) installation  
- The root password for that installation (or a working sudo installation)

### 1. Cloning the project
Clone the contents of the *simple-cdd* folder to your Debian installation.

### 2. Installing necessary packages
Navigate to the location where you cloned the *simple-cdd* folder, then run:
```shell
chmod +x ./install.sh && ./install.sh
```
This will install all the necessary packages and add the selected user to the sudoers file.

### 3.1 Changing configurations (optional)
You can now modify the configuration files as needed.  
Files that likely need changes include:
- `simple-cdd.conf`
- `profiles/my.postinst` (to change the FAH token or FAH version)

### 3.2 Building the ISO-Image
Now run:
```shell
./build.sh
```
to create a new ISO image that can be used to deploy new servers for the Folding@RHS project.

### 4. Creating a bootable USB-Drive
After the build script completes successfully, you can find your new ISO image in the `./images` folder.
Use a tool such as [Rufus](https://rufus.ie/) to create a bootable USB drive from the ISO image.
