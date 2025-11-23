#!/bin/bash

set -e

usage() {
	cat <<EOF
Builds the tegra kernel with OOTM like a daily build.

Must set the following variables before running:
  OOTM_REPO     - Out-of-tree modules DKMS package repo to clone.
  OOTM_BRANCH   - Out-of-tree modules DKMS package repo branch to checkout.
  KERNEL_REPO   - Kernel git repo to clone.
  KERNEL_BRANCH - Kernel git repo branch to checkout.
EOF
	exit 1
}

if [ -z "$OOTM_REPO" ] \
   || [ -z "$OOTM_BRANCH" ] \
   || [ -z "$KERNEL_REPO" ] \
   || [ -z "$KERNEL_BRANCH" ]; then
	usage
fi

exit

TOPDIR=$PWD

KERNEL_REPO_NAME=$TOPDIR/kernel
OOTM_REPO_NAME=$TOPDIR/ootm

ARCH=arm64

# Install dependencies
sudo apt -y install git build-essential devscripts

# Export variables needed for Debian packaging operations
export DEBIAN_FRONTEND=noninteractive
export DEBFULLNAME="Tegra Builder"
export DEBEMAIL="tegra-builder@builder.local"

# Start OOTM

if ! [ -d "$OOTM_REPO_NAME" ]; then
	git clone "$OOTM_REPO" -b "$OOTM_BRANCH" --single-branch "$OOTM_REPO_NAME"
fi
cd $OOTM_REPO_NAME
git checkout $OOTM_BRANCH

ootm_srcpkg="$(dpkg-parsechangelog -SSource)"
ootm_branch=${ootm_srcpkg#tegra-oot-}

# Just use the autoincremented version, doesn't really matter
dch "OOTM development build"
dch -r "$(dpkg-parsechangelog -SDistribution)"
ootm_version="$(dpkg-parsechangelog -SVersion)"

# Need to generate control file so apt build-dep works
fakeroot debian/rules debian/control

ootm_bin_names="$(sed -n 's/^Package: //p' debian/control)"

sudo apt -y build-dep .
fakeroot debian/rules clean

debuild -b --no-sign

echo "OOTM dkms packages built successfully"

# End OOTM

# Start kernel

if ! [ -d "$KERNEL_REPO_NAME" ]; then
	git clone "$KERNEL_REPO" -b "$KERNEL_BRANCH" --single-branch "$KERNEL_REPO_NAME"
fi
cd $KERNEL_REPO_NAME
git checkout $KERNEL_BRANCH

# Generate dkms-versions
. debian/debian.env
cp debian.nvidia-tegra/dkms-versions $DEBIAN/dkms-versions
for b in $ootm_bin_names
do
	modulename=${b%-dkms}
	dkms_string="$modulename $ootm_version"
	dkms_string+=" modulename=$modulename"
	dkms_string+=" debpath=$(realpath $OOTM_REPO/../${b}_${ootm_version}_${ARCH}.deb)"
	dkms_string+=" arch=$ARCH"
	dkms_string+=" rprovides=$modulename-modules"
	dkms_string+=" rprovides=$b"
	dkms_string+=" buildheaders=true"
	dkms_string+=" type=standalone"

	echo "$dkms_string" >> $DEBIAN/dkms-versions
done

# Build the correct OOTM branch
sed -i -E "s/BRANCHES=.*/BRANCHES=$ootm_branch/" $DEBIAN/rules.d/$ARCH.mk

kver="$(dpkg-parsechangelog -SVersion | sed 's/-.*//')"
abi="$(date +"%Y%m%d%H%M" --utc).1"
dch -v "$kver-$abi" "Kernel development build"
dch -r "$(dpkg-parsechangelog -SDistribution)"

fakeroot debian/rules clean
sudo apt -y build-dep .

debuild -b --no-sign

echo "Kernel packages built successfully"

# End kernel
