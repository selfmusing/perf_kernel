#!/usr/bin/env sh

# Changable Data
# ------------------------------------------------------------

# Kernel
KERNEL_NAME="Perf"
KERNEL_GIT="https://github.com/selfmusing/kernel_xiaomi_violet.git"
KERNEL_BRANCH="14"

# KernelSU
KERNELSU_REPO="tiann/KernelSU"
KSU_ENABLED="false"

# Anykernel3
ANYKERNEL3_GIT="https://github.com/kibria5/AnyKernel3.git"
ANYKERNEL3_BRANCH="master"

# Build
DEVICE_CODE="violet"
DEVICE_DEFCONFIG="vendor/violet-perf_deconfig"
COMMON_DEFCONFIG=""
DEVICE_ARCH="arch/arm64"

# Clang
CLANG_REPO="ZyCromerZ/Clang"

# ------------------------------------------------------------

# Input Variables
if [[ $1 == "KSU" ]]; then
    KSU_ENABLED="true"
    echo "Input changed KSU_ENABLED to true"
elif [[ $1 == "NonKSU" ]]; then
    KSU_ENABLED="false"
    echo "Input changed KSU_ENABLED to false"
fi

if [[ $2 == *.git ]]; then
    KERNEL_GIT=$2
    echo "Input changed KERNEL_GIT to $2"
fi

if [[ $3 ]]; then
    KERNEL_BRANCH=$3
    echo "Input changed KERNEL_BRANCH to $3"
fi

if [[ $4 == *.git ]]; then
    ANYKERNEL3_GIT=$4
    echo "Input changed KERNEL_GIT to $4"
fi

if [[ $5 ]]; then
    DEVICE_CODE=$5
    echo "Input changed DEVICE_CODE to $5"
fi

if [[ $6 ]]; then
    DEVICE_DEFCONFIG=$6
    echo "Input changed DEVICE_DEFCONFIG to $6"
fi

if [[ $7 ]]; then
    COMMON_DEFCONFIG=$7
    echo "Input changed COMMON_DEFCONFIG to $7"
fi

# Set variables
WORKDIR="$(pwd)"

CLANG_DLINK="$(curl -s https://api.github.com/repos/$CLANG_REPO/releases/latest\
| grep -wo "https.*" | grep Clang-.*.tar.gz | sed 's/.$//')"
CLANG_DIR="$WORKDIR/Clang/bin"

KERNEL_REPO="${KERNEL_GIT::-4}/"
KERNEL_SOURCE="${KERNEL_REPO::-1}/tree/$KERNEL_BRANCH"
KERNEL_DIR="$WORKDIR/$KERNEL_NAME"

KERNELSU_SOURCE="https://github.com/$KERNELSU_REPO"
CLANG_SOURCE="https://github.com/$CLANG_REPO"
README="https://github.com/silvzr/bootlegger_kernel_archive/blob/master/README.md"

if [[ ! -z "$COMMON_DEFCONFIG" ]]; then
    DEVICE_DEFCONFIG=$7
    COMMON_DEFCONFIG=$6
fi

DEVICE_DEFCONFIG_FILE="$KERNEL_DIR/$DEVICE_ARCH/configs/$DEVICE_DEFCONFIG"
IMAGE="$KERNEL_DIR/out/$DEVICE_ARCH/boot/Image.gz"
DTB="$KERNEL_DIR/out/$DEVICE_ARCH/boot/dtb.img"
DTBO="$KERNEL_DIR/out/$DEVICE_ARCH/boot/dtbo.img"

export KBUILD_BUILD_USER=silvzr
export KBUILD_BUILD_HOST=GitHubCI

# Highlight
msg() {
	echo
	echo -e "\e[1;33m$*\e[0m"
	echo
}

cd $WORKDIR

# Setup
msg "Setup"

msg "Clang"
mkdir -p Clang
aria2c -s16 -x16 -k1M $CLANG_DLINK -o Clang.tar.gz
tar -C Clang/ -zxvf Clang.tar.gz
rm -rf Clang.tar.gz

