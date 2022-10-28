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
  mkdir -p "$tar_tmp"
  cd "$spack_env_top_dir"
  tar -c *.log *-out.txt *.yaml | tar -C "$tar_tmp" -x
  tar -C "$TMPDIR/spack-stage" . | tar -C "$tar_tmp" -x
  for spack_env in $(spack env list); do
    spack -e $spack_env spec --format '{fullname}{/hash}' | while read root_spec; do
      spack find -d --no-groups --format '{fullname}{/hash}'
    done
  done | sed -Ee 's&^[[:space:]]+&&' | sort -u | while read env_spec; do
    local install_prefix="$(spack location -i $env_spec)"
    if [ -d "$install_prefix/.spack" ]; then
      mkdir -p "$tar_tmp/$env_spec"
      tar -C "$install_prefix" -c .spack | tar -C "$tar_tmp/$env_spec" -x
    fi
  done
  tar -C "$tar_tmp" -jcf "$working_dir/copyBack/spack-output.tar.bz2" .
  rm -rf "$tar_tmp"
} 2>/dev/null

_make_concretize_mirrors_yaml() {
  local out_file="$1"
  cp -p "$mirrors_cfg"{,~} \
    && cp "$default_mirrors" "$mirrors_cfg" \
    && spack mirror add --scope=site local "$working_dir/copyBack" \
    && cp "$mirrors_cfg" "$out_file" \
    && mv -f "$mirrors_cfg"{~,} \
      || { printf "ERROR: unable to generate concretization-specific mirrors.yaml at \"$out_file\"\n" 1>&2; exit 1; }
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
# To split bundled single-option arguments in your function or script:
#
#   eval "${ssi_split_options}"

{ ssi_split_options=$'declare OIFS="$IFS" IFS=$\'\n\r\' _ssi_opts_=
  read -a _ssi_opts_ -r -d \'\' < <(_split_opts_impl "$@")
  IFS="$OIFS"
  eval set -- "${_ssi_opts_[@]}"' # '
} 2>/dev/null
########################################################################

si_root=https://github.com/FNALssi/spack-infrastructure.git
si_ver=master
spack_ver=v0.19.0-dev.fermi
spack_config_files=()
spack_config_cmds=()
cache_urls=()
ups_opt=-u

eval "$si_split_options"
while (( $# )); do
  case $1 in
    -h) usage; exit 1;;
    --help)  usage 2; exit 1;;
    --no-cache) unset cache_urls;;
    --no-ups) ups_opt=-p;;
    --spack-config-file=*) spack_config_files+=("${1#*=}");;
    --spack-config-file) spack_config_files+=("$2"); shift;;
    --spack-infrastructure-root=*) si_root="${1#*=}";;
    --spack-infrastructure-root) si_root="$2"; shift;;
    --spack-infrastructure-version=*) si_ver="${1#*=}";;
    --spack-infrastructure-version) si_ver="$2"; shift;;
    --spack-version=*) spack_ver="${1#*=}";;
    --spack-version) spack_ver="$2"; shift;;
    --ups=*) ups_opt="$(_ups_string_to_opt "${1#*=}")" || exit;;
    --ups) ups_opt="$(_ups_string_to_opt "$2")" || exit; shift;;
    --with-cache=*) optarg="${1#*=}"; OIFS="$IFS"; IFS=","; cache_urls+=($optarg); IFS="$OIFS";;
    --with-cache) optarg="$2"; shift; OIFS="$IFS"; IFS=","; cache_urls+=($optarg); IFS="$OIFS";;
    --working-dir=*) working_dir="${1#*=}";;
    --working_dir) working_dir="$2"; shift;;
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
TMP=`mktemp -d -t build-spack-env.sh.XXXXXX`

# Safe, comprehensive cleanup.
trap "[ -d \"$TMP\" ] && rm -rf \"$TMP\" 2>/dev/null; \
[ -f \"$mirrors_cfg~\" ] && mv -f \"$mirrors_cfg\"{~,}; \
_copy_back_logs" EXIT

####################################
# Set up working area.
[ -n "$working_dir" ] || working_dir="${WORKSPACE:-$(pwd)}"
mkdir -p "$working_dir" || { printf "ERROR unable to ensure existence of working directory \"$working_dir\"\n" 1>&2; exit 1; }
cd "$working_dir" || { printf "ERROR unable change to working directory \"$working_dir\"\n" 1>&2; exit 1; }
if [ -z "$TMPDIR" ]; then
  export TMPDIR="$working_dir/tmp"
  rm -rf "$TMPDIR"
  mkdir -p "$TMPDIR"
fi
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
source "$spack_env_top_dir/setup-env.sh" \
  || { printf "ERROR: unable to set up Spack $spack_ver\n" 1>&2; exit 1; }
spack compiler find --scope=site
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
  spack config --scope=$cf_scope add -f "$config_file" \
    || { printf "ERROR: unable to add file obtained from \"$config_file\" to spack config with scope $cf_scope\n" 1>&2; exit 1; }
done
# 2. Spack config commands.
for config_cmd in ${spack_config_cmds[*]:+"${spack_config_commands[@]}"}; do
  eval spack config add $config_cmd \
    || { printf "ERROR: executing spack config command \"$config_cmd\"\n" 1>&2; exit 1; }
done
# 3. Caches
if [ -n "$SPACK_BUILDCACHE_SECRET" ]; then
  keyid="$(spack gpg trust "$SPACK_BUILDCACHE_SECRET" | sed -Ene '1 s&^gpg: key ([^:]+).*$&\1&p')"
  extra_buildcache_opts+=(--key "$keyid")
else
  extra_buildcache_opts+=(-u)
  extra_install_opts+=(--no-check-signature)
fi
if [ -z "${cache_urls+x}" ] \
     && { spack mirror list | grep -qEe '^fnal[[:space:]]+'; } >/dev/null 2>&1; then
  spack mirror rm --scope site fnal \
    || { printf "ERROR: executing spack mirror rm --scope site fnal\n" 1>&2; exit 1; }
else
  for cache_spec in ${cache_urls[*]:+"${cache_urls[@]}"}; do
    if [[ "$cache_spec" =~ ^([^|]+)|(.*)$ ]]; then
      cache_name="${BASH_REMATCH[1]}"
      cache_spec="${BASH_REMATCH[2]}"
    else
      cache_name="buildcache_$((++cache_count))"
    fi
    spack mirror add --scope=site $cache_name "$cache_spec" \
      || { printf "ERROR: executing spack mirror add --scope=site $cache_name \"$cache_spec\n" 1>&2; exit 1; }
  done
fi

# Add mirror as buildcache for locally-built packages.
spack mirror add --scope=site local "$working_dir/copyBack"
spack buildcache keys
####################################

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

_make_concretize_mirrors_yaml "$concretize_mirrors"

for env_cfg in "$@"; do
  if [[ "$env_cfg" =~ ^[a-z][a-z0-9_-]*://(.*/)?(.*) ]]; then
    curl -O "${BASH_REMATCH[2]}" --insecure --fail -L "$env_cfg" \
      || { printf "ERROR: unable to obtain specified environment config file \"$env_cfg\"\n" 1>&2; exit 1; }
    env_cfg="${BASH_REMATCH[2]}"
  fi
  env_name="${env_cfg##*/}"
  env_name="${env_name%.yaml}"
  env_name="${env_name//[^A-Za-z0-9_-.]/-}"
  env_name="${env_name##-}"
  spack env rm -y $env_name >/dev/null 2>&1
  spack env create $env_name "$env_cfg" \
    || { printf "ERROR: unable to create environment $env_name from $env_cfg\n" 1>&2; exit 1; }
  # Save logs and attempt to cache successful builds before we're killed.
  trap 'interrupt=$?; _copy_back_logs' HUP INT QUIT TERM
  # Copy our concretization-specific mirrors configuration into place to
  # prevent undue influence of external mirrors on the concretization
  # process.
  cp -p "$mirrors_cfg"{,~} \
    && cp "$concretize_mirrors" "$mirrors_cfg" \
      || { printf "ERROR: failed to install \"$concretize_mirrors\" prior to concretizing $env_name\n" 1>&2; exit 1; }
  # 1. Concretize the environment with a restricted mirror list.
  # 2. Restore the original mirror list.
  # 3. Store the environment specs so they can be used by
  #       `spack buildcache create`
  # 4. Install the environment.
  spack -e $env_name concretize --test=root \
    && mv -f "$mirrors_cfg"{~,} \
    && spack -e $env_name spec -j \
      | csplit -f "$env_name" -b "_%03d.json" -z -s - '/^\}$/+1' '{*}' \
    && spack -e $env_name install ${extra_install_opts[*]:+"${extra_install_opts[@]}"} --test=root \
      || failed=1
  # Store all successfully-built packages in the buildcache
  for env_json in "${env_name}"_*.json; do
    spack buildcache create -a --deptype=all \
          ${extra_buildcache_opts[*]:+"${extra_buildcache_opts[@]}"} \
          -d "$working_dir/copyBack" \
          -r --rebuild-index --spec-file "$env_json"
  done
  if [ -n "$interrupt" ]; then
    printf "ABORT: exit due to caught signal ${interrupt:-(HUP, INT, QUIT or TERM)}\n" 1>&2
    if (( interrupt )); then
      exit $interrupt
    else
      exit 3
    fi
  fi
  (( failed == 0 )) \
    || { printf "ERROR: failed to build environment $env_name\n" 1>&2; exit $failed; }
  if [[ "${env_cfg##*/}" =~ ^((gcc|intel|pgci|clang|xl|nag|fj|aocc)@.*)\.yaml$ ]]; then
    compiler_path="$( ( spack cd -i ${BASH_REMATCH[1]} && pwd -P ) )"
    status=$?
    (( $status == 0 )) \
      || { printf "ERROR: failed to extract path info for new compiler ${BASH_REMATCH[1]}\n" 1>&2; exit status; }
    spack compiler find "$compiler_path"
  fi
done

### Local Variables:
### mode: sh
### eval: (sh-set-shell "bash" t nil)
### End:
