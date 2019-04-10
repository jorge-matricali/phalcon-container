#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

phalconVersions=(
3.4.3
3.4.2
)
phpVersions=(
'_phpv=(7.1 7.2 7.3)'
'_phpv=(5.6 7.0)'
)
suites=(
stretch
)
variants=(
zts
fpm
apache
cli
)

generated_warning() {
	cat <<-EOH
		#
		# NOTE: THIS DOCKERFILE IS GENERATED VIA "update.sh"
		#
		# PLEASE DO NOT EDIT IT DIRECTLY.
		#

	EOH
}

i=0;
travisEnv=
for phalconVersion in "${phalconVersions[@]}"; do
	for _tmp in "${phpVersions[$i]}"; do
		(( i += 1 ))
		eval "$_tmp";
		for phpVersion in "${_phpv[@]}"; do
			phalconUrl="https://codeload.github.com/phalcon/cphalcon/tar.gz/v${phalconVersion}"
			rcVersion="${phalconVersion%-rc}"

			# "7", "5", etc
			majorVersion="${rcVersion%%.*}"
			# "2", "1", "6", etc
			minorVersion="${rcVersion#$majorVersion.}"
			minorVersion="${minorVersion%%.*}"

			for suite in "${suites[@]}"; do

				[ -d "$majorVersion.$minorVersion/php$phpVersion/$suite" ] || continue
				alpineVer="${suite#alpine}"

				baseDockerfile=Dockerfile-debian.template
				if [ "${suite#alpine}" != "$suite" ]; then
					baseDockerfile=Dockerfile-alpine.template
				fi

				for variant in "${variants[@]}"; do

					variantPath="$majorVersion.$minorVersion/php$phpVersion/$suite/$variant"
					dockerfilePath="$variantPath/Dockerfile"
					phpTag="$phpVersion-$variant-$suite"

					mkdir -p "$variantPath"
					touch "$dockerfilePath"
					echo "$variantPath"

					[ -d "$variantPath" ] || continue
					{ generated_warning; cat "$baseDockerfile"; } > "$dockerfilePath"

					echo "Generating $dockerfilePath from $baseDockerfile + $variant-Dockerfile-block-*"
					gawk -i inplace -v variant="$variant" '
						$1 == "##</autogenerated>##" { ia = 0 }
						!ia { print }
						$1 == "##<autogenerated>##" { ia = 1; ab++; ac = 0; if (system("test -f " variant "-Dockerfile-block-" ab) != 0) { ia = 0 } }
						ia { ac++ }
						ia && ac == 1 { system("cat " variant "-Dockerfile-block-" ab) }
					' "$dockerfilePath"

					# remove any _extra_ blank lines created by the deletions above
					gawk '
						NF > 0 { blank = 0 }
						NF == 0 { ++blank }
						blank < 2 { print }
					' "$dockerfilePath" > "$dockerfilePath.new"
					mv "$dockerfilePath.new" "$dockerfilePath"

					# select correct version for xdebug package
					phpXdebugPackage="xdebug"
					if [[ ${phpVersion} == "7.3" ]]; then
						phpXdebugPackage="xdebug-beta"
					elif [[ ${phpVersion%%.*} -eq "5" ]]; then
						phpXdebugPackage="xdebug-2.5.5"
					fi

					# select correct version for phpunit package
					phpunitVersion='8'
					if [[ ${phpVersion} == '5.6' ]]; then
						phpunitVersion='5'
					elif [[ ${phpVersion} == '7.0' ]]; then
						phpunitVersion='6'
					elif [[ ${phpVersion} == '7.1' ]]; then
						phpunitVersion='7'
					fi

					sed -ri \
						-e 's!%%PHP_TAG%%!'"$phpTag"'!' \
						-e 's!%%DEBIAN_SUITE%%!'"$suite"'!' \
						-e 's!%%ALPINE_VERSION%%!'"$alpineVer"'!' \
						-e 's!%%PHALCON_VERSION%%!'"$phalconVersion"'!' \
						-e 's!%%PHALCON_URL%%!'"$phalconUrl"'!' \
						-e 's!%%PHP_XDEBUG_PACKAGE%%!'"$phpXdebugPackage"'!' \
						-e 's!%%PHPUNIT_VERSION%%!'"$phpunitVersion"'!' \
						"$dockerfilePath"

					travisEnv='\n  - VERSION='"$majorVersion.$minorVersion VARIANT=php$phpVersion/$suite/$variant""$travisEnv"
				done;
			done
		done
	done;
done

travis="$(gawk -v 'RS=\n\n' '$1 == "env:" { $0 = "env:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml
