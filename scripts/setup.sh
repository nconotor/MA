# Initial setup script. May be incomplete
apt install -y python3 python3-pandas python3-matplotlib build-essential libnuma-dev git gcc git make pkgconf autoconf automake bison flex m4 linux-headers-$(uname -r) libc6-dev
git clone git://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git
cd rt-tests
git checkout tags/v2.6
make all
make install
cd ..
git clone https://github.com/linux-test-project/ltp.git
cd ltp
make autotools
./configure
make 
make install