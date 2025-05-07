#!/bin/bash
# Kernel Build Script for GitHub Actions

# Set Variables
TIMESTAMP=$(date +"%Y%m%d")
DATES=$(date +"%Y-%m-%d")
FW=RUI1
KSU=0  # KernelSU Setup (0 = No, 1 = Yes)
SUS_FS=0 # SuSFS Patches
USE_CUSTOM_GCC=1 # Use Custom GCC Toolchain (0 = No, 1 = Yes)
WIREGUARD=0 # Integrate wireguard (0 = No, 1 = yes)

# Get Telegram Bot Token and Chat ID from environment variables
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"

# Notify Telegram that cloning is starting
curl -X POST --silent --output /dev/null https://api.telegram.org/bot${BOT_TOKEN}/sendMessage -d chat_id=${CHAT_ID} -d text="|| Starting Cloning on Kernel Tree..."

# Sleep to give Telegram time to send message
sleep 10s

# Install Dependencies
echo "Installing dependencies..."
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y \
    nano bc bison ca-certificates curl flex gcc git libc6-dev \
    libssl-dev openssl python-is-python3 ssh wget zip zstd make \
    clang gcc-arm-linux-gnueabi software-properties-common build-essential \
    libarchive-tools gcc-aarch64-linux-gnu pigz python3 python2

# Clone Necessary Repositories
echo "Cloning repositories..."
git clone --depth=1 https://github.com/techyminati/android_prebuilts_clang_host_linux-x86_clang-5484270 clang
git clone --depth=1 https://github.com/Kavindu-Deshapriya/AnyKernel3 anykernel

# KernelSU Setup (If KSU is enabled)
if [[ $KSU == "1" ]]; then
    echo "Setting up KernelSU..."
    curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next/kernel/setup.sh" | bash -s -- --cleanup
    curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next/kernel/setup.sh" | bash -s next
    # curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s v0.9.5
fi

# Permissions Setup
echo "Setting permissions for all files..."
find . -type f -exec chmod 777 {} +

if [[ $SUS_FS == "1" ]]; then
    # Clone the SUSFS repository from GitLab
    echo "Cloning the SUSFS4KSU repository..."
    git clone --depth=1 --branch kernel-4.9 https://gitlab.com/simonpunk/susfs4ksu.git ./susfs4ksu
    # Apply the SUSFS patch
    echo "Applying SUSFS patches..."
    # Step 1: Copy the required patch files
    cp ./patches/KernelSU-Next-Implement-SUSFS-v1.5.5-Universal.patch ./KernelSU-Next/
    cp ./susfs4ksu/kernel_patches/50_add_susfs_in_kernel-4.9.patch ./
    cp ./susfs4ksu/kernel_patches/fs/* ./fs/
    cp ./susfs4ksu/kernel_patches/include/linux/* ./include/linux/
    # Step 2: Apply SUSFS patches
    echo "Patching KernelSU for SUSFS..."
    # cd ./KernelSU-Next
    # patch -p1 < KernelSU-Next-Implement-SUSFS-v1.5.5-Universal.patch
    # echo "Patching the Kernel for SUSFS..."
    # cd ..
    patch -p1 < 50_add_susfs_in_kernel-4.9.patch
    echo "Replacing fs/readdir.c with manually patched version..."
    cp patches/readdir.c fs/readdir.c
fi

# Custom GCC Setup (If enabled)
if [[ $USE_CUSTOM_GCC == "1" ]]; then
    echo "Cloning custom GCC toolchains..."
    git clone --depth=1 https://github.com/EternalX-project/aarch64-linux-gnu.git gcc64
    git clone --depth=1 https://github.com/EternalX-project/arm-linux-gnueabi.git gcc32
fi

if [[ $WIREGUARD == "1" ]]; then
    echo "Integrating Wireguard..."
    ./patches/patch-kernel.sh "$(pwd)"
fi

# Notify Telegram about the build start
curl -X POST --silent --output /dev/null https://api.telegram.org/bot${BOT_TOKEN}/sendMessage -d chat_id=${CHAT_ID} -d text="|| Building Kernel..."

# Build Kernel
export PATH="${PWD}/clang/bin:$PATH"
export CC="${PWD}/clang/bin/clang"
export KBUILD_BUILD_USER="Snowluna"
export KBUILD_BUILD_HOST="nefertari"

if [[ -d "gcc64" ]]; then
    echo "Using custom GCC toolchain for 64-bit..."
    make -j$(nproc --all) O=out ARCH=arm64 oppo6765_defconfig
    make -j$(nproc --all) ARCH=arm64 O=out CC="clang" CROSS_COMPILE="${PWD}/gcc64/bin/aarch64-linux-gnu-" CROSS_COMPILE_ARM32="${PWD}/gcc32/bin/arm-linux-gnueabi-"
else
    echo "Using default GCC toolchain..."
    make -j$(nproc --all) O=out ARCH=arm64 oppo6765_defconfig
    make -j$(nproc --all) ARCH=arm64 O=out CC="clang" CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi-
fi

# Check if Kernel is compiled successfully
if [[ -f "out/arch/arm64/boot/Image.gz-dtb" ]]; then
    # Notify Telegram that build was successful
    curl -X POST --silent --output /dev/null https://api.telegram.org/bot${BOT_TOKEN}/sendMessage -d chat_id=${CHAT_ID} -d text="|| Kernel Build Success! Waiting for zip file..."

    # Copy kernel image to AnyKernel directory
    cp ${PWD}/out/arch/arm64/boot/Image.gz-dtb ${PWD}/anykernel

    # Zip the kernel
    cd ${PWD}/anykernel
    zip -r9 "DiscussionVerse-${TIMESTAMP}-${FW}.zip" * -x .git README.md *placeholder
    cd ..

    # Create zip directory and move zipped kernel
    mkdir -p zipd
    mv ${PWD}/anykernel/DiscussionVerse-${TIMESTAMP}-${FW}.zip ${PWD}/zipd

    # Send the zipped kernel to Telegram
    curl -F chat_id=${CHAT_ID} -F document=@${PWD}/zipd/DiscussionVerse-${TIMESTAMP}-${FW}.zip -F caption="Zipping Kernel Done || Build Date: ${DATES}" "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument"
else
    echo "Kernel build failed"
    curl -X POST --silent --output /dev/null https://api.telegram.org/bot${BOT_TOKEN}/sendMessage -d chat_id=${CHAT_ID} -d text="|| Kernel Build Failed!"
    exit 1
fi

# End of script
