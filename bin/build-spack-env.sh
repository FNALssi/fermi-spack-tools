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

shopt -s extglob nullglob

####################################
# Message tags.
(( INFO = 0 )) # Baseline.
# Important.
(( WARNING = INFO - 1 ))
(( ERROR = WARNING - 1 ))
(( FATAL_ERROR = ERROR - 1 ))
(( INTERNAL_ERROR = FATAL_ERROR -1 ))
(( PIPE = INTERNAL_ERROR - 1 ))
# Informative.
(( PROGRESS = INFO + 1 ))
(( DEBUG_0 = PROGRESS )) # Bookkeeping.
(( DEBUG_1 = DEBUG_0 + 1 ))
(( DEBUG_2 = DEBUG_1 + 1 ))
(( DEBUG_3 = DEBUG_2 + 1 ))
(( DEBUG_4 = DEBUG_3 + 1 ))
# ... etc.
####################################

# Exit status codes.
(( EXIT_SUCCESS = 0 ))
(( EXIT_FAILURE = 1 ))
(( EXIT_PATH_FAILURE = 2 ))
(( EXIT_BOOTSTRAP_FAILURE = 3 ))
(( EXIT_CONFIG_FAILURE = 4 ))
(( EXIT_UPS_FAILURE = 5 ))
(( EXIT_SPACK_CONFIG_FAILURE = 6 ))
(( EXIT_SPACK_ENV_FAILURE = 7 ))
(( EXIT_SPACK_CONCRETIZE_FAILURE = 8 ))
(( EXIT_SPACK_INSTALL_FAILURE = 9 ))
(( EXIT_SPACK_GPG_FAILURE = 10 ))

# Default verbosity
(( DEFAULT_VERBOSITY = INFO ))
(( VERBOSITY = DEFAULT_VERBOSITY ))

# Unredirected standard outout, error
(( STDOUT = 3 ))
(( STDERR = 4 ))
eval exec "$STDOUT>&1" "$STDERR>&2"

prog="${BASH_SOURCE##*/}"
progfill=${prog//?/ }
working_dir="${WORKSPACE:=$(pwd)}"

usage() {
  cat <<EOF

usage: $prog 
EOF
}

# Report and execute this command.
_cmd() {
  local cmd_severity=$VERBOSITY
  _report_cmd "$@"
  while [[ "$1" =~ ^-?[0-9]*$ ]]; do
    (( cmd_severity = $1 ))
    shift
  done
  [ -n "$redirect" ] \
    || { (( VERBOSITY < cmd_severity )) && local redirect='>/dev/null 2>&1'; }
  eval '"$@"' $redirect
}

_copy_back_logs() {
  local tar_tmp="$working_dir/copyBack/tmp"
  local spack_env= env_spec= install_prefix=
  mkdir -p "$tar_tmp/spack_env"
  cd "$spack_env_top_dir"
  _cmd $DEBUG_1 spack clean -dmp
  _cmd $DEBUG_1 $PIPE tar -c *.log *-out.txt *.yaml etc var/spack/environments \
    | _cmd $DEBUG_1 tar -C "$tar_tmp/spack_env" -x
  _cmd $DEBUG_1 $PIPE tar -C "$TMPDIR" -c spack-stage | _cmd $DEUBG_1 tar -C "$tar_tmp" -x
  for spack_env in $(spack env list); do
    _cmd $DEBUG_1 $PIPE spack -e $spack_env \
          ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
          --color=never \
          spec --format '{fullname}{/hash}' \
      | while read root_spec; do
      _cmd $DEBUG_1 $PIPE spack \
        ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
        --color=never \
        find -d --no-groups \
        --format '{fullname}{/hash}'$'\t''{prefix}' \
        "$root_spec"
    done
  done \
    | sed -Ee 's&^[[:space:]]+&&' \
    | sort -u \
    | while read env_spec install_prefix; do
    if [ -d "$install_prefix/.spack" ]; then
      mkdir -p "$tar_tmp/installed/$env_spec"
      _cmd $DEBUG_1 $PIPE tar -C "$install_prefix/.spack" -c . \
        | _cmd $DEBUG_1 tar -C "$tar_tmp/installed/$env_spec" -x
    fi
  done
  _cmd $DEBUG_1 $PIPE tar -C "$tar_tmp" -jcf "$working_dir/copyBack/${BUILD_TAG:-spack-output}.tar.bz2" .
  _debug $DEBUG_1 rm -rf "$tar_tmp"
} 2>/dev/null

# Print a message and exit with the specifed numeric first argument or 1
# as status code.
_die() {
  local exitval= DIE_ERROR="${DIE_ERROR:-FATAL}"
  if [[ "$1" =~ ^[0-9]*$ ]]; then (( exitval = $1 )); shift; fi
  _report $ERROR "$@"
  exit ${exitval:-$EXIT_FAILURE}
}

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
  local extra_cmd_opts=()
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
          --color=never \
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
    while (( idx > 0 )); do
      _piecemeal_build || return
    done
  else
    # Build the whole environment.
    _report "building environment $env_name"
    local spack_build_env_cmd=(
      "${spack_install_cmd[@]}"
      ${extra_cmd_opts[*]:+"${extra_cmd_opts[@]}"}
    )
    _cmd $PROGRESS $INFO "${spack_build_env_cmd[@]}"
  fi
}

_internal_error() {
  local DIE_ERROR="INTERNAL"
  _die "$@"
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
  _report $DEBUG_1 "generating concretization-specific mirrors.yaml at \"$out_file\""
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
      || _die $EXIT_SPACK_CONFIG_FAILURE "unable to generate concretization-specific mirrors.yaml at \"$out_file\""
}

_piecemeal_build() {
  local buildable_dep_hashes=() build_root_hash=
  while (( idx-- )); do
    if _in_sorted_hashlist "${hashes[$idx]}" ${root_hashes[*]:+"${root_hashes[@]}"}; then
      build_root_hash="${hashes[$idx]}"
      _remove_root_hash "${hashes[$idx]}"
      break;
    fi
    # This is a dependency we should build if we haven't already.
    _in_sorted_hashlist "${hashes[$idx]}" ${installed_deps[*]:+"${installed_deps[@]}"}\
      || buildable_dep_hashes+=("${hashes[$idx]}")
  done
  # Uniquify hashes.
  OIFS="$IFS"; IFS=$'\n'
  buildable_dep_hashes=($(echo "${buildable_dep_hashes[*]}" | sort -u))
  IFS="$OIFS"
  # Build identified dependencies.
  if (( ${#buildable_dep_hashes[@]} )); then
    _report $PROGRESS "building ${#buildable_dep_hashes[@]} dependencies of root packages in environment $env_name (tranche #$(( ++deps_tranche_counter )))"
    _cmd $DEBUG_1 $INFO \
         "${spack_install_cmd[@]}" \
         ${buildable_dep_hashes[*]:+--no-add "${buildable_dep_hashes[@]//*\///}"} \
      || return
    # Add deps to list of installed deps.
    installed_deps+=(${buildable_dep_hashes[*]:+"${buildable_dep_hashes[@]}"})
  fi
  # Build identified root or the whole environment if we've run out of
  # intermediate roots to build.
  _report $PROGRESS "building${build_root_hash:+ root package $build_root_hash in} environment $env_name"
  local spack_build_root_cmd=(
    "${spack_install_cmd[@]}" \
      ${extra_cmd_opts[*]:+"${extra_cmd_opts[@]}"} \
      ${build_root_hash:+--no-add "/${build_root_hash##*/}"}
  )
  _cmd $PROGRESS $INFO "${spack_build_root_cmd[@]}" || return
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
      || _die $EXIT_PATH_FAILURE "unable to obtain specified environment config file \"$env_cfg\""
    env_cfg="${BASH_REMATCH[2]}"
  fi
  env_name="${env_cfg##*/}"
  env_name="${env_name%.yaml}"
  env_name="${env_name//[^A-Za-z0-9_-.]/-}"
  env_name="${env_name##-}"
  spack \
    ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
    env rm -y $env_name >/dev/null 2>&1
  _report $PROGRESS "creating environment $env_name from $env_cfg"
  _cmd $DEBUG_1 spack \
    ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
    env create --without-view $env_name "$env_cfg" \
    || _die $EXIT_SPACK_ENV_FAILURE "unable to create environment $env_name from $env_cfg"
  # Save logs and attempt to cache successful builds before we're killed.
  trap 'interrupt=$?; _copy_back_logs' HUP INT QUIT TERM
  # Copy our concretization-specific mirrors configuration into place to
  # prevent undue influence of external mirrors on the concretization
  # process.
  if (( concretize_safely )); then
    cp -p "$mirrors_cfg"{,~} \
      && cp "$concretize_mirrors" "$mirrors_cfg" \
        || _die $EXIT_PATH_FAILURE "failed to install \"$concretize_mirrors\" prior to concretizing $env_name"
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
  (( num_environments > ++env_idx )) \
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
  _report $PROGRESS "concretizing environment $env_name${concretize_safely:+ safely}"
  _cmd $DEBUG_1 $PROGRESS \
       spack \
       -e $env_name \
       ${__debug_spack_concretize:+-d} \
       ${__verbose_spack_concretize:+-v} \
       ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
       concretize ${tests_arg:+"$tests_arg"} \
    && { ! (( concretize_safely )) || mv -f "$mirrors_cfg"{~,}; } \
    && _report $DEBUG_1 "saving concretized spec as ${env_name}_nnn.json" \
    && _cmd $DEBUG_1 $PIPE spack \
            -e $env_name \
            ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
          --color=never \
         spec -j \
      | csplit -f "$env_name" -b "_%03d.json" -z -s - '/^\}$/+1' '{*}' \
    && { ! (( cache_write_sources )) \
           || { _report $PROGRESS "caching sources in local mirror"
                _cmd $DEBUG_1 $PROGRESS spack \
                     -e $env_name \
                     ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
                     mirror create -aD --skip-unstable-versions -d "$working_dir/copyBack/spack-source-mirror"; }; } \
                  && _do_build_and_test \
                    || failed=1
  if [ -n "$interrupt" ]; then
    failed=1 # Trigger buildcache dump.
    local tag_text=ALERT
    _die $interrupt "exit due to caught signal ${interrupt:-(HUP, INT, QUIT or TERM)}"
  fi
  (( failed == 0 )) \
    || _die "failed to build environment $env_name" 1>&2
  ####################################

  ####################################
  # Store all successfully-built packages in the buildcache
  if [ "${cache_write_binaries:-none}" != none ]; then
    _report $PROGRESS "caching $cache_write_binaries binary packages for environment $env_name in local mirror"
    for env_json in "$env_name"_*.json; do
      _cmd $DEBUG_1 $PROGRESS \
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
      _report $PROGRESS "removing roots of environment $env_name from binary cache"
      for env_json in "$env_name"_*.json; do
        spec="$(spack buildcache get-buildcache-name --spec-file "$env_json")"
        _report $DEBUG_1 "removing package for root spec $spec from binary cache"
        find "$working_dir/copyBack/spack-binary-mirror" \
             -type f \
             \( -name "$spec.spack" -o -name "$spec.json" -o -name "$spec.json.sig" \) \
             -exec rm -f \{\} \;
      done
    fi  >/dev/null 2>&1
    _report $PROGRESS "updating local build cache index"
    _cmd $DEBUG_1 $PROGRESS \
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
                     location --install-dir "$env_spec" ) )" \
      || _die $EXIT_PATH_FAILURE "failed to extract path info for new compiler $env_spec"
    _report $DEBUG_1 "registering compiler at $compiler_path with Spack"
    _cmd $DEBUG_1 spack \
      ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
      compiler find "$compiler_path"
  fi
  ####################################
}

# Properly quote a message for protection from the shell if copy/pasted.
if (( ${BASH_VERSINFO[0]} > 4 )) \
     || { (( ${BASH_VERSINFO[0]} == 4 )) \
            && (( ${BASH_VERSINFO[1]} >= 4 )); }; then
_quote() { local result_var="$1"; shift; eval $result_var='"${*@Q}"'; }
else
_quote() {
  local x= result_var="$1" result=()
  shift
  for x in "$@"; do
    if [[ "$x" =~ ^[.A-Za-z0-9_/@=-]*$ ]]; then
      result+=("$x")
    else
      local tmp_result="${x//\\/\\\\}"
      result+=("'${tmp_result//\'/\'\"\'\"\'}'")
    fi
  done
  eval $result_var='"${result[*]}"'
}
fi

_remove_root_hash() {
  local handled_root="$1"
  local filtered_root_hashes=()
  for hash in ${root_hashes[*]:+"${root_hashes[@]}"}; do
    [ "$handled_root" = "$hash" ] || filtered_root_hashes+=("$hash")
  done
  root_hashes=(${filtered_root_hashes[*]:+"${filtered_root_hashes[@]}"})
}

# Print a message with the specifed numeric first argument or 0 as
# severity.
_report() {
  local severity=$DEFAULT_VERBOSITY redirect=">&$STDOUT"
  if [[ "$1" =~ ^-?[0-9]*$ ]]; then (( severity = $1 )); shift; fi
  (( VERBOSITY < severity )) && return # Diagnostics suppression.
  (( severity < INFO )) && redirect=">&$STDERR" # Important to stderr.
  local severity_tag="$(_severity_tag $severity)"
  eval printf '"${severity_tag:+$severity_tag }${is_cmd:+executing }$*\n"' \
       $redirect \
    || { echo "==> INTERNAL_ERROR: unable to report: $*" >&$STDERR; exit $EXIT_FAILURE; }
}

# Report the command we're just about to execute.
_report_cmd() {
  local is_cmd=1 verbosity_directives=() quoted_cmd=()
  while [[ "$1" =~ ^-?[0-9]*$ ]]; do
    verbosity_directives+=("$1")
    shift
  done
  # We only use the first verbosity directive (if we have it) for the report:
  _quote quoted_cmd "$@"
  _report $verbosity_directives "$quoted_cmd"
}

_set_cache_write_binaries() {
  local wcb="$(echo "$1" | tr '[A-Z-]' '[a-z_]')"
  case $wcb in
    all|deps|dependencies|none|roots) cache_write_binaries="$wcb";;
    no_roots|non_roots) cache_write_binaries="no_roots";;
    *) _die $EXIT_CONFIG_FAILURE "unrecognized argument \"$1\" to --write-cache-binaries\n$(usage)"
  esac
}

