#!/bin/bash

# get full path to our script
case x$0 in
x/*) this=$0 ;;
x*)  this=$PWD/$0 ;;
esac

#
# shell variables to use throughout...
#
prefix=$(dirname $(dirname $this))
basedir=/tmp/fst_test_dir_$$
spack_rel1=v0_20_0-fermi
spack_rel2=v0_22_0-fermi

# put us on the front of the PATH
PATH=$prefix/bin:$PATH

make_basedir() {
    mkdir $basedir
    cd $basedir
    set -x
}

cleanup_basedir() {
    cd $basedir/..
    rm -rf $basedir
}

test_make_spack() {
    inst=upstream

    cd $basedir
    rm -rf $inst 
    echo "test_make_spack" >&3
    which make_spack >&3
    make_spack -u --spack_release=$spack_rel1 $PWD/$inst 

    source $inst/setup-env.sh
    echo $SPACK_ROOT | grep $PWD/$inst 
    spack find | grep fermi-spack-tools
    spack compiler list | grep gcc
}

test_make_packages_yaml() {
    cd $basedir
    rm -rf just_packages
    make_packages_yaml $PWD/just_packages
    ls -lR just_packages
}

test_make_subspack () {
    inst=downstream

    cd $basedir
    rm -rf $inst
    make_subspack $PWD/upstream $PWD/$inst

    source $inst/setup-env.sh
    echo $SPACK_ROOT | grep $PWD/$inst 
    spack find | grep fermi-spack-tools
    spack compiler list | grep gcc
}

test_bootstrap () {
    inst=bootstrapped
    cd $basedir
    rm -rf $inst

    bootstrap $PWD/$inst

    source $inst/setup-env.sh
    echo $SPACK_ROOT | grep $PWD/$inst 
    spack find | grep fermi-spack-tools
    spack compiler list | grep gcc
}
test_declare_simple () {
    echo not implemented
}
test_initial_buildcache_packages () {
    echo not implemented
}
test_make_env_buildcache () {
    echo not implemented
}
test_sign_buildcache_image () {
    echo not implemented
}
test_spack_cycle_checker () {
    echo not implemented
}
test_spack_gem_wrapper () {
    echo not implemented
}
test_sync_from_jenkins_local () {
    echo not implemented
}
test_sync_from_jenkins_scisoft () {
    echo not implemented
}
test_un_ups_to_spack () {
    echo not implemented
}
test_update_spack () {
    echo not implemented
}
test_update_ups_to_spack () {
    echo not implemented
}
test_update_versions () {
    echo not implemented
}
test_ups_deps_to_spec () {
    echo not implemented
}
test_ups_to_spack () {
    echo not implemented
}

source ./unittest.bash

testsuite fermi_spack_tools_tests \
    -s make_basedir \
    -t cleanup_basedir \
    test_make_spack  \
    test_make_packages_yaml  \
    test_make_subspack  \
    test_bootstrap  \

fermi_spack_tools_tests "$@"
