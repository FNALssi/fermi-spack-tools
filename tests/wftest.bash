#!/bin/bash


case x$0 in
x/*)  testdir=$(dirname $0);;
x./*) testdir=$(dirname $PWD/${0:2});;
x*)   testdir=$(dirname $PWD/$0);;
esac
prefix=$(dirname $testdir)
ds=$(date +%s)

test_setup() {
    PATH=$prefix/bin:$PATH
}


hash_of() {
    spack buildcache list -al "$1" | 
       tail -1 | 
       sed -e 's/ .*//'
}

check_buildcache() {
    # after the whole sequence, our environment should have
    # the whole 
    spack cd --env
    ls -lR bc
}

do_cmd() {
    echo "-- $*"
    echo "=-=-=-=-=-=-=-=-=-=-=-="
    "$@"
    echo "=-=-=-=-=-=-=-=-=-=-=-="
}

test_one_release() {
    test_setup
    rel="$1"
    use_subspack=$2
    spdir="$PWD/test_${rel}_${ds}"
    sspdir="$PWD/test_sub${rel}_${ds}"
    log=${spdir}_out.txt
    
    (

    do_cmd bootstrap --spack_release $rel $spdir
    do_cmd . $spdir/setup-env.sh

    oss=$(spack arch -o)
    do_cmd spack install --cache-only gcc/$(hash_of "gcc@13.3.0 os=$oss")
    do_cmd spack install critic/$(hash_of "critic@2.14.00 os=$oss")
    
    if $use_subspack
    then
        # use the extension
        do_cmd spack subspack --with-padding $sspdir
    else
        # use the older script
        do_cmd make_subspack --with_padding $spdir $sspdir
    fi

    do_cmd . $sspdir/setup-env.sh

    do_cmd spack env create re_critic $prefix/tests/re_critic.spack.yaml
    do_cmd spack env activate re_critic
    do_cmd spack concretize
    do_cmd spack install
    do_cmd spack localbuildcache

    check_buildcache

    do_cmd spack env deactivate
    ) | tee -a $log
}

test_one_release v1.0.0-alpha.3 false

