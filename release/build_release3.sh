#!/usr/bin/bash -e

export GIT_COMMITTER_NAME="Vehicle Researcher"
export GIT_COMMITTER_EMAIL="user@comma.ai"
export GIT_AUTHOR_NAME="Vehicle Researcher"
export GIT_AUTHOR_EMAIL="user@comma.ai"
export GIT_SSH_COMMAND="ssh -i /data/gitkey"

BUILD_DIR=/data/releasepilot
SOURCE_DIR="$(git rev-parse --show-toplevel)"

BRANCH=release3-staging

echo "[-] Setting up repo T=$SECONDS"
rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR
cd $BUILD_DIR
git init
git remote add origin git@github.com:commaai/openpilot.git
git checkout -f -B $BRANCH

# do the files copy
echo "[-] copying files T=$SECONDS"
cd $SOURCE_DIR
cp -pR --parents $(cat release/files_common) $BUILD_DIR/
cp -pR --parents $(cat release/files_tici) $BUILD_DIR/

# in the directory
cd $BUILD_DIR

rm -f panda/board/obj/panda.bin.signed

VERSION=$(cat selfdrive/common/version.h | awk -F\" '{print $2}')
echo "#define COMMA_VERSION \"$VERSION-$(git --git-dir=$SOURCE_DIR/.git rev-parse --short HEAD)-$(date '+%Y-%m-%dT%H:%M:%S')\"" > selfdrive/common/version.h

echo "[-] committing version $VERSION T=$SECONDS"
git add -f .
git commit -a -m "openpilot v$VERSION release"

# TODO: sign with release cert
# Build panda firmware
pushd panda/
scons -U .
mv board/obj/panda.bin.signed /tmp/panda.bin.signed
popd

# Build
export PYTHONPATH="$BUILD_DIR"
scons -j$(nproc)

# Run tests
#python selfdrive/manager/test/test_manager.py
selfdrive/car/tests/test_car_interfaces.py

# Cleanup
find . -name '*.a' -delete
find . -name '*.o' -delete
find . -name '*.os' -delete
find . -name '*.pyc' -delete
find . -name '__pycache__' -delete
rm -rf panda/board panda/certs panda/crypto
rm -rf .sconsign.dblite Jenkinsfile release/

# Move back signed panda fw
mkdir -p panda/board/obj
mv /tmp/panda.bin.signed panda/board/obj/panda.bin.signed

# Restore phonelibs
git checkout phonelibs/

# Mark as prebuilt release
touch prebuilt

# Add built files to git
git add -f .
git commit --amend -m "openpilot v$VERSION"

if [ ! -z "$PUSH" ]; then
  echo "[-] pushing T=$SECONDS"
  git remote set-url origin git@github.com:commaai/openpilot.git
  git push -f origin $BRANCH

  # Create dashcam
  git rm selfdrive/car/*/carcontroller.py
  git commit -m "create dashcam release from release"
  git push -f origin $BRANCH:dashcam3-staging
fi

echo "[-] done T=$SECONDS"