CLANG_VERSION="$($CLANG_DIR/clang --version | head -n 1 | cut -f1 -d "(" | sed 's/.$//')"
CLANG_VERSION=${CLANG_VERSION::-3} # May get removed later
LLD_VERSION="$($CLANG_DIR/ld.lld --version | head -n 1 | cut -f1 -d "(" | sed 's/.$//')"

msg "Kernel"
git clone --depth=1 $KERNEL_GIT -b $KERNEL_BRANCH $KERNEL_DIR

KERNEL_VERSION=$(cat $KERNEL_DIR/Makefile | grep -w "VERSION =" | cut -d '=' -f 2 | cut -b 2-)\
.$(cat $KERNEL_DIR/Makefile | grep -w "PATCHLEVEL =" | cut -d '=' -f 2 | cut -b 2-)\
.$(cat $KERNEL_DIR/Makefile | grep -w "SUBLEVEL =" | cut -d '=' -f 2 | cut -b 2-)
# .$(cat $KERNEL_DIR/Makefile | grep -w "EXTRAVERSION =" | cut -d '=' -f 2 | cut -b 2-)

KERNEL_VER=$(echo $KERNEL_VERSION | cut -d. -f1,2)

msg "Kernel Version: $KERNEL_VERSION"

TITLE=$KERNEL_NAME-$KERNEL_VERSION

cd $KERNEL_DIR
KERNELSU_DIR=$(find . -mindepth 0 -maxdepth 4 \( -iname "ksu" -o -iname "kernelsu" \) -type d ! -path "*/.git/*" | cut -c3-)
KERNELSU_GITMODULE=$(grep -i "KernelSU" .gitmodules)

cd $WORKDIR

# Compare kernel versions in order to apply the correct patches
version_le() {
    [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ]
}

#

if [[ $KERNEL_VER == "4.14" ]]; then
    cp ./patches/strip_out_extraversion.patch $KERNEL_DIR/
    cd $KERNEL_DIR && patch -p1 < strip_out_extraversion.patch
    msg "4.14 detected! Removing openela tag..." && cd $WORKDIR
fi

msg "KernelSU"
if [[ $KSU_ENABLED == "true" ]] && [[ ! -z "$KERNELSU_DIR" ]]; then
    if [[ ! -z "$KERNELSU_GITMODULE" ]]; then
        cd $KERNEL_DIR && git submodule init && git submodule update
        msg "KernelSU submodule detected! Cloning..." && cd $WORKDIR
    fi    

    if version_le "$KERNEL_VER" "5.9"; then
    	cp ./patches/KernelSU/Backport/backport_path_umount.patch $KERNEL_DIR/
        cd $KERNEL_DIR && patch -p1 < backport_path_umount.patch
        msg "Backporting path_umount from 5.10.9..." && cd $WORKDIR
    fi

    cp ./patches/KernelSU/Backport/safe_mode_ksu.patch $KERNEL_DIR/
    cd $KERNEL_DIR && patch -p1 < safe_mode_ksu.patch
    msg "Backporting KSU safe mode..." && cd $WORKDIR
    
    if [[ -d "$KERNEL_DIR/$KERNELSU_DIR/kernel" ]]; then
    	cp  ./patches/KernelSU/SuSFS/enable_susfs_for_ksu_auto.patch $KERNEL_DIR/$KERNELSU_DIR/
    	cd $KERNEL_DIR/$KERNELSU_DIR && patch -p1 < enable_susfs_for_ksu_auto.patch
    else
    	cp ./patches/KernelSU/SuSFS/enable_susfs_for_ksu_manual.patch $KERNEL_DIR/$KERNELSU_DIR/
        cd $KERNEL_DIR/$KERNELSU_DIR && patch -p1 < enable_susfs_for_ksu_manual.patch
    fi
    	msg "Importing SuSFS into KSU source..." && cd $WORKDIR

    cp ./patches/KernelSU/SuSFS/add_susfs_in_kernel-$KERNEL_VER.patch $KERNEL_DIR/
    cp ./patches/KernelSU/SuSFS/susfs.c $KERNEL_DIR/fs/
    cp ./patches/KernelSU/SuSFS/susfs.h $KERNEL_DIR/include/linux/
    cd $KERNEL_DIR && patch -p1 -F 3 < add_susfs_in_kernel-$KERNEL_VER.patch
    msg "Importing SuSFS for $KERNEL_VER kernel..."

    echo "CONFIG_KSU=y" >> $DEVICE_DEFCONFIG_FILE
    echo "CONFIG_KSU_SUSFS=y" >> $DEVICE_DEFCONFIG_FILE

    if [[ ! -z "$KERNELSU_GITMODULE" ]]; then
        KSU_GIT_VERSION=$(cd KernelSU && git rev-list --count HEAD)
        KERNELSU_VERSION=$(($KSU_GIT_VERSION + 10200))
    else
        KERNELSU_VERSION=$(cat $KERNELSU_DIR/ksu.h | grep "KERNEL_SU_VERSION" | cut -c26-)
    fi

    msg "KernelSU Version: $KERNELSU_VERSION"
    sed -i "s/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION=\"-$KERNEL_BRANCH-$KERNEL_NAME-KSU\"/" $DEVICE_DEFCONFIG_FILE
elif
   [[ $KSU_ENABLED == "true" ]]; then
    cd $KERNEL_DIR && curl -LSs "https://raw.githubusercontent.com/$KERNELSU_REPO/main/kernel/setup.sh" | bash -s main
    cd $WORKDIR

    if version_le "$KERNEL_VER" "5.9"; then
    	cp ./patches/KernelSU/Backport/backport_path_umount.patch $KERNEL_DIR/
        cp ./patches/KernelSU/revert_drop_non_gki.patch  $KERNEL_DIR/KernelSU/
        cd $KERNEL_DIR && patch -p1 < backport_path_umount.patch
        msg "Backporting path_umount from 5.10.9..."
        cd $KERNEL_DIR/KernelSU && patch -p1 < revert_drop_non_gki.patch
        msg "Readding support for Non GKI kernels..." && cd $WORKDIR
    fi

    cp ./patches/KernelSU/Backport/hook_patches_ksu-$KERNEL_VER.patch $KERNEL_DIR/
    cd $KERNEL_DIR && patch -p1 < hook_patches_ksu-$KERNEL_VER.patch
    msg "Importing KSU hooks for $KERNEL_VER kernel..." && cd $WORKDIR

    cp ./patches/KernelSU/SuSFS/enable_susfs_for_ksu_auto.patch $KERNEL_DIR/KernelSU
    cd $KERNEL_DIR/KernelSU && patch -p1 < enable_susfs_for_ksu_auto.patch
    msg "Importing SuSFS into KSU source..." && cd $WORKDIR

    cp ./patches/KernelSU/SuSFS/add_susfs_in_kernel-$KERNEL_VER.patch $KERNEL_DIR/
    cp ./patches/KernelSU/SuSFS/susfs.c $KERNEL_DIR/fs/
    cp ./patches/KernelSU/SuSFS/susfs.h $KERNEL_DIR/include/linux/
    cd $KERNEL_DIR && patch -p1 < add_susfs_in_kernel-$KERNEL_VER.patch
    msg "Importing SuSFS into $KERNEL_VER kernel..."

    echo "CONFIG_KSU=y" >> $DEVICE_DEFCONFIG_FILE
    echo "CONFIG_KSU_SUSFS=y" >> $DEVICE_DEFCONFIG_FILE
    echo "CONFIG_KPROBES=n" >> $DEVICE_DEFCONFIG_FILE # it will conflict with KSU hooks if it's on

    KSU_GIT_VERSION=$(cd KernelSU && git rev-list --count HEAD)
    KERNELSU_VERSION=$(($KSU_GIT_VERSION + 10200))
    msg "KernelSU Version: $KERNELSU_VERSION"

    TITLE=$TITLE-$KERNELSU_VERSION
    sed -i "s/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION=\"-$KERNELSU_VERSION-$KERNEL_NAME\"/" $DEVICE_DEFCONFIG_FILE
fi
if [[ $KSU_ENABLED == "false" ]]; then
    echo "KernelSU Disabled"
    cd $KERNEL_DIR
    echo "CONFIG_KSU=n" >> $DEVICE_DEFCONFIG_FILE
    echo "CONFIG_KPROBES=n" >> $DEVICE_DEFCONFIG_FILE # just in case KSU is left on by default

    KERNELSU_VERSION="Disabled"
    sed -i "s/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION=\"-$KERNEL_NAME\"/" $DEVICE_DEFCONFIG_FILE
fi

# Build
msg "Build"

args="PATH=$CLANG_DIR:$PATH \
ARCH=arm64 \
SUBARCH=arm64 \
CROSS_COMPILE=aarch64-linux-gnu- \
CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
CC=clang \
LD=ld.lld \
LLVM=1 \
LLVM_IAS=1"

rm -rf out
make O=out $args $DEVICE_DEFCONFIG
if [[ ! -z "$COMMON_DEFCONFIG" ]]; then
  make O=out $args $COMMON_DEFCONFIG
fi
make O=out $args kernelversion
make O=out $args -j"$(nproc --all)"
msg "Kernel version: $KERNEL_VERSION"

# Package
msg "Package"
cd $WORKDIR
git clone --depth=1 $ANYKERNEL3_GIT -b $ANYKERNEL3_BRANCH $WORKDIR/Anykernel3
cd $WORKDIR/Anykernel3
AK3_DEVICE=$(grep "device.name.*=$DEVICE_CODE" anykernel.sh | cut -d '=' -f 2)
DEVICE_DEFCONFIG_CODE=$(basename $DEVICE_DEFCONFIG | cut -d '_' -f 1)
COMMON_DEFCONFIG_CODE=$(basename $COMMON_DEFCONFIG | cut -d '.' -f 1)
if [[ $AK3_DEVICE != $DEVICE_CODE ]] && [[ $DEVICE_CODE == $DEVICE_DEFCONFIG_CODE || $DEVICE_CODE == $COMMON_DEFCONFIG_CODE ]]; then
    sed -i "s/device.name1=.*/device.name1=$DEVICE_CODE/" anykernel.sh
    sed -i "s/device.name2=.*/device.name2=/" anykernel.sh
    sed -i "s/device.name3=.*/device.name3=/" anykernel.sh
    sed -i "s/device.name4=.*/device.name4=/" anykernel.sh
    sed -i "s/device.name5=.*/device.name5=/" anykernel.sh
fi
cp $IMAGE .
cp $DTB $WORKDIR/Anykernel3/dtb
cp $DTBO .

# Archive
mkdir -p $WORKDIR/out
if [[ $KSU_ENABLED == "true" ]]; then
  ZIP_NAME="$KERNEL_NAME-KSU.zip"
else
  ZIP_NAME="$KERNEL_NAME-NonKSU.zip"
fi
TIME=$(TZ='Europe/Berlin' date +"%Y-%m-%d %H:%M:%S")
find ./ * -exec touch -m -d "$TIME" {} \;
zip -r9 $ZIP_NAME *
cp *.zip $WORKDIR/out

# Release Files
cd $WORKDIR/out
msg "Release Files"
echo "
## [$KERNEL_NAME]($README)
- **Time**: $TIME # CET

- **Codename**: $DEVICE_CODE

<br>

- **[Kernel]($KERNEL_SOURCE) Version**: $KERNEL_VERSION
- **[KernelSU]($KERNELSU_SOURCE) Version**: $KERNELSU_VERSION

<br>

- **[CLANG]($CLANG_SOURCE) Version**: $CLANG_VERSION
- **LLD Version**: $LLD_VERSION
" > bodyFile.md
echo "$TITLE" > name.txt
#echo "$KERNEL_NAME" > name.txt

# Finish
msg "Done"
