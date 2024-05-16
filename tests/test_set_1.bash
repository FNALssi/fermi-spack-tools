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
spack_rel1=v0.21.0-fermi
spack_rel2=v0.22.0-fermi

# put us on the front of the PATH
PATH=$prefix/bin:$PATH

make_basedir() {
    mkdir $basedir
    cd $basedir
}

cleanup_basedir() {
    cd $basedir/..
    rm -rf $basedir
}


make_spack_args() {
    inst=upstream

    cd $basedir
    rm -rf $inst 
    echo "test_make_spack" >&3
    which make_spack >&3
    make_spack "$@" $PWD/$inst 

    echo make_spack returns $?

    source $inst/setup-env.sh           
    echo source returns $?
    echo $SPACK_ROOT | grep $PWD/$inst  
    echo SPACK_ROOT grep  returns $?
    spack find | grep fermi-spack-tools
    echo spack find  grep  returns $?
    spack find
    spack compiler list | grep gcc
    echo spack compiler list   grep  returns $?
    false
}

test_make_spack_u_1() {
 make_spack_args -u --spack_release=$spack_rel1 
}
test_make_spack_p_1() {
 make_spack_args -p --spack_release=$spack_rel1 
}
test_make_spack_u_2() {
 make_spack_args -u --spack_release=$spack_rel2 
}
test_make_spack_p_2() {
 make_spack_args -p --spack_release=$spack_rel2 
}
test_make_spack_u_1_p() {
 make_spack_args -u --spack_release=$spack_rel1 --with_padding 
}
test_make_spack_p_1_p() {
 make_spack_args -p --spack_release=$spack_rel1 --with_padding 
}
test_make_spack_u_2_p() {
 make_spack_args -u --spack_release=$spack_rel2 --with_padding 
}
test_make_spack_p_2_p() {
 make_spack_args -p --spack_release=$spack_rel2 --with_padding 
}

test_make_packages_yaml() {
    cd $basedir
    rm -rf just_packages
    make_packages_yaml $PWD/just_packages
    grep 'spec: "python' just_packages/etc/spack/linux/*/packages.yaml
}

test_make_subspack () {
    inst=downstream

    cd $basedir
    rm -rf $inst
    make_subspack $PWD/upstream $PWD/$inst

    source $inst/setup-env.sh           &&
    echo $SPACK_ROOT | grep $PWD/$inst  && 
    spack find | grep fermi-spack-tools &&
    spack compiler list | grep gcc
}

test_bootstrap () {
    inst=bootstrapped
    cd $basedir
    rm -rf $inst

    bootstrap $PWD/$inst

    source $inst/setup-env.sh           &&
    echo $SPACK_ROOT | grep $PWD/$inst  &&
    spack find | grep fermi-spack-tools &&
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
    test_make_spack_u_1 \

#    test_make_spack_p_1 \
#    test_make_spack_u_2 \
#    test_make_spack_p_2 \
#    test_make_spack_u_1_p \
#    test_make_spack_p_1_p \
#    test_make_spack_u_2_p \
#    test_make_spack_p_2_p \
#    test_make_packages_yaml  \
#    test_make_subspack  \
#    test_bootstrap  \

fermi_spack_tools_tests "$@"
