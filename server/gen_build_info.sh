#!/bin/bash

###
# The MIT License (MIT)
#
# Copyright (c) <2015>
# - Mathieu Bodjikian <mathieu@bodjikian.fr>
# - Charles-Antoine Mathieu <skatkatt@root.gg>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
###

set -e

# some variables
version=$1
user=$(whoami)
host=$(hostname)
repo=$(pwd)
date=$(date "+%s")
isRelease=false
isMint=false

# get git current revision
sh=`git rev-list --pretty=format:%h HEAD --max-count=1 | sed '1s/commit /full_rev=/;2s/^/short_rev=/'`
eval "$sh"  # Sets the full_rev & short_rev variables.

# get git version tag
tag=$(git show-ref --tags | egrep "refs/tags/$version$" | cut -d " " -f1)
if [[ $tag = $full_rev ]]; then
    isRelease=true
fi

# get repository status
is_mint_repo() {
  git rev-parse --verify HEAD >/dev/null &&
  git update-index --refresh >/dev/null &&
  git diff-files --quiet &&
  git diff-index --cached --quiet HEAD
}
if is_mint_repo; then
    isMint=true
fi

# compute clients code
clients=""
clientList=$(find clients -name "plik*" 2> /dev/null | sort -n)
for client in $clientList ; do
	folder=$(echo $client | cut -d "/" -f2)
	binary=$(echo $client | cut -d "/" -f3)
	os=$(echo $folder | cut -d "-" -f1)
	arch=$(echo $folder | cut -d "-" -f2)
	md5=$(md5sum $client | cut -d " " -f1)

	prettyOs=""
	prettyArch=""

	case "$os" in
		"darwin") 	prettyOs="MacOS" ;;
		"linux") 	prettyOs="Linux" ;;
		"windows") 	prettyOs="Windows" ;;
		"openbsd")	prettyOs="OpenBSD" ;;
		"freebsd")	prettyOs="FreeBSD" ;;
		"bash")		prettyOs="Bash (curl)" ;;
	esac

	case "$arch" in
		"386")		prettyArch="32bit" ;;
		"amd64")	prettyArch="64bit" ;;
		"arm")		prettyArch="ARM" ;;
	esac

	fullName="$prettyOs $prettyArch"
	clientCode="&Client{Name: \"$fullName\", Md5: \"$md5\", Path: \"$client\", OS: \"$os\", ARCH: \"$arch\"}"
	clients+=$'\t\t'"buildInfo.Clients = append(buildInfo.Clients, $clientCode)"$'\n'
done


cat > "server/common/version.go" <<EOF 
package common

import (
	"fmt"
	"strings"
	"time"
)

var buildInfo *BuildInfo

type BuildInfo struct {
	Version string \`json:"version"\`
	Date    int64  \`json:"date"\`

	User string \`json:"user"\`
	Host string \`json:"host"\`

	GitShortRevision string \`json:"gitShortRevision"\`
	GitFullRevision  string \`json:"gitFullRevision"\`

	IsRelease bool \`json:"isRelease"\`
	IsMint    bool \`json:"isMint"\`

	Clients []*Client \`json:"clients"\`
}

type Client struct {
	Name string \`json:"name"\`
	Md5  string \`json:"md5"\`
	Path string \`json:"path"\`
	OS   string \`json:"os"\`
	ARCH string \`json:"arch"\`
}

func GetBuildInfo() *BuildInfo {
	if buildInfo == nil {
		buildInfo = new(BuildInfo)
		buildInfo.Clients = make([]*Client, 0)

		buildInfo.Version = "$version"
		buildInfo.Date = $date

		buildInfo.User = "$user"
		buildInfo.Host = "$host"

		buildInfo.GitShortRevision = "$short_rev"
		buildInfo.GitFullRevision = "$full_rev"

		buildInfo.IsRelease = $isRelease
		buildInfo.IsMint = $isMint
$clients
	}

	return buildInfo
}

func (bi *BuildInfo) String() string {

	v := fmt.Sprintf("v%s (built from git rev %s", bi.Version, bi.GitShortRevision)

	// Compute flags
	flags := make([]string, 0)
	if buildInfo.IsMint {
		flags = append(flags, "mint")
	}
	if buildInfo.IsRelease {
		flags = append(flags, "release")
	}

	if len(flags) > 0 {
		v += fmt.Sprintf(" [%s]", strings.Join(flags, ","))
	}

	v += fmt.Sprintf(" at %s)", time.Unix(bi.Date, 0))

	return v
}
EOF
