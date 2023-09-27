#
# Linear
#

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

SPACESHIP_LINEAR_SHOW="${SPACESHIP_LINEAR_SHOW=true}"
SPACESHIP_LINEAR_API_KEY="${SPACESHIP_LINEAR_API_KEY=""}"
SPACESHIP_LINEAR_LINK="${SPACESHIP_LINEAR_LINK="true"}" # true, false or `text`
SPACESHIP_LINEAR_ASYNC="${SPACESHIP_LINEAR_ASYNC=true}"
SPACESHIP_LINEAR_PREFIX="${SPACESHIP_LINEAR_PREFIX="$SPACESHIP_PROMPT_DEFAULT_PREFIX"}"
SPACESHIP_LINEAR_SUFFIX="${SPACESHIP_LINEAR_SUFFIX="$SPACESHIP_PROMPT_DEFAULT_SUFFIX"}"
SPACESHIP_LINEAR_SYMBOL="${SPACESHIP_LINEAR_SYMBOL="󰻿 "}"
SPACESHIP_LINEAR_COLOR="${SPACESHIP_LINEAR_COLOR="white"}"
SPACESHIP_LINEAR_TITLE_MAX_LENGTH="${SPACESHIP_LINEAR_TITLE_MAX_LENGTH=35}"
SPACESHIP_LINEAR_CACHE_DIR="${SPACESHIP_LINEAR_CACHE_DIR="/tmp/.spaceship-linear"}"
SPACESHIP_LINEAR_CACHE_TTL_SECONDS="${SPACESHIP_LINEAR_CACHE_TTL_SECONDS=1800}"

# Function to check if a directory is a Git repository
function is_git_repo() {
  git rev-parse --is-inside-work-tree &>/dev/null
  return $?
}

function seconds_since_last_modified() {
  local file=$1
  local current_time=$(date +%s)
  local file_mod_time=$(stat -f%c $file)

  echo "$(($current_time - $file_mod_time))"
}

function fetch_data() {
  local issue_id=$1
  local linear_api_key="$SPACESHIP_LINEAR_API_KEY"
  local response=$(curl \
    -s \
    -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: $linear_api_key" \
    --data '{ "query": "{ organization {urlKey} issue(id: \"'$issue_id'\") { title url }}" }' \
    https://api.linear.app/graphql)

  echo "$response" | jq -r '.data'
}

function fetch_data_cached() {
  local issue_id=$1
  local cache_file="$SPACESHIP_LINEAR_CACHE_DIR/$issue_id.json"
  #echo "Debug $cache_file"
  #echo "Debug $(seconds_since_last_modified "$cache_file")"

  if [[ ! -f "$cache_file" ]] || [[ "$(seconds_since_last_modified "$cache_file")" -ge "$SPACESHIP_LINEAR_CACHE_TTL_SECONDS" ]]; then
    #echo "CACHE MISS"
    local data=$(fetch_data "$issue_id" || '')
    if [[ $data ]] && [[ $data != null ]]; then
      echo $data >"$cache_file"
    fi
  fi

  [[ -f "$cache_file" ]] && cat $cache_file
}
function get_linear_id_from_branch_name() {
  local branch=$1
  local pattern="\b[A-Za-z]{3,4}-[0-9]+\b"
  local matches=$(echo "$branch" | grep -oE "$pattern")
  echo "$matches"
}

# Function to match branch name with Linear issue
function match_branch_to_linear() {
  local branch=$1
  local formatted_branch=$(get_linear_id_from_branch_name "$branch")
  if [ -z "$formatted_branch" ]; then
    return
  fi
  echo "$formatted_branch"
}

# Function to retrieve the current branch name
function get_current_branch() {
  git symbolic-ref --short HEAD 2>/dev/null
}

mkdir -p $SPACESHIP_LINEAR_CACHE_DIR

# ------------------------------------------------------------------------------
# Start linear spaceship plugin
# ------------------------------------------------------------------------------

# Show linear ticket title
# spaceship_ prefix before section's name is required!
# Otherwise this section won't be loaded.
spaceship_linear() {
  # If SPACESHIP_LINEAR_SHOW is false, don't show linear section
  [[ $SPACESHIP_LINEAR_SHOW == false ]] && return

  [[ ! is_git_repo ]] && return

  local branch=$(get_current_branch)
  [[ -z "$branch" ]] && return

  local issue_id=$(match_branch_to_linear "$branch")

  [[ -z "$issue_id" ]] && return

  if [[ -z "$SPACESHIP_LINEAR_API_KEY" ]]; then
    spaceship::section::v4 \
      --color "red" \
      '!! Linear API key not set. See github.com/bjoerge/spaceship-linear#add-linear-api-key'
    return 0
  fi

  local data=$(fetch_data_cached $issue_id)

  # If there's no linear data returned
  ([[ -z "$data" ]] || [[ $data == null ]]) && return

  local title=$(echo "$data" | jq -r '.issue.title' | sed "s/\(.\{$SPACESHIP_LINEAR_TITLE_MAX_LENGTH\}\).*/\1…/")
  local url_key=$(echo "$data" | jq -r '.organization.urlKey')

  local full_url="https://linear.app/$url_key/issue/$issue_id"
  local short_url="linear.app/$url_key/issue/$issue_id"

  local reset="\e[0m"
  local link_color="\e[0;37m"

  spaceship::section::v4 \
    --color "$SPACESHIP_LINEAR_COLOR" \
    --prefix "$SPACESHIP_LINEAR_PREFIX" \
    --suffix "$SPACESHIP_LINEAR_SUFFIX" \
    --symbol "$SPACESHIP_LINEAR_SYMBOL" \
    $(
      [[ $SPACESHIP_LINEAR_LINK == "text" ]] &&
        echo -e "\e]8;;$full_url\a$title\e]8;;\a" ||
        echo "$title$([[ $SPACESHIP_LINEAR_LINK == false ]] || echo " $link_color($short_url)$reset")"
    )
}

