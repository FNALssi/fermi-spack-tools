#!/bin/bash

. ./unittest.bash

setup_1() {
   case "x$0" in
   x/*) export testdir=$(dirname $0) 
        ;;
   x./*) export testdir=$(dirname $(dirname $PWD/$0))
        ;;
   *)   export testdir=$(dirname $PWD/$0) 
        ;;
   esac
   export prefix=$(dirname $testdir)
   export workdir=${TMPDIR:-/tmp}/$USER/work$$
   mkdir -p $workdir
   export PATH=$prefix/bin:$PATH
   echo "setup_1: set workdir=$workdir, PATH=$PATH"
}
   

test_bootstrap_help() {
   bootstrap --help  > $workdir/out_help 2>&1

   # match the options in the output, should get all 6
   chk_re='[-]-(query-packages|with_padding|fermi_spack_tools_release|fermi_spack_tools_repo|fermi_spack_tools_release|spack_release|spack_repo)'
   test $(egrep "$chk_re" $workdir/out_help | wc -l) = 6
}

test_bootstrap_std() {
   bootstrap \
        --with_padding  \
        $workdir/sp_tst_std

   test -r $workdir/sp_tst_std/setup-env.sh
}

test_bootstrap_xmastree() {
   bootstrap \
        --query-packages \
        --with_padding  \
        --fermi_spack_tools_release main \
        --fermi_spack_tools_repo https://github.com/FNALssi/fermi-spack-tools.git \
        --spack_release HEAD \
        --spack_repo https://github.com/FNALssi/spack.git \
        $workdir/sp_tst_xmas

   test -r $workdir/sp_tst_xmas/setup-env.sh
}

testsuite boot_tst -s setup_1 test_bootstrap_help test_bootstrap_std test_bootstrap_xmastree

boot_tst "$@"