# Print a severity tag for the given severity code
_severity_tag() {
  local tag_text
  if (( is_cmd )); then
    if (( $1 > DEBUG_0 )); then
      local tag_text="DEBUG_$(( $1 - DEBUG_0 ))_CMD"
    else
      local tag_text="CMD"
    fi
  fi
  case $1 in
    $ERROR) tag="\e[1;31m==> ${tag_text:-${DIE_ERROR:+$DIE_ERROR }ERROR}\e[m";;
    $WARNING) tag="\e[1;33m==> ${tag_text:-WARNING}\e[m";;
    $INFO) tag="\e[1;34m==> ${tag_text:-INFO}\e[m";;
    $PROGRESS) tag="\e[1;32m==> ${tag_text:-PROGRESS}\e[m";;
    *) tag="\e[1m==> ${tag_text:-DEBUG_$(( $1 - DEBUG_0 ))}\e[m"
  esac
  echo "$tag"
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
      printf "%q\n" "$1"
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
    *) _die $EXIT_CONFIG_FAILURE "unrecognized --ups option \"$1\"\n$(usage)"
  esac
  printf -- "$opt\n";
}

########################################################################
# Main
########################################################################

# Sanity check.
if [ -n "$SPACK_ROOT" ]; then
_die "cowardly refusing to initialize a Spack system with one
already in the shell environment:

SPACK_ROOT=$SPACK_ROOT

$(spack env status)"
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

color=
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

eval "$ssi_split_options"
while (( $# )); do
  case $1 in
    --cache-write-binaries=*) _set_cache_write_binaries "${1#*=}";;
    --cache-write-binaries) _set_cache_write_binaries "$2"; shift;;
    --cache-write-bootstrap) cache_write_bootstrap=1;;
    --cache-write-sources) cache_write_sources=1;;
    --clear-mirrors) clear_mirrors=1;;
    --color) color="$2"; shift;;
    --color=*) color="${1#*=}";;
    --debug-spack-*|--verbose-spack-*) eval "${1//-/_}=1";;
    --help|-h|-\?) usage 2; exit 1;;
    --no-cache-write-binaries) cache_write_binaries=none;;
    --no-cache-write-bootstrap) unset cache_write_bootstrap;;
    --no-cache-write-sources) unset cache_write_sources;;
    --no-safe-concretize) unset concretize_safely;;
    --no-ups) ups_opt=-p;;
    --quiet|-q) QUIET=1;;
    --safe-concretize) concretize_safely=1;;
    --spack-config-cmd) spack_config_cmds+=("$2"); shift;;
    --spack-config-cmd=*) spack_config_cmds+=("${1#*=}");;
    --spack-config-file) spack_config_files+=("$2"); shift;;
    --spack-config-file=*) spack_config_files+=("${1#*=}");;
    --spack-infrastructure-root) si_root="$2"; shift;;
    --spack-infrastructure-root=*) si_root="${1#*=}";;
    --spack-infrastructure-version) si_ver="$2"; shift;;
    --spack-infrastructure-version=*) si_ver="${1#*=}";;
    --spack-python) spack_python="$2"; shift;;
    --spack-python=*) spack_python="${1#*=}";;
    --spack-root) spack_root="$2"; shift;;
    --spack-root=*) spack_root="${1#*=}";;
    --spack-version) spack_ver="$2"; shift;;
    --spack-version=*) spack_ver="${1#*=}";;
    --test) tests_type="$2"; shift;;
    --test=*) tests_type="${1#*=}";;
    --ups) ups_opt="$(_ups_string_to_opt "$2")" || exit; shift;;
    --ups=*) ups_opt="$(_ups_string_to_opt "${1#*=}")" || exit;;
    -v) (( ++VERBOSITY ));;
    --with-cache) optarg="$2"; shift; OIFS="$IFS"; IFS=","; cache_urls+=($optarg); IFS="$OIFS";;
    --with-cache=*) optarg="${1#*=}"; OIFS="$IFS"; IFS=","; cache_urls+=($optarg); IFS="$OIFS";;
    --working-dir=*) working_dir="${1#*=}";;
    --working_dir) working_dir="$2"; shift;;
    -h) usage; exit 1;;
    --) shift; break;;
    -*) _die $EXIT_CONFIG_FAILURE "unrecognized option $1\n$(usage)";;
    *) break
  esac
  shift
done

color_arg=${color:+--color=$color}
common_spack_opts+=($color_arg)

####################################
# Supress all but warnings and errors if we need quiet.
if (( QUIET )); then
  (( VERBOSITY > DEFAULT_VERBOSITY )) && _report $INFO "-q overrides -v"
  (( VERBOSITY = WARNING ))
fi
####################################


####################################
# Set up working area.
[ -n "$working_dir" ] || working_dir="${WORKSPACE:-$(pwd)}"
mkdir -p "$working_dir" || _die $EXIT_PATH_FAILURE "unable to ensure existence of working directory \"$working_dir\""
cd "$working_dir" || _die $EXIT_PATH_FAILURE "unable to change to working directory \"$working_dir\""
if [ -z "$TMPDIR" ]; then
  export TMPDIR="$working_dir/tmp"
  rm -rf "$TMPDIR"
  mkdir -p "$TMPDIR"
fi
####################################

spack_env_top_dir="$working_dir/spack_env"
mirrors_cfg="$spack_env_top_dir/etc/spack/mirrors.yaml"
default_mirrors="$spack_env_top_dir/etc/spack/defaults/mirrors.yaml"
concretize_mirrors="$spack_env_top_dir/concretize_mirrors.yaml"

####################################
# Handle SPACK_PYTHON
if [ -n "$spack_python" ]; then
  python_type="$(type -t "$spack_python")" \
    || _die $EXIT_CONFIG_FAILURE "specified python \"$spack_python\" is not a viable command"
  [ "$python_type" = "file" ] && spack_python="$(type -P "$spack_python")"
  export SPACK_PYTHON="$spack_python"
fi

[ -n "$SPACK_PYTHON" ] && _report "SPACK_PYTHON=$SPACK_PYTHON"
####################################

####################################
# Handle tests type
case ${tests_type:=none} in
  all|none|root) : ;;
  *) _die $EXIT_CONFIG_FAILURE "unknown --test argument $tests_type\n$(usage)"
esac

tests_arg=
if ! [ "$tests_type" = "none" ]; then
  tests_arg="--test=$tests_type"
fi
####################################

####################################
# Translate --cache-write-binaries opt into options to
#
#    `spack buildcache create`
case ${cache_write_binaries:=none} in
  all|none|no_roots) : ;;
  roots) extra_buildcache_opts+=(--only package);;
  dep*) extra_buildcache_opts+=(--only dependencies);;
  *) _die $EXIT_CONFIG_FAILURE "unknown --cache-write-binaries argument $cache_write_binaries\n$(usage)"
esac
####################################

####################################
# Safe, comprehensive cleanup.
TMP=`mktemp -d -t build-spack-env.sh.XXXXXX`
trap "[ -d \"$TMP\" ] && rm -rf \"$TMP\" 2>/dev/null; \
[ -f \"$mirrors_cfg~\" ] && mv -f \"$mirrors_cfg\"{~,}; \
_copy_back_logs; \
if (( failed == 1 )) && [ \"${cache_write_binaries:-none}\" != none ]; then \
  tag_text=ALERT _report $ERROR \"emergency buildcache dump...\"; \
  _cmd $ERROR $PIPE spack \
      \${common_spack_opts[*]:+\"\${common_spack_opts[@]}\"} \
      buildcache create -a --deptype=all \
      \${extra_buildcache_opts[*]:+\"\${extra_buildcache_opts[@]}\"} \
      -d \"$working_dir/copyBack/spack-binary-mirror\" \
      -r --rebuild-index \$(spack find --no-groups); \
  tag_text=ALERT _report $ERROR \"emergency buildcache dump COMPLETE\"; \
fi; \
eval exec \"$STDOUT>&-\" \"$STDERR>&-\"\
" EXIT
####################################

si_upsver="v${si_ver#v}"
####################################
# Install spack-infrastructure to bootstrap a Spack installation.
_report $PROGRESS "cloning spack-infrastructure"
_cmd $DEBUG_1 git clone -b "$si_ver" "$si_root" "$TMP/" \
  || _die "unable to clone spack-infrastructure $si_ver from $si_root"
if [[ "${spack_config_files[*]}" =~ (^|/)packages\.yaml([[:space:]]|$) ]]; then
  # Bypass packages.yaml generation if we're going to ignore it anyway.
  _report $DEBUG_2 "bypassing packages.yaml generation"
  _cmd $DEBUG_2 ln -sf /usr/bin/true "$TMP/bin/make_packages_yaml"
else
  # Don't want externals from CVMFS.
  _report $DEBUG_2 "externals in CVMFS will be excluded from generated packages.yaml"
  _cmd $DEBUG_2 sed -Ei'' -e 's&^([[:space:]]+cprefix=).*$&\1'"''"'&' "$TMP/bin/make_packages_yaml"
fi
####################################

####################################
# Bootstrap the Spack installation.
mkdir -p "$spack_env_top_dir" \
  || _die $EXIT_PATH_FAILURE "unable to make directory structure for spack environment installation"
cd "$spack_env_top_dir"
if ! [ -f "$spack_env_top_dir/setup-env.sh" ]; then
  make_spack_cmd=(make_spack --spack_release $spack_ver --minimal $ups_opt "$spack_env_top_dir")
  _report $INFO "bootstrapping Spack $spack_ver"
  PATH="$TMP/bin:$PATH" \
      _cmd $PROGRESS ${make_spack_cmd[*]:+"${make_spack_cmd[@]}"} \
    || _die "unable to install Spack $spack_ver"
fi

# Clear mirrors list back to defaults.
if (( clear_mirrors )); then
  _report $PROGRESS "clearing default mirrors list"
  _cmd $PROGRESS "$default_mirrors" "$mirrors_cfg"
fi

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
_report $PROGRESS "setting up Spack $spack_ver"
source "$spack_env_top_dir/setup-env.sh" \
  || _die "unable to set up Spack $spack_ver"
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
      || _die $EXIT_PATH_FAILURE "unable to obtain specified config file \"$config_file\""
    config_file="${BASH_REMATCH[2]}"
  fi
  _cmd $DEBUG_1 spack \
    ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
    config --scope=$cf_scope add -f "$config_file" \
    || _die $EXIT_SPACK_CONFIG_FAILURE "unable to add file obtained from \"$config_file\" to spack config with scope $cf_scope"
