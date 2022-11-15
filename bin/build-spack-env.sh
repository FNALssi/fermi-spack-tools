#!/bin/bash
########################################################################
# build-spack-env.sh
#
# Build an arbitrary Spack environment as configured by the specified
# YAML URL.
#
####################################
# Environment variables:
#
# WORKSPACE
#
####################################

prog="${BASH_SOURCE##*/}"
working_dir="${WORKSPACE:=$(pwd)}"
shopt -s extglob nullglob

usage() {
  cat <<EOF
usage: $prog 
EOF
}

_copy_back_logs() {
  local tar_tmp="$working_dir/copyBack/tmp"
  local spack_env= env_spec= install_prefix=
  mkdir -p "$tar_tmp"
  cd "$spack_env_top_dir"
  spack clean -dmp
  tar -c *.log *-out.txt *.yaml | tar -C "$tar_tmp" -x
  tar -C "$TMPDIR" -c spack-stage | tar -C "$tar_tmp" -x
  for spack_env in $(spack env list); do
    spack -e $spack_env \
          ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
          spec --format '{fullname}{/hash}' \
      | while read root_spec; do
      spack \
        ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
        find -d --no-groups \
        --format '{fullname}{/hash}'$'\t''{prefix}' \
        "$root_spec"
    done
  done \
    | sed -Ee 's&^[[:space:]]+&&' \
    | sort -u \
    | while read env_spec install_prefix; do
    if [ -d "$install_prefix/.spack" ]; then
      mkdir -p "$tar_tmp/$env_spec"
      tar -C "$install_prefix/.spack" -c . | tar -C "$tar_tmp/$env_spec" -x
    fi
  done
  tar -C "$tar_tmp" -jcf "$working_dir/copyBack/${BUILD_TAG:-spack-output}.tar.bz2" .
  rm -rf "$tar_tmp"
} 2>/dev/null

_do_build_and_test() {
  local spack_install_cmd=(
    spack
    -e $env_name
    ${__debug_spack_install:+-d}
    ${__verbose_spack_install:+-v}
    ${common_spack_opts[*]:+"${common_spack_opts[@]}"}
    install
    --fail-fast
    --only-concrete
    ${extra_install_opts[*]:+"${extra_install_opts[@]}"}
  )
  local extra_cmd_opts=
  (( is_nonterminal_compiler_env )) || extra_cmd_opts+=(${tests_arg:+"$tests_arg"})
  if ! (( is_nonterminal_compiler_env )) && [ "$tests_type" = "root" ]; then
    extra_cmd_opts+=(--no-cache) # Ensure roots are built even if in cache.
    # Identify and install non-root dependencies first.
    local root_spec_args=()
    # Identify all concrete specs
    OIFS="$IFS"; IFS=$'\n'
    local all_specs=(
      $(IFS="$OIFS" \
           spack -e $env_name \
           ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
           spec -NL \
          | sed -Ene '/^Concretized$/,/^$/ { /^(Concretized|-+)?$/ b; p;  }')
    )
    IFS="$OIFS"
    # Split each spec into hash and indent (=dependency) level,
    # identifying root hashes (level==0).
    local hashes=() root_hashes=() installed_deps=() levels=() \
          regex='^([^[:space:]]+)  (( *)\^)?([^[:space:]@+~%]*)'
    for specline in ${all_specs[*]:+"${all_specs[@]}"}; do
      [[ "$specline" =~ $regex ]] || continue
      local hash="${BASH_REMATCH[4]}/${BASH_REMATCH[1]}"
      hashes+=("$hash")
      levels+=(${#BASH_REMATCH[3]})
      (( ${#BASH_REMATCH[3]} == 0 )) && root_hashes+=("$hash")
    done
    # Sort root hashes for efficient checking.
    OIFS="$IFS"; IFS=$'\n'; root_hashes=($(echo "${root_hashes[*]}" | sort -u)); IFS="$OIFS"
    # Loop through all specs in reverse order (i.e. generally up each
    # dependency tree).
    local idx=${#hashes[@]}
    while (( idx )); do
      _piecemeal_build || return
    done
  else
    # Build the whole environment.
    echo "==> building environment $env_name"
    local spack_build_env_cmd=(
      "${spack_install_cmd[@]}"
      ${extra_cmd_opts[*]:+"${extra_cmd_opts[@]}"}
    )
    echo "      ${spack_build_env_cmd[*]}"
    "${spack_build_env_cmd[@]}"
  fi
}

# Test a hash to see whether it's present in a sorted list
_in_sorted_hashlist() {
  local hut="$1" ref_hash=
  shift
  for ref_hash in ${*:+"$@"}; do
    [ "$hut" = "$ref_hash" ] && return # true
    [[ "$ref_hash" < "$hut" ]] || return # Short circuit false
  done
  return 1 # Exhaustion false
}

_make_concretize_mirrors_yaml() {
  local out_file="$1"
  cp -p "$mirrors_cfg"{,~} \
    && cp "$default_mirrors" "$mirrors_cfg" \
    && spack \
         ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
         mirror add --scope=site __local_binaries "$working_dir/copyBack/spack-binary-mirror" \
    && spack \
         ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
         mirror add --scope=site __local_sources "$working_dir/copyBack/spack-source-mirror" \
    && cp "$mirrors_cfg" "$out_file" \
    && mv -f "$mirrors_cfg"{~,} \
      || { printf "ERROR: unable to generate concretization-specific mirrors.yaml at \"$out_file\"\n" 1>&2; exit 1; }
}

_piecemeal_build() {
  local buildable_dep_hashes=() build_root_hash=
  while (( idx-- )); do
    if _in_sorted_hashlist "${hashes[$idx]}" ${root_hashes[*]:+"${root_hashes[@]}"}; then
      build_root_hash="${hashes[$idx]}"
      _remove_root_hash "${hashes[$idx]}"
      break;
    fi
    # This is a dependency we should build.
    _in_sorted_hashlist "${hashes[$idx]}" ${installed_deps[*]:+"${installed_deps[@]}"}\
      || buildable_dep_hashes+=("${hashes[$idx]}")
  done
  # Uniquify hashes.
  OIFS="$IFS"; IFS=$'\n'
  buildable_dep_hashes=($(echo "${buildable_dep_hashes[*]}" | sort -u))
  IFS="$OIFS"
  # Build identified dependencies.
  if (( ${#buildable_dep_hashes[@]} )); then
    echo "==> building the following dependencies of root packages in environment $env_name:"
    OIFS="$IFS"; IFS=$'\n'; echo "${buildable_dep_hashes[*]/#/      }"; IFS="$OIFS"
    "${spack_install_cmd[@]}" ${buildable_dep_hashes[*]:+--no-add "${buildable_dep_hashes[@]//*\///}"} \
      || return
    # Add deps to list of installed deps.
    installed_deps+=(${buildable_dep_hashes[*]:+"${buildable_dep_hashes[@]}"})
  fi
  # Build identified root or the whole environment if we've run out of
  # intermediate roots to build.
  echo "==> building${build_root_hash:+ root package $build_root_hash in} environment $env_name"
  local spack_build_root_cmd=(
    "${spack_install_cmd[@]}" \
      ${extra_cmd_opts[*]:+"${extra_cmd_opts[@]}"} \
      ${build_root_hash:+--no-add "/${build_root_hash##*/}"}
  )
  echo "      ${spack_build_root_cmd[*]}"
  "${spack_build_root_cmd[@]}" || return
  installed_deps+=(${build_root_hash:+"$build_root_hash"})
  if (( ${#buildable_dep_hashes[@]} + ${#build_root_hash} )); then
    OIFS="$IFS"; IFS=$'\n'
    installed_deps=($(echo "${installed_deps[*]}" | sort -u))
    IFS="$OIFS"
  fi
  return 0
}

_process_environment() {
  local env_cfg="$1"
  if [[ "$env_cfg" =~ ^[a-z][a-z0-9_-]*://(.*/)?(.*) ]]; then
    curl -o "${BASH_REMATCH[2]}" --insecure --fail -L "$env_cfg" \
      || { printf "ERROR: unable to obtain specified environment config file \"$env_cfg\"\n" 1>&2; exit 1; }
    env_cfg="${BASH_REMATCH[2]}"
  fi
  env_name="${env_cfg##*/}"
  env_name="${env_name%.yaml}"
  env_name="${env_name//[^A-Za-z0-9_-.]/-}"
  env_name="${env_name##-}"
  spack \
    ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
    env rm -y $env_name >/dev/null 2>&1
  spack \
    ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
    env create --without-view $env_name "$env_cfg" \
    || { printf "ERROR: unable to create environment $env_name from $env_cfg\n" 1>&2; exit 1; }
  # Save logs and attempt to cache successful builds before we're killed.
  trap 'interrupt=$?; _copy_back_logs' HUP INT QUIT TERM
  # Copy our concretization-specific mirrors configuration into place to
  # prevent undue influence of external mirrors on the concretization
  # process.
  if (( concretize_safely )); then
    cp -p "$mirrors_cfg"{,~} \
      && cp "$concretize_mirrors" "$mirrors_cfg" \
        || { printf "ERROR: failed to install \"$concretize_mirrors\" prior to concretizing $env_name\n" 1>&2; exit 1; }
  fi
  local is_nonterminal_compiler_env=
  local env_spec="${env_cfg%.yaml}"
  env_spec="${env_spec##*/}"
  ####################################
  # If this environment is:
  #
  #   1. Not the last environment in the build list, and
  #
  #   2. a compiler environment
  #
  # then note that fact.
  (( num_environments > ++env_idx ))
    && [[ "$env_spec"  =~ ^$known_compilers_re([~+@%[:space:]].*)?$ ]] \
    && is_nonterminal_compiler_env=1
  ####################################

  ####################################
  # 1. Concretize the environment with a possibly restricted mirror
  #    list, restoring the original mirror list immediately afterward.
  # 2. Store the environment specs so they can be used by
  #       `spack buildcache create`
  # 3. Download and save sources to copyBack for mirroring.
  # 4. Install the environment.
  spack \
    -e $env_name \
    ${__debug_spack_concretize:+-d} \
    ${__verbose_spack_concretize:+-v} \
    ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
    concretize ${tests_arg:+"$tests_arg"} \
    && { ! (( concretize_safely )) || mv -f "$mirrors_cfg"{~,}; } \
    && spack \
         -e $env_name \
         ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
         spec -j \
      | csplit -f "$env_name" -b "_%03d.json" -z -s - '/^\}$/+1' '{*}' \
    && { ! (( cache_write_sources )) \
           || spack \
                -e $env_name \
                ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
                mirror create -aD --skip-unstable-versions -d "$working_dir/copyBack/spack-source-mirror"; } \
    && _do_build_and_test \
      || failed=1
  if [ -n "$interrupt" ]; then
    failed=1 # Trigger buildcache dump.
    printf "ABORT: exit due to caught signal ${interrupt:-(HUP, INT, QUIT or TERM)}\n" 1>&2
    if (( interrupt )); then
      exit $interrupt
    else
      exit 3
    fi
  fi
  (( failed == 0 )) \
    || { printf "ERROR: failed to build environment $env_name\n" 1>&2; exit $failed; }
  ####################################

  ####################################
  # Store all successfully-built packages in the buildcache
  if [ "${cache_write_binaries:-none}" != none ]; then
    for env_json in "${env_name}"_*.json; do
      spack \
        ${__debug_spack_buildcache:+-d} \
        ${__verbose_spack_buildcache:+-v} \
        ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
        buildcache create -a --deptype=all \
        ${extra_buildcache_opts[*]:+"${extra_buildcache_opts[@]}"} \
        -d "$working_dir/copyBack/spack-binary-mirror" \
        -r --spec-file "$env_json"
    done
    if [ "$cache_write_binaries" = "no_roots" ]; then
      for env_json in "${env_name}"_*.json; do
        spec="$(spack buildcache get-buildcache-name --spec-file "$env_json")"
        find "$working_dir/copyBack/spack-binary-mirror" -type f \( -name "$spec.spack" -o -name "$spec.json" -o -name "$spec.json.sig" \) -exec rm -f \{\} \;
      done
    fi  >/dev/null 2>&1
    spack \
      ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
      buildcache update-index -k -d "$working_dir/copyBack/spack-binary-mirror"
  fi
  ####################################

  ####################################
  # If we just built a non-terminal compiler environment, add the
  # compiler to the list of available compilers.
  if (( is_nonterminal_compiler_env )); then
    compiler_path="$( ( spack \
                    -e $env_name \
                     ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
                     location --install-dir "${env_spec}" ) )"
    status=$?
    (( $status == 0 )) \
      || { printf "ERROR: failed to extract path info for new compiler $env_spec\n" 1>&2; exit $status; }
    spack \
      ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
      compiler find "$compiler_path"
  fi
  ####################################
}

_remove_root_hash() {
  local handled_root="$1"
  local filtered_root_hashes=()
  for hash in ${root_hashes[*]:+"${root_hashes[@]}"}; do
    [ "$handled_root" = "$hash" ] || filtered_root_hashes+=("$hash")
  done
  root_hashes=(${filtered_root_hashes[*]:+"${filtered_root_hashes[@]}"})
}

_set_cache_write_binaries() {
  local wcb="$(echo "$1" | tr '[A-Z-]' '[a-z_]')"
  case $wcb in
    all|deps|dependencies|none|no_roots|roots) cache_write_binaries="$wcb";;
    *) printf "ERROR: unrecognized argument \"$1\" to --write-cache-binaries\n" 1>&2
       usage
       exit 1
  esac
}

_split_opts_impl() {
  local unbundling=1
  while (( $# )); do
    if (( unbundling )) && [[ "$1" =~ ^-[A-Za-z0-9#?]{2,}$ ]]; then
      local count=1
      while (( count < ${#1} )); do
        printf "%q\n" "-${1:$((count++)):1}"
      done
    else
      [ "$1" = -- ] && unbundling=
      printf "%q\n" "${1}"
    fi
    shift
  done
}

_ups_string_to_opt() {
  local ups_string="$(echo "$1" | tr '[A-Z]' '[a-z]')"
  local opt
  case $ups_string in
    -[utp]) opt="$ups_string";;
    plain|traditional|unified) opt="-${ups_string:0:1}";;
    *) printf "ERROR: unrecognized --ups option \"$1\"\n" 1>&2; exit 1
  esac
  printf -- "$opt\n";
}

########################################################################
# Main
########################################################################

# Sanity check.
if [ -n "$SPACK_ROOT" ]; then
  cat 1>&2 <<EOF
ERROR: cowardly refusing to initialize a Spack system with one
       already in the shell environment:

       SPACK_ROOT=$SPACK_ROOT

       $(spack env status)
EOF
  exit 1
fi

########################################################################
# To split bundled single-option arguments in your function or script:
#
#   eval "${ssi_split_options}"

{ ssi_split_options=$'declare OIFS="$IFS" IFS=$\'\n\r\' _ssi_opts_=
  read -a _ssi_opts_ -r -d \'\' < <(_split_opts_impl "$@")
  IFS="$OIFS"
  eval set -- "${_ssi_opts_[@]}"' # '
} 2>/dev/null
########################################################################

concretize_safely=1
si_root=https://github.com/FNALssi/spack-infrastructure.git
si_ver=master
spack_ver=v0.19.0-dev.fermi
spack_config_files=()
spack_config_cmds=()
cache_urls=()
ups_opt=-u

cache_write_binaries=all
#unset cache_write_bootstrap
cache_write_sources=1
common_spack_opts=(--backtrace --timestamp)

eval "$si_split_options"
while (( $# )); do
  case $1 in
    --cache-write-binaries=*) _set_cache_write_binaries "${1#*=}";;
    --cache-write-binaries) _set_cache_write_binaries "$2"; shift;;
    --cache-write-bootstrap) cache_write_bootstrap=1;;
    --cache-write-sources) cache_write_sources=1;;
    --clear-mirrors) clear_mirrors=1;;
    --debug-spack-*|--verbose-spack-*) eval "${1//-/_}=1";;
    --help) usage 2; exit 1;;
    --no-cache-write-binaries) cache_write_binaries=none;;
    --no-cache-write-bootstrap) unset cache_write_bootstrap;;
    --no-cache-write-sources) unset cache_write_sources;;
    --no-safe-concretize) unset concretize_safely;;
    --no-ups) ups_opt=-p;;
    --safe-concretize) concretize_safely=1;;
    --spack-config-cmd) spack_config_cmds+=("$2"); shift;;
    --spack-config-cmd=*) spack_config_cmds+=("${1#*=}");;
    --spack-config-file) spack_config_files+=("$2"); shift;;
    --spack-config-file=*) spack_config_files+=("${1#*=}");;
    --spack-infrastructure-root) si_root="$2"; shift;;
    --spack-infrastructure-root=*) si_root="${1#*=}";;
    --spack-infrastructure-version) si_ver="$2"; shift;;
    --spack-infrastructure-version=*) si_ver="${1#*=}";;
    --spack-root) spack_root="$2"; shift;;
    --spack-root=*) spack_root="${1#*=}";;
    --spack-version) spack_ver="$2"; shift;;
    --spack-version=*) spack_ver="${1#*=}";;
    --test) tests_type="$2"; shift;;
    --test=*) tests_type="${1#*=}";;
    --ups) ups_opt="$(_ups_string_to_opt "$2")" || exit; shift;;
    --ups=*) ups_opt="$(_ups_string_to_opt "${1#*=}")" || exit;;
    --with-cache) optarg="$2"; shift; OIFS="$IFS"; IFS=","; cache_urls+=($optarg); IFS="$OIFS";;
    --with-cache=*) optarg="${1#*=}"; OIFS="$IFS"; IFS=","; cache_urls+=($optarg); IFS="$OIFS";;
    --working-dir=*) working_dir="${1#*=}";;
    --working_dir) working_dir="$2"; shift;;
    -h) usage; exit 1;;
    --) shift; break;;
    -*) printf "ERROR unrecognized option $1\n$(usage)" 1>&2; exit 2;;
    *) break
  esac
  shift
