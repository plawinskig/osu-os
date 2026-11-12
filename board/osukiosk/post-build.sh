#!/bin/sh
# Buildroot post-build script for the main system
# (BR2_ROOTFS_POST_BUILD_SCRIPT). Buildroot runs it after every package
# is installed into the target directory and before the root filesystem
# image is made; $1 is that target directory.
#
# Removes LLVM, clang and SPIR-V files that reach the target only as a
# side effect of Buildroot's Mesa dependencies. The iris driver selects
# BR2_PACKAGE_MESA3D_NEEDS_PRECOMP_COMPILER, which selects Mesa's OpenCL
# support, which makes clang, libclc, the SPIR-V LLVM translator and
# SPIRV-Tools target packages. Mesa compiles its OpenCL C kernels on the
# host (host-mesa3d builds mesa_clc for that), so at run time it needs
# none of the files below: libgallium links only libLLVM and
# libSPIRV-Tools, which stay. Every removed library is used only by the
# command line tools removed with it (checked with readelf -d over the
# whole target). The rootfs is copied into RAM at boot, so this saves RAM
# and boot time on every machine: about 41 MB of the 104 MB squashfs.
#
# Packages are not reinstalled by an incremental build, so these files
# come back only when one of those packages is rebuilt, and then this
# script removes them again.

set -eu

TARGET_DIR=$1

# clang: diagtool is the only user of libclang-cpp, nothing uses libclang
rm -f \
	"$TARGET_DIR"/usr/lib/libclang.so* \
	"$TARGET_DIR"/usr/lib/libclang-cpp.so* \
	"$TARGET_DIR"/usr/bin/diagtool

# SPIR-V LLVM translator: llvm-spirv is the only user of the library
rm -f \
	"$TARGET_DIR"/usr/lib/libLLVMSPIRVLib.so* \
	"$TARGET_DIR"/usr/bin/llvm-spirv

# SPIRV-Tools: the spirv-* tools and the libraries only they use;
# libSPIRV-Tools.so itself is linked by libgallium
rm -f \
	"$TARGET_DIR"/usr/bin/spirv-* \
	"$TARGET_DIR"/usr/lib/libSPIRV-Tools-diff.so \
	"$TARGET_DIR"/usr/lib/libSPIRV-Tools-link.so \
	"$TARGET_DIR"/usr/lib/libSPIRV-Tools-lint.so \
	"$TARGET_DIR"/usr/lib/libSPIRV-Tools-opt.so \
	"$TARGET_DIR"/usr/lib/libSPIRV-Tools-reduce.so \
	"$TARGET_DIR"/usr/lib/libSPIRV-Tools-shared.so

# libclc: OpenCL C library bitcode, read only by an OpenCL implementation,
# and the image has none
rm -rf "$TARGET_DIR"/usr/share/clc