done
# 2. Spack config commands.
for config_cmd in ${spack_config_cmds[*]:+"${spack_config_cmds[@]}"}; do
  eval _cmd $DEBUG_1 spack \
       ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
       config $config_cmd \
    || _die $EXIT_SPACK_CONFIG_FAILURE "executing spack config command \"$config_cmd\""
done
# 3. Caches
for cache_spec in ${cache_urls[*]:+"${cache_urls[@]}"}; do
  if [[ "$cache_spec" =~ ^([^|]+)\|(.*)$ ]]; then
    cache_name="${BASH_REMATCH[1]}"
    cache_spec="${BASH_REMATCH[2]}"
  else
    cache_name="buildcache_$((++cache_count))"
  fi
  _cmd $DEBUG_1 spack \
    ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
    mirror add --scope=site "$cache_name" "$cache_spec" \
    || _die $EXIT_SPACK_CONFIG_FAILURE "executing spack mirror add --scope=site $cache_name \"$cache_spec"
done

# Add mirror as buildcache for locally-built packages.
_cmd $DEBUG_1 spack mirror add --scope=site __local_binaries "$working_dir/copyBack/spack-binary-mirror"
_cmd $DEBUG_1 spack mirror add --scope=site __local_sources "$working_dir/copyBack/spack-source-mirror"

# Make a cut-down mirror configuration for safe concretization.
if (( concretize_safely )); then
  _make_concretize_mirrors_yaml "$concretize_mirrors"
fi
####################################

####################################
# Make sure we know about compilers.
spack compiler find --scope=site >/dev/null 2>&1
####################################

####################################
# Execute bootstrap explicitly.
_report $PROGRESS "bootstrapping Spack's tools"
_cmd $PROGRESS $INFO \
     spack \
     ${__debug_spack_bootstrap:+-d} \
     ${__verbose_spack_bootstrap:+-v} \
     ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
     bootstrap now \
  || _die $EXIT_BOOTSTRAP_FAILURE "unable to bootstrap safely with base configuration"
####################################

####################################
# Update our local public keys from configured build caches.
_report $PROGRESS "updating local keys from configured build caches"
_cmd $DEBUG_1 spack buildcache keys
####################################

####################################
# Initialize signing key for binary packages.
if [ -n "$SPACK_BUILDCACHE_SECRET" ]; then
  _report $PROGRESS "initializing configured signing key"
  spack \
    ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
    gpg trust "$SPACK_BUILDCACHE_SECRET"
  # Handle older Spack installations that need the long-format keyid.
  keyid="$(gpg2 --list-secret-keys --keyid-format long --homedir "${SPACK_GNUPGHOME:-$SPACK_ROOT/opt/spack/gpg}" | sed -Ene '/^sec/{s&^[^/]+/([A-F0-9]+).*$&\1&p; q}')"
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
  _report $PROGRESS "writing bootstrap packages to build cache"
  _cmd $DEBUG_1 spack \
    ${__debug_spack_bootstrap:+-d} \
    ${__verbose_spack_bootstrap:+-v} \
    ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
    bootstrap mirror --binary-packages --dev "$working_dir/copyBack/spack-bootstrap-mirror" \
    || _report $WARNING "unable to write bootstrap packages to local cache"
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
  _report $PROGRESS "declaring spack-infrastructure package to UPS"
  source /grid/fermiapp/products/common/etc/setups \
    || source /products/setup \
    || _die $EXIT_UPS_ERROR "unable to set up UPS"
  PRODUCTS="$spack_env_top_dir:$PRODUCTS"

  cd $TMP \
    && _cmd $DEBUG_1 "$TMP/bin/declare_simple" spack-infrastructure $si_upsver \
      || _die $EXIT_UPS_ERROR "unable to declare spack-infrastructure $si_ver to UPS"
  cd - >/dev/null
fi
####################################

environment_specs=("$@")
num_environments=${#environment_specs[@]}
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
