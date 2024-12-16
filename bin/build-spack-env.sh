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

usage: $prog <options> (--)? [(<spack-env-yaml-file>|<spack-env-yaml-url>)] ...
       $prog (-[h?]|--help)

EOF
  cat <<\EOF
BRIEF OPTIONS

  --cache-write-(sources|binaries[= ](all|none|deps|dependencies|(no|non)[_-]roots|roots))
  --no-cache-write-(sources|binaries)
  --extra-(sources|binaries)-write-cache[= ](<cache-path>|<cache-url>)(,...)+
  --clear-mirrors
  --color[= ](auto|always|never)
  --(debug|verbose)-spack-(bootstrap|buildcache|concretize|install)
  --debug-tmp
  --fermi-spack-tools-root[= ]<repo>
  --fermi-spack-tools-version[= ]<version>
  --no-auto-recipe-repos
  --(no-)?emergency-buildcache
  --(no-)?fail-fast
  --(no-)?query-packages
  --(no-)?safe-concretize
  --(no-)?upgrade-(etc|extensions|recipes|spack)
  --no-view
  --spack-python[= ]<python-exec>
  --spack-config-cmd[= ]<config-cmd-string>+
  --spack-config-file[= ](<cache-name>\|)?<config-file>+
  --spack-repo[= ]<path>|<repo>(\|<version|branch>)?
  --spack-root[= ]<repo>
  --spack-version[= ]<version>
  --test[= ](all|none|root)
  -q
  --quiet
  [+-]v+
  --verbosity[= ](-?[0-9]+|INFO|WARNING|(FATAL_|INTERNAL_)?ERROR|INFO|PROGRESS|DEBUG_[1-9][0-9]*)
  --no-ups
  --ups[= ](plain|traditional|unified|-[ptu])
  --with-cache[= ](<cache-name>\|)?(<type>:)?(<cache-path>|<cache-url>)(,...)+
  --with-concretiz(e|ing|ation)-cache[= ](<cache-name>\|)?(<type>:)?(<cache-path>|<cache-url>)(,...)+
  --with-padding
  --working-dir[= ]<dir>

  [ Options suffixed with + are repeatable and cumulative ]

EOF
  if (( "${1:-0}" == 0 )); then
    return
  fi
cat <<\EOF
HELP AND DIAGNOSTIC OPTIONS

  -h
  -\?
  --help

    This help.

  -q
  --quiet

    Reset the verbosity to WARNING.

  -v
  +v

    Increase (-v) or decrease (+v) the verbosity by one level.

  --verbosity[= ](-?[0-9]+|INFO|WARNING|(FATAL_|INTERNAL_)?ERROR|INFO|PROGRESS|DEBUG_[1-9][0-9]*)

    Set the verbosity to the indicated value.

  --(debug|verbose)-spack-(bootstrap|buildcache|concretize|install)

    Add -d or -v options to appropriate invocations of Spack.

  --debug-tmp

    Preserve script-generated temporary files.

  --color[= ](auto|always|never)

    Control the use of ANSI colors; auto (default) => color on tty output only.


LOCATION AND VERSION OPTIONS

  --fermi-spack-tools-root[= ]<repo>
  --fermi-spack-tools-version[= ]<version|branch>

    Obtain the Fermi Spack Tools from the specified repository and/or
    branch/version.

  --spack-root[= ]<repo>

    Obtain Spack from the specified repository.

  --spack-version[= ]<version|branch>

    Obtain the specified branch/version of Spack.

  --working-dir[= ]<working_dir>

    Top level working directory. If not set, use $WORKSPACE or $PWD.


SPACK CONFIGURATION OPTIONS

 Mirror/Cache Options

  --cache-write-(sources|binaries[= ](all|none|deps|dependencies|(no|non)[_-]roots|roots))
  --no-cache-write-(sources|binaries)

    Control whether sources or binary packages are written to local
    caches under <working-dir>/copyBack.

  --extra-(sources|binaries)-write-cache[= ](<cache-path>|<cache-url>)(,...)+

    Extra source/binary cache locations for built products. Incompatible
    with --no-cache-write-(sources|binaries).

  --clear-mirrors

    Remove bootstrapped mirrors/caches from configuration.

  --with-cache[= ](<cache-name>\|)?(<type>:)?(<cache-path>|<cache-url>)(,...)+
  --with-concretiz(e|ing|ation)-cache[= ](<cache-name>\|)?(<type>:)?(<cache-path>|<cache-url>)(,...)+

    Add a read-only mirror/cache. If --safe-concretize is set, added
    caches will be ignored during the concretizaton process unless the
    second form is used. If specified, <type> may be "source," or
    "binary."


 Other Spack Configuration

  --no-auto-recipe-repos

    Do not define a default set of recipe repositories to obtain and
    configure (handled by `make_spack`).

  --(no-)?emergency-buildcache

    Control whether to dump successfully installed binaries to an
    emergency buildcache on abnormal exit (default yes).

  --(no-)?fail-fast

    Control whether to abort an installation at the first failure or
    continue to install as many packages as possible before exit
    (default --fail-fast).

  --(no-)?query-packages

    Construct a packages.yaml based on the packages available on the
    system, or use a prepackaged one appropriate to the platform.

  --(no-)?safe-concretize

    Control whether to concretize environments with only a minimal set
    of mirrors configured to improve reproducibility (default yes).

  --(no-)?upgrade-(etc|extensions|recipes|spack)

    Control whether to upgrade the corresponding component(s) of an
    existing Spack installation:

    * `etc/` (default yes)
    * Spack extensions (default yes)
    * recipe repositories including those specified with --spack-repo (default no)
    * the Spack installation itself (default no).

  --no-view

    Disable views in created environments. If specified, any view
    settings in `spack.yaml` or `spack.lock` files will be overridden.

  --spack-python[= ]<python-exec>

    Use the specified non-default Python executable to invoke Spack.

  --spack-config-cmd[= ]<config-cmd-string>+

    Pass the specified configuration command to `spack config`.

  --spack-config-file[= ](<config-scope>\|)?<config-file>+

    Import the specified YAML configuration file into Spack's
    configuration.

  --spack-repo[= ]<path>
  --spack-repo[= ]<repo>(\|<version|branch>)?

    Configure an external source of Spack recipes from the specified
    path or repository. If a Spack recipe repo is already configured
    with the same namespace as that incoming, it will be
    deconfigured. If there is an existing directory in var/spack/repos
    that would conflict with a cloned `<repo>`, the cloned repo's top
    level directory will be amended with `-_n_`.

  --test[= ](all|none|root)

     Configure Spack to test all, none, or only specified "root"
     packages in non-compiler environment configurations (default is
     none).

  --no-ups
  --ups[= ](plain|traditional|unified|-[ptu])

    These options are deprecated: all except --ups=plain a.k.a. --no-ups
    (the default) are ignored.

  --with-padding

    Equivalent to --spack-config-cmd='--scope=site add config:install_tree:padded_length:255'


NON-OPTION ARGUMENTS

  (<spack-env-yaml-file>|<spack-env-yaml-url>)+

  Paths or URLs to `spack.yaml` or `spack.lock` files configuring
  environments. The basename of the path or URL will be used to form the
  Spack environment name and should be descriptive of the environment
  (e.g. gcc@12.2.0.yaml, clang@14.0.6.yaml, or
  critic@develop-e26-prof.yaml).


BUILDING CONFIGURED SPACK ENVIRONMENTS

  Environments describing compilers recognized by Spack are treated
  specially:

  * After the environment has been built, the compiler will be added to
    Spack's list of available compilers for building subsequent
    environments.

  * if `--test=root` is specified, then non-terminal compiler
    environments will be built without tests; otherwise the user's
    preference will be honored as for terminal or non-compiler
    environments.

  If `--test=root` is specified, then for terminal or non-compiler
  environments:

  * Dependencies which are not themselves roots of the environment will
    be built in batches before their dependents.

  * Root packages will be built with `spack install --no-cache` to
    ensure that they will be built and tests will be run regardless of
    whether the package is available as a pre-built binary package from
    a configured mirror cache.


CACHING SOURCE AND BINARY PACKAGES

  If configured:

  * Source packages for each environment will be cached under
    `<working-dir>/copyBack/spack-packages/sources` before that environment
    is built. "Non-stable" sources (e.g. those obtained from
    repositories) will not be cached.

  * Binary packages for each environment will be cached under
    `<working-dir>/copyBack/spack-packages/binaries` or
    `<working-dir>/copyBack/spack-packages/compilers` (as appropriate) after
    that environment has been built successfully. If
    `--cache-write-binaries=no_roots` is active, then root packages of
    non-compiler environments will not be cached.