done

spack_env_top_dir="$working_dir/spack_env"
mirrors_cfg="$spack_env_top_dir/etc/spack/mirrors.yaml"
default_mirrors="$spack_env_top_dir/etc/spack/defaults/mirrors.yaml"
concretize_mirrors="$working_dir/concretize_mirrors.yaml"

####################################
# Set up working area.
[ -n "$working_dir" ] || working_dir="${WORKSPACE:-$(pwd)}"
mkdir -p "$working_dir" || { printf "ERROR unable to ensure existence of working directory \"$working_dir\"\n" 1>&2; exit 1; }
cd "$working_dir" || { printf "ERROR unable to change to working directory \"$working_dir\"\n" 1>&2; exit 1; }
if [ -z "$TMPDIR" ]; then
  export TMPDIR="$working_dir/tmp"
  rm -rf "$TMPDIR"
  mkdir -p "$TMPDIR"
fi
####################################

case ${tests_type:=none} in
  all|none|root) : ;;
  *) printf "ERROR: unknown --test argument $tests_type\n" 1>&2; exit 1
esac

tests_arg=
if ! [ "$tests_type" = "none" ]; then
  tests_arg="--test=$tests_type"
fi


####################################
# Translate --cache-write-binaries opt into options to
#
#    `spack buildcache create`
case ${cache_write_binaries:=none} in
  all|none|no_roots) : ;;
  roots) extra_buildcache_opts+=(--only package);;
  dep*) extra_buildcache_opts+=(--only dependencies);;
  *) printf "ERROR: unknown --cache-write-binaries argument $cache_write_binaries\n" 1>&2; exit 1
esac
####################################

####################################
# Safe, comprehensive cleanup.
TMP=`mktemp -d -t build-spack-env.sh.XXXXXX`
trap "[ -d \"$TMP\" ] && rm -rf \"$TMP\" 2>/dev/null; \
[ -f \"$mirrors_cfg~\" ] && mv -f \"$mirrors_cfg\"{~,}; \
_copy_back_logs; \
if (( failed == 1 )) && [ \"${cache_write_binaries:-none}\" != none ]; then \
  printf \"ALERT: emergency buildcache dump...\\n\" 1>&2 ; \
  spack \
      \${common_spack_opts[*]:+\"\${common_spack_opts[@]}\"} \
      buildcache create -a --deptype=all \
      \${extra_buildcache_opts[*]:+\"\${extra_buildcache_opts[@]}\"} \
      -d \"$working_dir/copyBack/spack-binary-mirror\" \
      -r --rebuild-index \$(spack find --no-groups); \
  printf \"       ...done\\n\" 1>&2; \
fi\
" EXIT
####################################

si_upsver="v${si_ver#v}"
####################################
# Install spack-infrastructure to bootstrap a Spack installation.
git clone -b "$si_ver" "$si_root" "$TMP/" \
  || { printf "ERROR: unable to clone spack-infrastructure $si_ver from $si_root\n" 1>&2; exit 1; }
