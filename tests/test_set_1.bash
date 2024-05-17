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
    inst=$1
    shift

    cd $basedir
    rm -rf $inst 
    echo "running: make_spack $*"
    make_spack "$@" $PWD/$inst             && echo make_spack succeeds &&
    ls -l $PWD/$inst                       && echo ls succeeeds &&
    source $inst/setup-env.sh              && echo setup-env succeeeds &&
    echo $SPACK_ROOT | grep -q $PWD/$inst  && echo SPACK_ROOT set && 
    spack compiler list | grep -q gcc      && echo found gcc compiler
}

test_make_spack_u_1() {
 make_spack_args upstream -v -u --minimal --spack_release=$spack_rel1 
}
test_make_spack_p_1() {
 make_spack_args upstream -v -p --minimal --spack_release=$spack_rel1 
}
test_make_spack_u_2() {
 make_spack_args upstream -v -u --minimal --spack_release=$spack_rel2 
}
test_make_spack_p_2() {
 make_spack_args upstream -v -p --minimal --spack_release=$spack_rel2 
}
test_make_spack_u_1_p() {
 make_spack_args upstream -v -u --minimal --spack_release=$spack_rel1 --with_padding 
}
test_make_spack_p_1_p() {
 make_spack_args upstream -v -p --minimal --spack_release=$spack_rel1 --with_padding 
}
test_make_spack_u_2_p() {
 make_spack_args upstream -v -u --minimal --spack_release=$spack_rel2 --with_padding 
}
test_make_spack_p_2_p() {
 make_spack_args upstream -v -p --minimal --spack_release=$spack_rel2 --with_padding 
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

    source $inst/setup-env.sh           && echo source ok &&
    echo $SPACK_ROOT | grep $PWD/$inst  && echo spack_root ok &&
    spack compiler list | grep gcc      && echo compilers ok 
}

test_bootstrap () {
    inst=bootstrapped
    cd $basedir
    rm -rf $inst

    bootstrap --spack_release $spack_rel1 $PWD/$inst  && echo bootstrap succeeded &&
    source $inst/setup-env.sh           && echo setup succeeded &&
    echo $SPACK_ROOT | grep $PWD/$inst  && echo spack root grep succeeded &&
    spack find | grep fermi-spack-tools && echo fermi-spack-tools succeeded &&
    spack compiler list | grep gcc      && echo grep compiler succeeded
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
test_dummy() {
  echo dummy
}

source ./unittest.bash

testsuite fermi_spack_tools_tests \
    -s make_basedir \
    -t cleanup_basedir \
    test_make_spack_u_1 \
    test_make_spack_p_1 \
    test_make_spack_p_2 \
    test_make_spack_u_2_p \
    test_make_spack_p_2_p \
    test_make_packages_yaml  \
    test_bootstrap  \
    test_make_subspack  \
    test_dummy


fermi_spack_tools_tests "$@"