LOG RETRIEVAL AND ERROR RECOVERY

  At the end of execution of `build-spack-env.sh` (successful or
  otherwise), the `.spack` directories for all installed packages will
  be stored in a `.tar.bz2` file under `<working-dir>/copyBack`, along
  with any generated YAML or Spack configuration files and anything
  remaining in or under Spack's top-level staging directory (see `spack
  location -S`).

  In the event of an abnormal termination: if the emergency buildcache
  is enabled (see `--(no-)?emergency-buildcache`), then all successfully
  installed packages will be written to an emergency cache
  `<working-dir>/copyBack/spack-emergency-cache` before
  `build-spack-env.sh` exits.


ENVIRONMENT VARIABLES

  SPACK_BUILDCACHE_SECRET

    Location of a file containing a secret key to be used for signing
    binary package for a Spack build cache.

  SPACK_CMAKE_GENERATOR

    A CMake generator identifier interpreted by certain Spack recipes.

  SPACK_GNUPGHOME

    Non-default location for Spack GPG keys.

  SPACK_PYTHON

    Non-default Python exec for use by invocations of Spack. Overridden
    by --spack-python.

  TMPDIR

    Honored if set; otherwise set to <working-dir>/tmp and create/clear.

  WORKSPACE

    If set: use as default value for <working-dir>; otherwise use <pwd>.

EOF
}

_cache_info() {
  if [[ "$cache_spec" =~ ^(([^|]+)\|)?((source|binary):)?(.*)$ ]]; then
    cache_name="${BASH_REMATCH[2]:-buildcache_$((++cache_count))}"
    (( have_mirror_add_type )) && cache_type="${BASH_REMATCH[4]}"
    cache_url="${BASH_REMATCH[5]}"
  else
    _die $EXIT_SPACK_CONFIG_FAILURE "unable to parse cache_spec \"$cache_spec\""
  fi
}

# Split each spec into name, hash and indent (=dependency) level,
# identifying root hashes (level==0).
_classify_concretized_specs() {
  local all_concrete_specs=()
  _identify_concrete_specs || return
  local regex='^(.{4,5})?([^[:space:]]{32,}) ( *)([^[:space:]@+~%]*)'
  local n_speclines=${#all_concrete_specs[@]} specline_idx=0
  local new_format=0
  while (( specline_idx < n_speclines )); do
    _report $DEBUG_4 "examining line $((specline_idx + 1))/$n_speclines: ${all_concrete_specs[$specline_idx]}"
    [[ "${all_concrete_specs[$((specline_idx++))]}" =~ $regex ]] || continue
    local hash="${BASH_REMATCH[2]}"
    local namespace_name="${BASH_REMATCH[4]}"
    if (( ${#BASH_REMATCH[1]} == 4 )); then
      new_format=1
      root_hashes+=("$namespace_name/$hash")
    elif ! { (( new_format )) || (( ${#BASH_REMATCH[3] )); }; then
      root_hashes+=("$namespace_name/$hash")
    else
      non_root_hashes+=("$namespace_name/$hash")
    fi
    hashes+=("$namespace_name/$hash")
  done
  _report $DEBUG_4 "hashes:\n            ${hashes[@]/%/$'\n'           }"
  _report $DEBUG_2 "root hashes:\n            ${root_hashes[@]/%/$'\n'           }"
  # Remove namespace.name for future use
  root_hashes=(${root_hashes[@]##*/})
  non_root_hashes=(${non_root_hashes[@]##*/})
  # Sort hashes for efficient checking.
  local OIFS="$IFS"; IFS=$'\n'
  # Unique hash-only.
  root_hashes=($(echo "${root_hashes[*]}" | sort -u))
  non_root_hashes=($(echo "${non_root_hashes[*]}" | sort -u))
  IFS="$OIFS"
  # Make sure root hashes that are also dependencies of other roots are
  # all removed from non_root_hashes.
  _remove_hash non_root_hashes "${root_hashes[@]}"
  # Record the number of hashes we need to deal with, and report info.
  n_hashes=${#hashes[@]}
  local n_unique=$(( ${#root_hashes[@]} + ${#non_root_hashes[@]} ))
  _report $DEBUG_1 "examined $specline_idx speclines and found ${#root_hashes[@]} root(s) and $n_unique unique package(s)"
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

# Configure specified Spack recipe repos.
_configure_recipe_repos() {
  local configured_repos=($(_cmd $DEBUG_1 $PIPE spack repo list | \
                              _cmd $DEBUG_2 $PIPE sed -Ene 's&^([A-Za-z0-9_.-]+).*$&\1&p'))
  for repo_element in ${recipe_repos[*]:+"${recipe_repos[@]}"}; do
    local path=
    if [[ "$repo_element" =~ ^(file|https?)://(.*)$ ]]; then
      local url=
      local url_type="${BASH_REMATCH[1]}"
      local url_remainder="${BASH_REMATCH[2]}"
      local branch_etc="${url_remainder##*|}"
      if [ "$branch_etc" = "$url_remainder" ]; then
        url="$url_type://$url_remainder"
      else
        url="$url_type://${url_remainder%|*}"
      fi
      local path="${url%.git}"
      path="$SPACK_ROOT/${path##*/}"
      local configure_namespace=1
      if [ -d "$path" ]; then # We already have a repo here.
        # Deactivate existing namespace.
        _deactivate_repo_at "$path"
        if [ "$(_cmd $DEBUG_3 $PIPE git -C "$path" remote)" = "origin" ] &&
             [ "$(_cmd $DEBUG_3 $PIPE git -C "$path" remote get-url origin)" = "$url" ]; then
          if [ "$(_cmd $DEBUG_3 $PIPE git -C "$path" branch --show-current)" = "$branch_etc" ]; then
            :
          elif (( $(_cmd $DEBUG_3 $PIPE git -C "$path" status -s | wc -l) == 0 )) &&
                 [ -n "$branch_etc" ]; then
            # Switch to desired branch.
            _report $INFO "switching to branch $branch_etc in $path"
            _cmd $DEBUG_1 git -C "$path" switch "$branch_etc"
          fi
          if (( upgrade_recipes )); then
            _report $INFO "upgrading recipe repository on branch $branch_etc at $path"
            _cmd $DEBUG_1 git -C "$path" pull ||
              _die "unable to update recipe repository on branch $branch_etc at $path"
          fi
        else
          local bnum=0 rpath= orig_path="$path"
          while read -r rpath < <(_cmd $DEBUG_3 $PIPE ls -1 "$orig_path"-*); do
            _deactivate_repo_at "$rpath"
            [[ "$rpath" =~ -([0-9]+)$ ]] &&
              (( "${BASH_REMATCH[1]}" > bnum )) &&
              (( bnum = "${BASH_REMATCH[1]}" ))
          done
          path="$orig_path-$((bnum + 1))"
          _report $INFO "cloning Git repository $url${branch_etc:+:$branch_etc} to $path"
          _cmd $DEBUG_1 git clone ${branch_etc:+-b "$branch_etc"} "$url" "$path" ||
            _die "unable to clone $url to $path to configure Spack recipe repository"
        fi
      else
        _report $INFO "cloning Git repository $url${branch_etc:+:$branch_etc} to $path"
        _cmd $DEBUG_1 git clone ${branch_etc:+-b "$branch_etc"} "$url" "$path" ||
          _die "unable to clone $url to $path to configure Spack recipe repository"
      fi
      if (( $? )); then
        _die "unable to reconcile requested repo $repo_element with existing path $path"
      fi
    else
      path="$repo_element"
    fi
    local new_namespace="$(_cmd $DEBUG_3 $PIPE sed -Ene 's&^[[:space:]]*namespace[[:space:]]*:[[:space:]]*'"'([^']+)'"'$&\1&p' "$path/repo.yaml")"
    # Deactivate namespace if it is configured.
    _deactivate_repo $new_namespace
    _report $INFO "configuring Spack recipe repo $new_namespace${scope:+ in scope $scope} at $path"
    _cmd $DEBUG_1 spack repo add${scope:+ --scope $scope} "$path" ||
      _die "unable to add repo $new_namespace${scope:+ in scope $scope} at $path"
  done
}

_configure_spack() {
  # Clear mirrors list back to defaults.
  if (( clear_mirrors )); then
    _report $PROGRESS "clearing default mirrors list"
    _cmd $PROGRESS cp "$default_mirrors" "$mirrors_cfg"
  fi

  ####################################
  # Check whether spack mirror add supports --type
  mirror_add_help="$(spack mirror add --help | grep -Ee '^[[:space:]]*--type[[:space:]]+')"
  [ -n "$mirror_add_help" ] && have_mirror_add_type=1
  ####################################

  ####################################
  # Check whether spack buildcache create still needs -r
  local buildcache_create_help="$(spack buildcache create --help | grep -Ee '^[[:space:]]-r\b')"
  [ -z "$buildcache_create_help" ] ||
    [[ "$buildcache_create_help" == *"(deprecated)"* ]] ||
    buildcache_rel_arg="-r"
  ####################################

  ####################################
  # Configure Spack according to user specifications.
  #
  # 1. Extra / different config files.
  _report $PROGRESS "applying user-specified Spack configuration files"
  local config_file
  for config_file in ${spack_config_files[*]:+"${spack_config_files[@]}"}; do
    local cf_scope="${config_file%'|'*}"
    [ "$cf_scope" = "$config_file" ] && cf_scope=site
    config_file="${config_file##*'|'}"
    if [[ "$config_file" =~ ^[a-z][a-z0-9_-]*://(.*/)?(.*) ]]; then
      curl -o "${BASH_REMATCH[2]}" -fkLNSs "$config_file" \
        || _die $EXIT_CONFIG_FAILURE "unable to obtain specified config file \"$config_file\""
      config_file="${BASH_REMATCH[2]}"
    fi
    _cmd $DEBUG_1 spack \
         ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
         config --scope=$cf_scope add -f "$config_file" \
      || _die $EXIT_SPACK_CONFIG_FAILURE "unable to add file obtained from \"$config_file\" to spack config with scope $cf_scope"
  done
  # 2. Spack config commands.
  _report $PROGRESS "applying user-specified Spack configuration commands"
  local config_cmd
  for config_cmd in ${spack_config_cmds[*]:+"${spack_config_cmds[@]}"}; do
    _cmd $DEBUG_1 spack \
         ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
         config $config_cmd \
      || _die $EXIT_SPACK_CONFIG_FAILURE "executing spack config command \"$config_cmd\""
  done
  # 3. Caches
  _report $PROGRESS "configuring user-specified cache locations"
  local cache_spec cache_url cache_name cache_type
  for cache_spec in \
    ${cache_specs[*]:+"${cache_specs[@]}"} \
    ${concretizing_cache_specs[*]:+"${concretizing_cache_specs[@]}"}
  do
    _cache_info "$cache_spec"
    _cmd $DEBUG_1 spack \
         ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
         mirror add --scope=site ${cache_type:+--type "${cache_type}"} \
         "$cache_name" "$cache_url"  ||
      _die $EXIT_SPACK_CONFIG_FAILURE "executing spack mirror add --scope=site ${cache_type:+--type \"${cache_type}\"} \"$cache_name\" \"$cache_url\""
  done
  # 4. Spack recipe repos.
  _report $PROGRESS "configuring user-specified recipe repositories"
  _configure_recipe_repos

  _report $PROGRESS "configuring local caches"
  # Add mirror as buildcache for locally-built packages.
  for cache_spec in ${local_caches[*]:+"${local_caches[@]}"}; do
    _cache_info "$cache_spec"
    _cmd $DEBUG_1 spack \
         mirror add --scope=site ${cache_type:+--type "${cache_type}"} \
         "$cache_name" "$cache_url"
  done

  # Make a cut-down mirror configuration for safe concretization.
  if (( concretize_safely )); then
    _report $PROGRESS "preparing cache configuration for safe concretization"
    _make_concretize_mirrors_yaml "$concretize_mirrors"
  fi

  ####################################
  # Make sure we know about compilers.
  _report $PROGRESS "configuring compilers"
  spack compiler find --scope=site >/dev/null 2>&1
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
    spack gpg trust "$SPACK_BUILDCACHE_SECRET" >/dev/null 2>&1
    # Handle older Spack installations that need the long-format keyid.
    keyid="$(gpg2 --list-secret-keys --keyid-format long --homedir "${SPACK_GNUPGHOME:-$SPACK_ROOT/opt/spack/gpg}" | sed -Ene '/^sec/{s&^[^/]+/([A-F0-9]+).*$&\1&p; q}')"
    buildcache_key_opts+=(--key "$keyid")
  else
    # Enable insecure mirror use.
    buildcache_key_opts+=(-u)
    extra_install_opts+=(--no-check-signature)
  fi
  ####################################
}

_copy_back_logs() {
  local tar_tmp="$working_dir/copyBack/tmp"
  local spack_env= env_spec= install_prefix=
  _report $INFO "end-of-job copy-back"
  trap 'status=$?; _report $INFO "end-of-job copy-back PREEMPTED by signal $((status - 128))"; exit $status' INT
  mkdir -p "$tar_tmp/"{spack_env,spack-stage}
  cd "$spack_env_top_dir"
  _cmd $DEBUG_3 spack clean -dmp
  _cmd $DEBUG_3 $PIPE tar -c \
       "$spack_source_dir"/*.log \
       "$spack_source_dir"/*-out.txt \
       "$spack_source_dir"/*.yaml \
       "$spack_source_dir"/etc \
       "$spack_source_dir"/var/spack/environments \
    | _cmd $DEBUG_3 tar -C "$tar_tmp/spack_env" -x
  _cmd $DEBUG_3 $PIPE tar -C "$(spack location -S)" -c . \
    | _cmd $DEBUG_3 tar -C "$tar_tmp/spack-stage" -x
  for spack_env in $(spack env list); do
    _cmd $DEBUG_3 $PIPE spack -e $spack_env \
          ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
          --color=never \
          spec --format '{fullname}{/hash}' \
      | while read root_spec; do
      _cmd $DEBUG_3 $PIPE spack \
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
      _cmd $DEBUG_3 $PIPE tar -C "$install_prefix/.spack" -c . \
        | _cmd $DEBUG_3 tar -C "$tar_tmp/installed/$env_spec" -x
    fi
  done
  _cmd $DEBUG_3 tar -C "$tar_tmp" -jcf "$working_dir/copyBack/${BUILD_TAG:-spack-output}.tar.bz2" .
  _cmd $DEBUG_3 rm -rf "$tar_tmp"
  _report $INFO "end-of-job copy-back COMPLETE"
} 2>/dev/null

_deactivate_repo() {
  local namespace="$1" rrepo=
  for rrepo in ${configured_repos[*]:+"${configured_repos[@]}"}; do
    [ "$namespace" = "$rrepo" ] || continue
    local path="$(_cmd $DEBUG_2 $PIPE spack repo list | _cmd $DEBUG_3 $PIPE grep -Ee "^$namespace")"
    local path_basename="${path##*/}"
    scope="$(_cmd $DEBUG_2 $PIPE spack config blame repos | _cmd $DEBUG_3 $PIPE sed -Ene '\&/'"$path_basename"'$& s&/repos\.yaml:[[:digit:]]+[[:space:]]+.*$&/&p')"
    scope="${scope##*/etc/spack/}"
    scope="${scope%/*}"
    [[ scope == defaults/* ]] || scope="site${scope:+/$scope}"
    _report $PROGRESS "deactivating existing repo $rrepo in scope $scope at $path"
    _cmd $DEBUG_1 spack repo rm --scope $scope $rrepo ||
      _die "unable to deactivate existing repo $rrepo in scope $scope at $path"
  done
}

_deactivate_repo_at() {
  local path="$1"
  local orig_namespace="$(_cmd $DEBUG_3 $PIPE sed -Ene 's&^[[:space:]]*namespace[[:space:]]*:[[:space:]]*'"'([^']+)'"'$&\1&p' "$path/repo.yaml")"
  _deactivate_repo $orig_namespace
}

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
    ${fail_fast:+--fail-fast}
    --no-add
    --only-concrete
    ${extra_install_opts[*]:+"${extra_install_opts[@]}"}
  )
  local extra_cmd_opts=(${env_tests_arg:+"$env_tests_arg"})
  if ! (( is_nonterminal_compiler_env )) && [ "$tests_type" = "root" ]; then
    # Build non-root dependencies first, followed by roots.
    _piecemeal_build || return
  else
    # Build the whole environment.
    _report $PROGRESS "building environment $env_name"
    local spack_build_env_cmd=(
      "${spack_install_cmd[@]}"
      ${extra_cmd_opts[*]:+"${extra_cmd_opts[@]}"}
    )
    _cmd $PROGRESS $INFO "${spack_build_env_cmd[@]}"
  fi
}

_identify_concrete_specs() {
  # Identify all concrete specs
  { spack \
      -e $env_name \
      ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
      --color=never \
      find  --no-groups --show-full-compiler -cfNdvL \
      > "$TMP/$env_name-concrete.txt"
      sed -Ene '/^==> (\[.*\] )?(Concretized roots|[[:digit:]]+ root specs)$/,/^==> (\[.*\] )?Installed packages$/ { /^(==>.*)?$/ b; /^.{4,5}?[^[:space:]]{32,}/ p; }' \
          "$TMP/$env_name-concrete.txt" > "$TMP/$env_name-concrete-filtered.txt"
  } 2>/dev/null
  local status=$?
  _report $DEBUG_1 "$TMP/$env_name-concrete-filtered.txt has $(wc -l "$TMP/$env_name-concrete-filtered.txt" | cut -d' ' -f 1) lines"
  while IFS='' read -r line; do
    all_concrete_specs+=("$line")
  done < "$TMP/$env_name-concrete-filtered.txt"
  _report $DEBUG_1 "found ${#all_concrete_specs[@]} concrete specs"
  return $status
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
  cp -p "$mirrors_cfg"{,~} &&
    cp "$default_mirrors" "$mirrors_cfg" ||
      _die $EXIT_SPACK_CONFIG_FAILURE \
           "unable to generate concretization-specific mirrors.yaml at \"$out_file\""

  local cache_spec cache_name cache_url
  for cache_spec in \
    ${local_caches[*]:+"${local_caches[@]}"} \
    ${concretizing_cache_specs[*]:+"${concretizing_cache_specs[@]}"}
  do
    _cache_info "$cache_spec"
    _cmd $DEBUG_1 spack \
         ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
         mirror add --scope=site ${cache_type:+--type "${cache_type}"} "$cache_name" "$cache_url" ||
      _die $EXIT_SPACK_CONFIG_FAILURE \
           "unable to add $cache_url to concretization-specific mirrors"
  done
  cp "$mirrors_cfg" "$out_file" &&
    mv -f "$mirrors_cfg"{~,} ||
      _die $EXIT_SPACK_CONFIG_FAILURE \
           "unable to generate concretization-specific mirrors.yaml at \"$out_file\""
}

_maybe_cache_binaries() {
  [ "${cache_write_binaries:-none}" == "none" ] && return
  local binary_mirror msg_extra= cache
  if (( is_compiler_env )); then
    binary_mirror=compiler
  else
    binary_mirror=binary
  fi
  local hashes_to_cache_tmp=(${non_root_hashes[*]:+"${non_root_hashes[@]}"})
  if [ "$cache_write_binaries" = "no_roots" ] && ! (( is_compiler_env )); then
    msg_extra=" $cache_write_binaries"
  else
    hashes_to_cache_tmp+=("${root_hashes[@]}")
  fi
  # We need to ask Spack for the location prefix of possibly many
  # packages in order to avoid writing packages to build cache that were
  # already installed from build cache. Do this in one Spack session to
  # avoid unnecessary overhead.
  {
    cat > "$TMP/location_cmds.py" <<\EOF
import spack.environment
import spack.store

all_hashes = spack.environment.active_environment().all_hashes()


def print_prefix_for_hash(spec, hash):
    matching_specs = spack.store.STORE.db.query(hash, hashes=all_hashes, installed=True)
    if len(matching_specs) == 1:
      print(spec, matching_specs[0].prefix)

EOF
  } ||
    _die "I/O error writing to $TMP/location_cmds.py"
  for hash in ${hashes_to_cache_tmp[*]:+"${hashes_to_cache_tmp[@]}"}; do
    _report $DEBUG_4 "scheduling location lookup of $hash"
    echo 'print_prefix_for_hash("'"$hash"'", "'"/${hash//*\///}"'")' >> "$TMP/location_cmds.py"
  done ||
    _die "I/O error writing to $TMP/location_cmds.py"
  local hashes_to_cache=(
    $(
      _cmd $DEBUG_1 $PIPE spack \
           -e $env_name \
           ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
           python "$TMP/location_cmds.py" |
        while read hash prefix; do
          _report $DEBUG_4 "looking for binary_distribution marker for $hash in $prefix/.spack/"
          if [  -f "$prefix/.spack/binary_distribution" ]; then
	          _report_stderr=1 _report $DEBUG_1 "skip package installed from buildcache: $hash"
	        else
	          _report_stderr=1 _report $DEBUG_2 "save package in buildcache: $hash"
            echo "${hash//*\///}"
          fi
        done
    )
  )
  (( $? == 0 )) ||
    _die "unexpected result executing Python script $TMP/location_cmds.py:\n$(cat "$TMP/location_cmds.py")"

  if (( ${#hashes_to_cache[@]} )); then
    for cache in "$working_dir/copyBack/spack-$binary_mirror-cache" \
                   ${extra_sources_write_cache[*]:+"${extra_sources_write_cache[@]}"}; do
      _report $PROGRESS "caching ${#hashes_to_cache[@]}$msg_extra binary packages for environment $env_name to $cache"
      _cmd $DEBUG_1 $PROGRESS \
           spack \
           ${__debug_spack_buildcache:+-d} \
           ${__verbose_spack_buildcache:+-v} \
           ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
           buildcache create --only package \
           ${buildcache_package_opts[*]:+"${buildcache_package_opts[@]}"} \
           ${buildcache_key_opts[*]:+"${buildcache_key_opts[@]}"} \
           ${buildcache_rel_arg} "$cache" \
           "${hashes_to_cache[@]/#//}" ||
        _die "failure caching packages to $cache"
      if [ -d "$cache/build_cache" ] &&
           (( $({ ls -1 "$cache/build_cache/*.json*" | wc -l; } 2>/dev/null) )); then
        _report $PROGRESS "updating build cache index at $cache"
        _cmd $DEBUG_1 $PROGRESS \
             spack \
             ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
             buildcache update-index -k "$cache" ||
          _report $ERROR "failure to update build cache index: manual intervention required for $cache"
      fi
    done
  fi
}

_maybe_cache_sources() {
  ! (( cache_write_sources )) && return
  local cache
  for cache in "$working_dir/copyBack/spack-packages/sources" \
                 ${extra_sources_write_cache[*]:+"${extra_sources_write_cache[@]}"}; do
    _report $PROGRESS "caching sources in mirror $cache"
  _cmd $DEBUG_1 $PROGRESS spack \
       -e $env_name \
       ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
       mirror create -aD --skip-unstable-versions -d "$cache"
  done
}

_maybe_register_compiler() {
  if (( is_compiler_env )); then
    local compiler_spec="${env_spec%%-*}"
    compiler_spec="${compiler_spec/@/@=}"
    compiler_spec="${compiler_spec/@==/@=}"
    compiler_build_spec=${compiler_spec/clang/llvm}
    compiler_build_spec=${compiler_build_spec/oneapi/intel-oneapi-compilers}
    compiler_build_spec=${compiler_build_spec/dpcpp/intel-oneapi-compilers}
    local compiler_path="$(_cmd $DEBUG_2 $PIPE spack \
                    -e $env_name \
                     ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
                     location --install-dir "${compiler_build_spec}" )" \
      || _die $EXIT_PATH_FAILURE "failed to extract path info for new compiler $compiler_spec"
    local binutils_path="$(_cmd $DEBUG_2 $PIPE spack \
                    -e $env_name \
                     ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
                     location --install-dir binutils 2>/dev/null)"
    local compilers_scope="$(_cmd $DEBUG_2 $PIPE spack \
                    -e $env_name \
                    ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
                    arch)"
    compilers_scope="${compilers_scope%-*}"
    compilers_scope="site${compilers_scope:+/${compilers_scope//-//}}"
    _report $DEBUG_1 "registering compiler $compiler_spec at $compiler_path with Spack"
    _cmd $DEBUG_1 spack \
      ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
      compiler find --mixed-toolchain --scope "$compilers_scope" "$compiler_path"
    if [ -n "$binutils_path" ]; then
      # Modify the compiler configuration to prepend binutils to PATH.
      local compilers_yaml="$(_cmd $DEBUG_2 $PIPE spack \
                     ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
                     config --scope "$compilers_scope" edit --print-file compilers)"
      _cmd $DEBUG_2 perl -wapi'' -e 'm&\bcompiler:\s*$&msx and $in_compiler=1; $in_compiler and m&spec:\s*\Q'"$compiler_spec"'\E&msx and $in_wanted_compiler=1; $in_wanted_compiler and s&(^\s*environment:\s*).*$&$1\{ prepend_path: \{ PATH: "'"$binutils_path"'/bin" \} \}\n&msx and undef $in_wanted_compiler and undef $in_compiler' "$compilers_yaml" || _die $EXIT_SPACK_CONFIG_FAILURE "unable to configure compiler binutils path for $compiler_spec"
    fi
    if [[ "$compiler_spec" == *clang* ]]; then
      _cmd $DEBUG_2 perl -wapi'' -e 'm&\bcompiler:\s*$&msx and $in_compiler=1; $in_compiler and m&spec:\s*\Q'"$compiler_spec"'\E&msx and $in_wanted_compiler=1; $in_wanted_compiler and s&(^\s*flags:\s*).*$&$1\{ cxxflags: -stdlib=libc++ \}\n&msx and undef $in_wanted_compiler and undef $in_compiler' "$compilers_yaml" || _die $EXIT_SPACK_CONFIG_FAILURE "unable to configure compiler flags for $compiler_spec"
    fi
  fi
}

# Restore previously-saved mirrors.yaml (see
# _maybe_swap_mirror_config()).
_maybe_restore_mirror_config() {
  if (( concretize_safely )); then
    _report $PROGRESS "restoring cache configuration post-concretization"
    mv -f "$mirrors_cfg"{~,} ||
      _die $EXIT_PATH_FAILURE "failed to restore original \"$mirrors_cfg\""
  fi
}

# Copy our concretization-specific mirrors configuration into place to
# prevent undue influence of external mirrors on the concretization
# process.
_maybe_swap_mirror_config() {
  if (( concretize_safely )); then
    _report $PROGRESS "applying temporary minimal cache configuration for safe concretization"
    cp -p "$mirrors_cfg"{,~} \
      && cp "$concretize_mirrors" "$mirrors_cfg" \
        || _die $EXIT_PATH_FAILURE "failed to install \"$concretize_mirrors\" prior to concretizing $env_name"
  fi
}

_piecemeal_build() {
  local extra_cmd_opts+=(--no-cache) # Ensure roots are built even if in cache.
  {
    cat > "$TMP/dep_hash_cmds.py" <<\EOF
import spack.cmd as cmd
import spack.traverse
import spack.environment as ev

env = ev.active_environment()
concretized_root_specs = [env.specs_by_hash[h] for h in env.concretized_order]
specs = list(spack.traverse.traverse_nodes(concretized_root_specs, root=False))
filtered_hashes = [s.format("{namespace}.{name}{/hash}") for s in specs if not (s.installed or any(c in s for c in concretized_root_specs))]
if filtered_hashes:
    print(*filtered_hashes, sep="\n")
EOF
  } || _die "I/O error writing to $TMP/dep_hash_cmds.py"
  local hashes_to_install=(
    $(_cmd $DEBUG_1 $PIPE spack \
           -e $env_name \
           ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
           python "$TMP/dep_hash_cmds.py")
  )
  (( $? == 0 )) ||
    _die "unexpected result executing Python script $TMP/dep_hash_cmds.py:\n$(cat "$TMP/dep_hash_cmds.py")"
  if (( ${#hashes_to_install[@]} )); then
    _report $DEBUG_2 "building ${#hashes_to_install[@]} non-root dependencies in environment $env_name"
    _report $DEBUG_4 "            ${hashes_to_install[@]/%/$'\n'           }"
    _cmd $DEBUG_1 $INFO \
         "${spack_install_cmd[@]}" \
         ${hashes_to_install[*]:+"${hashes_to_install[@]/*\///}"} || return
  fi
  _report $PROGRESS "building${hashes_to_install[*]:+ remaining package(s) in} environment $env_name"
  _cmd $DEBUG_1 $INFO "${spack_install_cmd[@]}" ${extra_cmd_opts[*]:+"${extra_cmd_opts[@]}"}
}

_process_environment() {
  local env_cfg="$1"
  if [[ "$env_cfg" =~ ^[a-z][a-z0-9_-]*://(.*/)?(.*) ]]; then
    curl -o "${BASH_REMATCH[2]}" -fkLNSs "$env_cfg" \
      || _die $EXIT_CONFIG_FAILURE "unable to obtain specified environment config file \"$env_cfg\""
    env_cfg="${BASH_REMATCH[2]}"
  fi
  env_name="${env_cfg##*/}"
  env_name="${env_name%.yaml}"
  env_name="${env_name//[^A-Za-z0-9_-]/-}"
  env_name="${env_name##-}"
  spack \
    ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
    env rm -y $env_name >/dev/null 2>&1
  _report $PROGRESS "creating environment $env_name from $env_cfg"
  _cmd $DEBUG_1 spack \
    ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
    env create $view_opt $env_name "$env_cfg" \
    || _die $EXIT_SPACK_ENV_FAILURE "unable to create environment $env_name from $env_cfg"

  # Record an intentional stoppage. EXIT trap will take care of
  # log/cache preservation.
  trap 'interrupt=$?; trap - HUP INT QUIT TERM; _report $INFO "user interrupt"' HUP INT QUIT TERM

  local is_compiler_env=
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
  (( ++env_idx ))
  [[ "$env_spec"  =~ ^$known_compilers_re[@-][0-9] ]] \
    && is_compiler_env=1 \
    && (( num_environments > env_idx )) \
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
  local env_tests_arg=
  (( is_nonterminal_compiler_env )) || env_tests_arg=${tests_arg:+"$tests_arg"}
  local hashes=() non_root_hashes=() root_hashes=() n_hashes= idx=0
  _maybe_swap_mirror_config &&
    _cmd $DEBUG_1 $PROGRESS \
         spack \
         -e $env_name \
         ${__debug_spack_concretize:+-d} \
         ${__verbose_spack_concretize:+-v} \
         ${common_spack_opts[*]:+"${common_spack_opts[@]}"} \
         concretize ${env_tests_arg:+"$env_tests_arg"}  &&
    _maybe_restore_mirror_config &&
    _classify_concretized_specs &&
    _maybe_cache_sources &&
    _do_build_and_test || failed=1
  if [ -n "$interrupt" ]; then
    failed=1 # Trigger buildcache dump.
    local tag_text=ALERT
    _die $interrupt "exit due to caught signal ${interrupt:-(HUP, INT, QUIT or TERM)}"
  fi
  (( failed == 0 )) || _die "failed to build environment $env_name" 1>&2
  ####################################

  ####################################
  # Store all successfully-built packages in the buildcache if
  # appropriate.
  _maybe_cache_binaries
  ####################################

  ####################################
  # If we just built a compiler environment, add the
  # compiler to the list of available compilers.
  _maybe_register_compiler
  ####################################
}

# Properly quote a message for protection from the shell if copy/pasted.
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

_remove_hash() {
  local hashes_var="$1"
  shift
  local OIFS="$IFS"; IFS=$'\n'; IFS="$OIFS"
  handled_hashes=($(echo "$*" | sort -u))
  IFS="$OIFS"
  eval local "hashes=(\${$hashes_var[*]:+\"\${$hashes_var[@]}\"})"
  (( ${#hashes[@]} )) || return
  local filtered_hashes=()
  for hash in ${hashes[*]:+"${hashes[@]}"}; do
    _in_sorted_hashlist "$hash" "${handled_hashes[@]}" ||
      filtered_hashes+=("$hash")
  done
  eval $hashes_var="(\${filtered_hashes[*]:+\"\${filtered_hashes[@]}\"})"
}

# Print a message with the specifed numeric first argument or 0 as
# severity.
_report() {
  local severity=$DEFAULT_VERBOSITY redirect=">&$STDOUT"
  if [[ "$1" =~ ^-?[0-9]*$ ]]; then (( severity = $1 )); shift; fi
  (( VERBOSITY < severity )) && return # Diagnostics suppression.
  (( _report_stderr || severity < INFO )) && redirect=">&$STDERR" # Important to stderr.
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
    $ERROR) tag="${want_color:+\e[1;31m}==> ${tag_text:-${DIE_ERROR:+$DIE_ERROR }ERROR}${want_color:+\e[m}";;
    $WARNING) tag="${want_color:+\e[1;33m}==> ${tag_text:-WARNING}${want_color:+\e[m}";;
    $INFO) tag="${want_color:+\e[1;34m}==> ${tag_text:-INFO}${want_color:+\e[m}";;
    $PROGRESS) tag="${want_color:+\e[1;32m}==> ${tag_text:-PROGRESS}${want_color:+\e[m}";;
    *) tag="${want_color:+\e[1m}==> ${tag_text:-DEBUG_$(( $1 - DEBUG_0 ))}${want_color:+\e[m}"
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

# Initial and default values for global variables/options.
cache_specs=()
cache_write_binaries=all
cache_write_sources=1
color=
common_spack_opts=(--backtrace --timestamp)
concretize_safely=1
concretizing_cache_specs=()
extra_binaries_write_cache=()
extra_sources_write_cache=()
fail_fast=1
no_auto_recipe_repos=
recipe_repos=()
si_root=https://github.com/FNALssi/fermi-spack-tools.git
si_ver=main
spack_config_cmds=()
spack_config_files=()
spack_source_dir="./"
spack_ver=v0.22.0-fermi
upgrade_etc=1
upgrade_extensions=1
upgrade_recipes=
upgrade_spack=
ups_opt=-p
want_emergency_buildcache=1

eval "$ssi_split_options"
while (( $# )); do
  case $1 in
    --cache-write-binaries) _set_cache_write_binaries "$2"; shift;;
    --cache-write-binaries=*) _set_cache_write_binaries "${1#*=}";;
    --extra-binaries-write-cache) extra_binaries_write_cache+=("$2"); shift;;
    --extra-binaries-write-cache=*) extra_binaries_write_cache+=("${1#*=}");;
    --cache-write-sources) cache_write_sources=1;;
    --extra-sources-write-cache) extra_sources_write_cache+=("$2");;
    --extra-sources-write-cache=*) extra_sources_write_cache+=("${1#*=}");;
    --clear-mirrors) clear_mirrors=1;;
    --color) color="$2"; shift;;
    --color=*) color="${1#*=}";;
    --debug-spack-*|--verbose-spack-*) eval "${1//-/_}=1";;
    --debug-tmp) debug_tmp=1;;
    --emergency-buildcache) want_emergency_buildcache=1;;
    --fail-fast) fail_fast=1;;
    --help|-h|-\?) usage 2; exit 1;;
    --no-auto-recipe-repos) no_auto_recipe_repos=1;;
    --no-cache-write-binaries) _set_cache_write_binaries "none";;
    --no-cache-write-sources) unset cache_write_sources;;
    --no-emergency-buildcache) unset want_emergency_buildcache;;
    --no-fail-fast) unset fail_fast;;
    --no-view) view_opt="--without-view";;
    --no-query-packages) unset query_packages;;
    --no-safe-concretize) unset concretize_safely;;
    --no-upgrade-etc) unset upgrade_etc;;
    --no-upgrade-extensions) unset upgrade_extensions;;
    --no-upgrade-recipes) unset upgrade_recipes;;
    --no-upgrade-spack) unset upgrade_spack;;
    --no-ups) ups_opt=-p;;
    --query-packages) query_packages=1;;
    --quiet|-q) (( VERBOSITY = WARNING ));;
    --safe-concretize) concretize_safely=1;;
    --spack-config-cmd) spack_config_cmds+=("$2"); shift;;
    --spack-config-cmd=*) spack_config_cmds+=("${1#*=}");;
    --spack-config-file) spack_config_files+=("$2"); shift;;
    --spack-config-file=*) spack_config_files+=("${1#*=}");;
    --fermi-spack-tools-root) si_root="$2"; shift;;
    --fermi-spack-tools-root=*) si_root="${1#*=}";;
    --fermi-spack-tools-version) si_ver="$2"; shift;;
    --fermi-spack-tools-version=*) si_ver="${1#*=}";;
    --spack-python) spack_python="$2"; shift;;
    --spack-python=*) spack_python="${1#*=}";;
    --spack-repo) recipe_repos+=("$2"); shift;;
    --spack-repo=*) recipe_repos+=("${1#*=}");;
    --spack-root) spack_root="$2"; shift;;
    --spack-root=*) spack_root="${1#*=}";;
    --spack-version) spack_ver="$2"; shift;;
    --spack-version=*) spack_ver="${1#*=}";;
    --test) tests_type="$2"; shift;;
    --test=*) tests_type="${1#*=}";;
    --upgrade-etc) upgrade_etc=1;;
    --upgrade-extensions) upgrade_extensions=1;;
    --upgrade-recipes) upgrade_recipes=1;;
    --upgrade-spack) upgrade_spack=1;;
    --ups) ups_opt="$(_ups_string_to_opt "$2")" || exit; shift;;
    --ups=*) ups_opt="$(_ups_string_to_opt "${1#*=}")" || exit;;
    +v) (( --VERBOSITY ));;
    -v) (( ++VERBOSITY ));;
    --verbosity) eval "(( VERBOSITY = $2 ))"; shift;;
    --verbosity=*) eval "(( VERBOSITY = ${1#*=} ))";;
    --with-cache)
      optarg="$2"; shift; OIFS="$IFS"; IFS=","
      cache_specs+=($optarg); IFS="$OIFS"
      ;;
    --with-cache=*)
      optarg="${1#*=}"; OIFS="$IFS"; IFS=","
      cache_specs+=($optarg); IFS="$OIFS"
      ;;
    --with-concretize-cache|--with-concretizing-cache|--with-concretization-cache)
      optarg="$2"; shift; OIFS="$IFS"; IFS=","
      concretizing_cache_specs+=($optarg); IFS="$OIFS"
      ;;
    --with-concretize-cache=*|--with-concretizing-cache=*|--with-concretization-cache=*)
      optarg="${1#*=}"; OIFS="$IFS"; IFS=","
      concretizing_cache_specs+=($optarg); IFS="$OIFS"
      ;;
    --with-padding) with_padding=1;;
    --working-dir=*) working_dir="${1#*=}";;
    --working_dir) working_dir="$2"; shift;;
    --) shift; break;;
    -*) _die $EXIT_CONFIG_FAILURE "unrecognized option $1\n$(usage)";;
    *) break
  esac
  shift
done

color_arg=${color:+--color=$color}
if [ "${color:-auto}" = "auto" -a -t 1 ] || [ "$color" = "always" ]; then
  want_color=1
else
  unset want_color
fi
common_spack_opts+=($color_arg)

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

# Temporary working area (and cleanup trap).
TMP="$(mktemp -d -t build-spack-env.sh.XXXXXX)"
(( debug_tmp )) && _report $INFO "generated files will be preserved in $TMP"
trap "! (( debug_tmp )) && [ -d \"$TMP\" ] && rm -rf \"$TMP\" 2>/dev/null" EXIT

# Local cache locations are derived from $working_dir.
local_caches=(
  "__local_binaries|binary:$working_dir/copyBack/spack-binary-cache"
  "__local_compilers|binary:$working_dir/copyBack/spack-compiler-cache"
  "__local_sources|source:$working_dir/copyBack/spack-packages/sources"
)

spack_env_top_dir="$working_dir/spack_env"
case "$ups_opt" in
    -p) :;;
    -[ut]) _report $WARNING "deprecated --ups option \"$ups_opt\" ignored.";;
    -*) _die $EXIT_CONFIG_FAILURE "unrecognized --ups option $ups_opt\n$(usage)";;
    *) break
esac


###################################
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
  roots) buildcache_package_opts+=(--only package);;
  dep*) buildcache_package_opts+=(--only dependencies);;
  *) _die $EXIT_CONFIG_FAILURE "unknown --cache-write-binaries argument $cache_write_binaries\n$(usage)"
esac
####################################

si_upsver="v${si_ver#v}"
####################################
# Install fermi-spack-tools to bootstrap a Spack installation.
_report $PROGRESS "cloning fermi-spack-tools"
_cmd $DEBUG_1 git clone -b "$si_ver" "$si_root" "$TMP/" \
  || _die "unable to clone fermi-spack-tools $si_ver from $si_root"
if [[ "${spack_config_files[*]}" =~ (^|/)packages\.yaml([[:space:]]|$) ]]; then
  # Bypass packages.yaml generation if we're going to ignore it anyway.
  _report $DEBUG_2 "bypassing packages.yaml generation"
  _cmd $DEBUG_2 ln -sf /usr/bin/true "$TMP/bin/make_packages_yaml"
else
  # Don't want externals from CVMFS.
  _report $DEBUG_2 "externals in CVMFS will be excluded from generated packages.yaml"
  _cmd $DEBUG_2 sed -Ei'' -e 's&^([[:space:]]+(cvmfsversions|cprefix)=).*$&\1'"''"'&' "$TMP/bin/make_packages_yaml"
fi
####################################

####################################
# Bootstrap the Spack installation.
mkdir -p "$spack_env_top_dir" \
  || _die $EXIT_PATH_FAILURE "unable to make directory structure for spack environment installation"
cd "$spack_env_top_dir"
make_spack_cmd=(
  make_spack
  ${spack_root:+--spack_repo "$spack_root"}
  --spack_release $spack_ver
  --minimal
  ${no_auto_recipe_repos:+"--no-recipe-repos"}
  ${upgrade_etc:+"--upgrade-etc"}
  ${upgrade_extensions:+"--upgrade-extensions"}
  ${upgrade_recipes:+"--upgrade-recipes"}
  ${upgrade_spack:+"--upgrade-spack"}
  $ups_opt
)
(( VERBOSITY < DEBUG_1 )) || make_spack_cmd+=(-v)
(( query_packages )) && make_spack_cmd+=(--query-packages)
(( with_padding )) && make_spack_cmd+=(--with_padding)
make_spack_cmd+=("$spack_env_top_dir")
_report $PROGRESS "bootstrapping Spack $spack_ver"
PATH="$TMP/bin:$PATH" \
    _cmd $PROGRESS ${make_spack_cmd[*]:+"${make_spack_cmd[@]}"} \
  || _die "unable to install Spack $spack_ver"

# Enhanced setup scripts.
if ! { [ -e "setup-env.sh" ] || [ -e "setup-env.csh" ]; } &&
    [ "$ups_opt" = "-p" ]; then
  cat >setup-env.sh <<EOF
export PATH="$(echo "$PATH" | sed -Ee 's&(^|:)[^/][^:]*&&g')"
. "$spack_env_top_dir/share/spack/setup-env.sh"
export SPACK_DISABLE_LOCAL_CONFIG=true
export SPACK_USER_CACHE_PATH="$spack_env_top_dir/tmp/spack-cache"
export TMPDIR="\${TMPDIR:-$TMPDIR}"
EOF
  cat >setup-env.csh <<EOF
setenv PATH "`echo "$PATH" | sed -Ee 's&(^|:)[^/][^:]*&&g'`"
source "$spack_env_top_dir/share/spack/setup-env.csh"
setenv SPACK_DISABLE_LOCAL_CONFIG true
setenv SPACK_USER_CACHE_PATH "$spack_env_top_dir/tmp/spack-cache"
if (! $?TMPDIR) then
  setenv TMPDIR "$TMPDIR"
endif
EOF
fi
####################################

####################################
# Source the setup script.
_report $PROGRESS "configuring Spack $spack_ver for use"
source "$spack_env_top_dir/setup-env.sh" \
  || _die "unable to set up Spack $spack_ver"
####################################

mirrors_cfg="$SPACK_ROOT/etc/spack/mirrors.yaml"
default_mirrors="$SPACK_ROOT/etc/spack/defaults/mirrors.yaml"
concretize_mirrors="$SPACK_ROOT/concretize_mirrors.yaml"

_configure_spack

####################################
# Safe, comprehensive cleanup.
trap "trap - EXIT; \
! (( debug_tmp )) && [ -d \"$TMP\" ] && rm -rf \"$TMP\" 2>/dev/null; \
[ -f \"\$mirrors_cfg~\" ] && mv -f \"\$mirrors_cfg\"{~,}; \
_copy_back_logs; \
if (( failed )) && (( want_emergency_buildcache )); then \
  tag_text=ALERT _report $ERROR \"emergency buildcache dump\"; \
  for spec in \$(spack find -L | sed -Ene 's&^([[:alnum:]]+).*\$&/\\1&p');do \
    if [  -f \"\$(spack location -i \$spec)/.spack/binary_distribution\" ]; then
      tag_text=ALERT _report $ERROR skipping package installed from buildcache \$spec;\
      else \
      _cmd $ERROR $PIPE spack \
      \${common_spack_opts[*]:+\"\${common_spack_opts[@]}\"} \
      buildcache create \
      \${buildcache_package_opts[*]:+\"\${buildcache_package_opts[@]}\"} \
      \${buildcache_key_opts[*]:+\"\${buildcache_key_opts[@]}\"} \
      \$buildcache_rel_arg --rebuild-index \
      \"$working_dir/copyBack/spack-emergency-cache\" \
     \$spec; \
     fi \
  done;\
  tag_text=ALERT _report $ERROR \"emergency buildcache dump COMPLETE\"; \
fi; \
exec $STDOUT>&- $STDERR>&-\
" EXIT
####################################

known_compilers=($(ls -1 "$SPACK_ROOT/lib/spack/spack/compilers/"[A-Za-z]*.py | sed -Ene 's&^.*/(.*)\.py$&\1&p'))
OIFS="$IFS"
IFS='|'
known_compilers_re="(${known_compilers[*]})"
IFS="$OIFS"

environment_specs=("$@")
num_environments=${#environment_specs[@]}
env_idx=0

if (( ! num_environments )); then # NOP
  _report $INFO "no environment configurations specified: exiting after setup"
else
  ####################################
  # Build each specified environment.
  for env_cfg in ${environment_specs[*]:+"${environment_specs[@]}"}; do
    _report $PROGRESS "processing user-specified environment configuration $env_cfg"
    _process_environment "$env_cfg"
  done
  ####################################
fi

### Local Variables:
### mode: sh
### eval: (sh-set-shell "bash" t nil)
### End:
