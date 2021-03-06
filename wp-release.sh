#!/bin/bash
#
# Creates and pushes a git tag to the svn WordPress.org Plugin Directory.

SELFDIR=${BASH_SOURCE%/*}

source .wp-release.conf

# Validate configuration.
[[ -n $SHORTNAME ]] || { echo >&2 "ERROR: Plugin shortname must not be empty."; exit 1; }
[[ -e $PLUGINPATH ]] || { echo >&2 "ERROR: Configured plugin path does not exist."; exit 1; }
[[ -e $PLUGINPATH/$MAINFILE ]] || { echo >&2 "ERROR: Configure main plugin file does not exist."; exit 1; }
[[ -n $SVNUSER ]] || { echo >&2 "ERROR: Subversion username must not be empty."; exit 1; }

# Initialize variables.
SVNURL=${SVNURL:="http://plugins.svn.wordpress.org/$SHORTNAME/"}
SVNCMD="svn --username=$SVNUSER"

if [[ $DRYRUN != 0 ]]; then
	DRYRUN="echo +"
else
	DRYRUN=
fi

# Output header.
echo
echo "Project: $SHORTNAME"
echo "Source:  $PLUGINPATH"
echo "Workdir: $SVNPATH"
echo "Target:  $SVNURL"
echo

# Validate new version.
NEWVERSION=`grep -E "Version:" "$PLUGINPATH/$MAINFILE" | awk -F' ' '{print $2}'`
READMEVERSION=`grep "^Stable tag" "$PLUGINPATH/readme.txt" | awk -F' ' '{print $3}'`

echo "$MAINFILE version: $NEWVERSION"
echo "readme.txt version: $READMEVERSION"

if [ "$NEWVERSION" != "$READMEVERSION" ]; then
	echo >&2 "ERROR: readme.txt version does not match version in $MAINFILE."
	exit 1
fi

if git show-ref --tags --quiet --verify -- "refs/tags/$NEWVERSION"; then
	echo -e "WARNING: git tag $NEWVERSION already exists.  Continue without git changes? (Y/n) [n] \c"
	read CONFIRMED
	[[ $CONFIRMED == "Y" ]] || { echo "Aborted."; exit 1; }
else
	# Review and confirm changes to be committed/released.
	echo "Review and confirm changes to be committed/released:"
	echo
	$DRYRUN git commit -pem "Preparing release $NEWVERSION."

	echo
	echo -e "Ready to tag release in git? (Y/n) [n] \c"
	read CONFIRMED
	[[ $CONFIRMED == "Y" ]] || { echo "Aborted."; exit 1; }

	echo
	echo "Tagging release in git..."
	$DRYRUN git tag -a "$NEWVERSION" -m "Tagging release $NEWVERSION."

	# Safety net; pushing tags to the public is ultimate.
	echo
	echo -e "Ready to publish release to git? (Y/n) [n] \c"
	read CONFIRMED
	[[ $CONFIRMED == "Y" ]] || { echo "Aborted."; exit 1; }

	echo
	echo "Pushing master to origin, including tags..."
	$DRYRUN git push origin master --tags
fi


# Begin Subversion dump-export process.
echo
echo "Checking out SVN repository in $SVNPATH..."
$SVNCMD checkout $SVNURL $SVNPATH

echo
echo "Setting svn:ignore for git and release specific files..."
svn propset svn:ignore "
README.md
.git*
.wp-release.conf
" "$SVNPATH/trunk/"

echo
echo "Exporting git HEAD of master to SVN trunk..."

# Delete existing files to capture deleted files.
find $SVNPATH/trunk/ -type f -exec rm '{}' ';'
# Export current files.
git checkout-index --all --force --prefix=$SVNPATH/trunk/

# Recursively check out submodules, if any.
if [ -f ".gitmodules" ]; then
	echo "Exporting git HEAD of submodules to SVN trunk..."
	git submodule init
	git submodule update
	git submodule foreach --recursive 'git checkout-index --all --force --prefix=$SVNPATH/trunk/$path/'
fi

echo
echo "Exporting to SVN..."
pushd $SVNPATH > /dev/null
pushd trunk > /dev/null

# Note: On Windows, svn status outputs backslashes instead of slashes.

# Delete missing/deleted files.
svn status | grep "^!" | awk '{gsub(":\\\\", "/", $2); gsub("\\\\", "/", $2); print $2}' | xargs svn delete
# Add new files.
# svn:ignore files are not listed.
svn status | grep "^?" | awk '{gsub(":\\\\", "/", $2); gsub("\\\\", "/", $2); print $2}' | xargs svn add

# Extra safety net; SVN does not allow to rewrite history.
echo
echo "Changes to be committed to SVN:"
svn status
echo
echo -e "Ready to publish release to SVN? (Y/n) [n] \c"
read CONFIRMED
[[ $CONFIRMED == "Y" ]] || { echo "Aborted."; exit 1; }

$DRYRUN $SVNCMD commit -m "Preparing release $NEWVERSION."

echo
echo "Creating and committing SVN tag..."
popd > /dev/null
svn copy trunk tags/$NEWVERSION
pushd tags/$NEWVERSION > /dev/null
$DRYRUN $SVNCMD commit -m "Tagging release $NEWVERSION."
popd > /dev/null

echo "Done."
popd > /dev/null
