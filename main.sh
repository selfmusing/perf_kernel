#!/usr/bin/env sh

set -e
set -o pipefail

# Changable Data
# ------------------------------------------------------------

# Kernel
KERNEL_NAME="Perf"
KERNEL_GIT="https://github.com/selfmusing/kernel_xiaomi_violet.git"
KERNEL_BRANCH="14"

# KernelSU
KERNELSU_REPO="selfmusing/USlenreK"
KSU_ENABLED="false"

# KernelSU Custom Manager
MANAGER_EXPECTED_SIZE="0x3a6"
MANAGER_EXPECTED_HASH="d06917e6deece7bf9b3278b1bb4ca4123c7d546bfebfd204915465804750bd03"

# Anykernel3
ANYKERNEL3_GIT="https://github.com/selfmusing/AnyKernel3.git"
ANYKERNEL3_BRANCH="master"

# Build
DEVICE_CODE="violet"
DEVICE_DEFCONFIG="vendor/violet-perf_deconfig"
COMMON_DEFCONFIG=""
DEVICE_ARCH="arch/arm64"

# Clang
CLANG_REPO="bachnxuan/aosp_clang_mirror"
CLANG_VERSION="clang-r574158-14475230"

# ------------------------------------------------------------

# Input Variables
if [[ $1 == "KSU" ]]; then
    KSU_ENABLED="true"
    echo "Input changed KSU_ENABLED to true"
elif [[ $1 == "NonKSU" ]]; then
    KSU_ENABLED="false"
    echo "Input changed KSU_ENABLED to false"
fi

if [[ $2 == "true" ]]; then
    KSU_MANAGER="true"
	echo "Input changed KSU_MANAGER to true"
elif [[ $2 == "false" ]]; then
    KSU_MANAGER="false"
	echo "Input changed KSU_MANAGER to false"
fi

if [[ $3 == *.git ]]; then
    KERNEL_GIT=$3
    echo "Input changed KERNEL_GIT to $3"
fi

if [[ $4 ]]; then
    KERNEL_BRANCH=$4
    echo "Input changed KERNEL_BRANCH to $4"
fi

if [[ $5 == *.git ]]; then
    ANYKERNEL3_GIT=$5
    echo "Input changed KERNEL_GIT to $5"
fi

if [[ $6 ]]; then
    DEVICE_CODE=$6
    echo "Input changed DEVICE_CODE to $6"
fi

if [[ $7 ]]; then
    DEVICE_DEFCONFIG=$7
    echo "Input changed DEVICE_DEFCONFIG to $7"
fi

if [[ $8 ]]; then
    COMMON_DEFCONFIG=$8
    echo "Input changed COMMON_DEFCONFIG to $8"
fi

# Set variables
WORKDIR="$(pwd)"

if [[ $CLANG_VERSION == "latest" ]]; then
    CLANG_DLINK="$(curl -s https://api.github.com/repos/$CLANG_REPO/releases/latest | grep "browser_download_url.*tar.gz" | cut -d '"' -f 4)"
else 
    CLANG_DLINK="$(curl -s https://api.github.com/repos/$CLANG_REPO/releases/tags/$CLANG_VERSION | grep "browser_download_url.*tar.gz" | cut -d '"' -f 4)"
fi
CLANG_DIR="$WORKDIR/Clang/bin"

KERNEL_REPO="${KERNEL_GIT::-4}/"
KERNEL_SOURCE="${KERNEL_REPO::-1}/tree/$KERNEL_BRANCH"
KERNEL_DIR="$WORKDIR/$KERNEL_NAME"

KERNELSU_SOURCE="https://github.com/$KERNELSU_REPO"
CLANG_SOURCE="https://github.com/$CLANG_REPO"
README="https://github.com/silvzr/bootlegger_kernel_archive/blob/master/README.md"

if [[ ! -z "$COMMON_DEFCONFIG" ]]; then
    DEVICE_DEFCONFIG=$8
    COMMON_DEFCONFIG=$7
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
git config --global http.postBuffer 524288000

msg "Cloning Clang and Kernel in parallel..."
# Kernel
(
    git clone --depth=10 $KERNEL_GIT --single-branch -b $KERNEL_BRANCH $KERNEL_DIR && cd $KERNEL_DIR && git reset --hard 106ec755faf9 && cd
) &
KERNEL_PID=$!

# Clang
(
    mkdir -p Clang
    aria2c -s16 -x16 -k1M $CLANG_DLINK -o Clang.tar.gz
    tar -C Clang/ -zxf Clang.tar.gz
    rm -rf Clang.tar.gz
) &
CLANG_PID=$!

wait $KERNEL_PID $CLANG_PID
msg "Clone completed"

CLANG_VERSION="$("$CLANG_DIR/clang" --version 2>&1 | sed -nE '1{s/.clang version ([0-9]+(.[0-9]+){1,}).(based on [^)])./\1 (\2)/p}')"
LLD_VERSION="$($CLANG_DIR/ld.lld --version | head -n 1 | cut -f1 -d "(" | sed 's/.$//')"

KERNEL_VERSION=$(cat $KERNEL_DIR/Makefile | grep -w "VERSION =" | cut -d '=' -f 2 | cut -b 2-)\
.$(cat $KERNEL_DIR/Makefile | grep -w "PATCHLEVEL =" | cut -d '=' -f 2 | cut -b 2-)\
.$(cat $KERNEL_DIR/Makefile | grep -w "SUBLEVEL =" | cut -d '=' -f 2 | cut -b 2-)
KERNEL_VER=$(echo $KERNEL_VERSION | cut -d. -f1,2)

msg "Kernel Version: $KERNEL_VERSION"

TITLE=$KERNEL_NAME-$KERNEL_VERSION

# Import patches
git submodule update --recursive --remote --init && msg "Importing patches..."

source ./patches/config.sh

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
AK3_DEVICE=$(grep -m 1 "device.name.*=$DEVICE_CODE" anykernel.sh | cut -d '=' -f 2)
DEVICE_DEFCONFIG_CODE=$(basename $DEVICE_DEFCONFIG | cut -d '_' -f 1 | cut -d '-' -f 1)
if [[ ! -z "$COMMON_DEFCONFIG" ]]; then
    COMMON_DEFCONFIG_CODE=$(basename $COMMON_DEFCONFIG | cut -d '.' -f 1 | cut -d '-' -f 1)
fi
if [[ $AK3_DEVICE != $DEVICE_CODE ]] && [[ $DEVICE_CODE == $DEVICE_DEFCONFIG_CODE || $DEVICE_CODE == $COMMON_DEFCONFIG_CODE ]]; then
    sed -i "s/device.name1=.*/device.name1=$DEVICE_CODE/" anykernel.sh
    sed -i "s/device.name2=.*/device.name2=/" anykernel.sh
    sed -i "s/device.name3=.*/device.name3=/" anykernel.sh
    sed -i "s/device.name4=.*/device.name4=/" anykernel.sh
    sed -i "s/device.name5=.*/device.name5=/" anykernel.sh
    msg "Wrong AnyKernel3 repo detected! Trying to fix it..."
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
- **[SuSFS](https://gitlab.com/simonpunk/susfs4ksu) Version**: $SUSFS_VERSION

<br>

- **[CLANG]($CLANG_SOURCE) Version**: $CLANG_VERSION
- **LLD Version**: $LLD_VERSION
" > bodyFile.md
echo "$TITLE" > name.txt
#echo "$KERNEL_NAME" > name.txt

# Finish
msg "Done"