if [[ "${spack_config_files[*]}" =~ (^|/)packages\.yaml([[:space:]]|$) ]]; then
  # Bypass packages.yaml generation if we're going to ignore it anyway.
  ln -sf /usr/bin/true "$TMP/bin/make_packages_yaml"
else
  # Don't want externals from CVMFS.
  sed -Ei'' -e 's&^([[:space:]]+cprefix=).*$&\1'"''"'&' "$TMP/bin/make_packages_yaml"
fi
####################################

####################################
# Bootstrap the Spack installation.
mkdir -p "$spack_env_top_dir" \
  || { printf "ERROR: unable to make directory structure for spack environment installation\n" 1>&2; exit 1; }
cd "$spack_env_top_dir"
if ! [ -f "$spack_env_top_dir/setup-env.sh" ]; then
  make_spack_cmd=(make_spack --spack_release $spack_ver --minimal $ups_opt "$spack_env_top_dir")
  PATH="$TMP/bin:$PATH" ${make_spack_cmd[*]:+"${make_spack_cmd[@]}"} \
    || { printf "ERROR: unable to install Spack $spack_ver with\n          ${make_spack_cmd[*]}\n" 1>&2; exit 1; }
fi

# Clear mirrors list back to defaults.
(( clear_mirrors )) && cp "$default_mirrors" "$mirrors_cfg"

# Enhanced setup scripts.
if [ "$ups_opt" = "-p" ]; then
  cat >setup-env.sh <<EOF
. "$spack_env_top_dir/share/spack/setup-env.sh"
export SPACK_DISABLE_LOCAL_CONFIG=true
export SPACK_USER_CACHE_PATH="$spack_env_top_dir/tmp/spack-cache"
EOF
  cat >setup-env.csh <<EOF
source "$spack_env_top_dir/share/spack/setup-env.csh"
setenv SPACK_DISABLE_LOCAL_CONFIG true
setenv SPACK_USER_CACHE_PATH "$spack_env_top_dir/tmp/spack-cache"
EOF
fi
####################################

####################################
# Source the setup script.
source "$spack_env_top_dir/setup-env.sh" \
  || { printf "ERROR: unable to set up Spack $spack_ver\n" 1>&2; exit 1; }
####################################

####################################
# Configure Spack according to user specifications.
#
# 1. Extra / different config files.
for config_file in ${spack_config_files[*]:+"${spack_config_files[@]}"}; do
  cf_scope="${config_file%'|'*}"
  [ "$cf_scope" = "$config_file" ] && cf_scope=site
  config_file="${config_file##*'|'}"
  if [[ "$config_file" =~ ^[a-z][a-z0-9_-]*://(.*/)?(.*) ]]; then
    curl -o "${BASH_REMATCH[2]}" --insecure --fail -L "$config_file" \
      || { printf "ERROR: unable to obtain specified config file \"$config_file\"\n" 1>&2; exit 1; }
    config_file="${BASH_REMATCH[2]}"
  fi
  spack \
    ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
    config --scope=$cf_scope add -f "$config_file" \
    || { printf "ERROR: unable to add file obtained from \"$config_file\" to spack config with scope $cf_scope\n" 1>&2; exit 1; }
done
# 2. Spack config commands.
for config_cmd in ${spack_config_cmds[*]:+"${spack_config_cmds[@]}"}; do
  eval spack \
       ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
       config $config_cmd \
    || { printf "ERROR: executing spack config command \"$config_cmd\"\n" 1>&2; exit 1; }
done
# 3. Caches
for cache_spec in ${cache_urls[*]:+"${cache_urls[@]}"}; do
  if [[ "$cache_spec" =~ ^([^|]+)\|(.*)$ ]]; then
    cache_name="${BASH_REMATCH[1]}"
    cache_spec="${BASH_REMATCH[2]}"
  else
    cache_name="buildcache_$((++cache_count))"
  fi
  spack \
    ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
    mirror add --scope=site "$cache_name" "$cache_spec" \
    || { printf "ERROR: executing spack mirror add --scope=site $cache_name \"$cache_spec\n" 1>&2; exit 1; }
done

# Add mirror as buildcache for locally-built packages.
spack mirror add --scope=site __local_binaries "$working_dir/copyBack/spack-binary-mirror"
spack mirror add --scope=site __local_sources "$working_dir/copyBack/spack-source-mirror"

# Make a cut-down mirror configuration for safe concretization.
if (( concretize_safely )); then
  _make_concretize_mirrors_yaml "$concretize_mirrors"
fi
####################################

####################################
# Make sure we know about compilers.
spack compiler find --scope=site
####################################

####################################
# Execute bootstrap explicitly.
spack \
  ${__debug_spack_bootstrap:+-d} \
  ${__verbose_spack_bootstrap:+-v} \
  ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
  bootstrap now \
  || { printf "ERROR: unable to bootstrap safely with base configuration\n" 1>&2; exit 1; }
####################################

####################################
# Update our local public keys from configured build caches.
spack buildcache keys
####################################

####################################
# Initialize signing key for binary packages.
if [ -n "$SPACK_BUILDCACHE_SECRET" ]; then
  spack \
    -e $env_name \
    ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
    gpg trust "$SPACK_BUILDCACHE_SECRET"
  # Handle older Spack installations that need the long-format keyid.
  keyid="$(gpg2 --list-secret-keys --keyid-format long --homedir "$SPACK_ROOT/opt/spack/gpg" | sed -Ene '/^sec/{s&^[^/]+/([A-F0-9]+).*$&\1&p; q}')"
  extra_buildcache_opts+=(--key "$keyid")
else
  # Enable insecure mirror use.
  extra_buildcache_opts+=(-u)
  extra_install_opts+=(--no-check-signature)
fi
####################################

####################################
# Write bootstrap packages to cache.
if (( cache_write_bootstrap )); then \
  spack \
    ${__debug_spack_bootstrap:+-d} \
    ${__verbose_spack_bootstrap:+-v} \
    ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
    bootstrap mirror --binary-packages --dev "$working_dir/copyBack/spack-bootstrap-mirror" \
    || { printf "WARNING: unable to write bootstrap packages to local cache\n" 1>&2; }
fi
####################################

known_compilers=($(ls -1 "$SPACK_ROOT/lib/spack/spack/compilers/"[A-Za-z]*.py | sed -Ene 's&^.*/(.*)\.py$&\1&p'))
OIFS="$IFS"
IFS='|'
known_compilers_re="(${known_compilers[*]})"
IFS="$OIFS"

####################################
# Set up the build environment.
if ! [ "$ups_opt" = "-p" ]; then
  source /grid/fermiapp/products/common/etc/setups \
    || source /products/setup \
    || { printf "ERROR: unable to set up UPS\n" 1>&2; exit 1; }
  PRODUCTS="$spack_env_top_dir:$PRODUCTS"

  cd $TMP \
    && "$TMP/bin/declare_simple" spack-infrastructure $si_upsver \
      || { printf "ERROR: unable to declare spack-infrastructure $si_ver to UPS\n" 1>&2; exit 1; }
  cd - >/dev/null
fi
####################################

environment_specs=("$@")
num_environments=${#environment_specs}
env_idx=0

####################################
# Build each specified environment.
for env_cfg in ${environment_specs[*]:+"${environment_specs[@]}"}; do
  _process_environment "$env_cfg"
done
####################################

### Local Variables:
### mode: sh
### eval: (sh-set-shell "bash" t nil)
### End:
