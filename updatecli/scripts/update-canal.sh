#!/bin/bash
set -eu

source $(dirname $0)/create-issue.sh

ISSUE_TITLE="Updatecli failed for canal ${CALICO_VERSION} / ${FLANNEL_VERSION}"
trap report-error EXIT INT

if [ -n "$FLANNEL_VERSION" ]; then
	current_flannel_version=$(yq '.flannel.image.tag' packages/rke2-canal/charts/values.yaml)
	if [ "$current_flannel_version" != "$FLANNEL_VERSION" ]; then
		echo "Updating flannel image to $FLANNEL_VERSION"
		yq -i ".flannel.image.tag = \"$FLANNEL_VERSION\"" packages/rke2-canal/charts/values.yaml
		package_version=$(yq '.packageVersion' packages/rke2-canal/package.yaml)
		new_version=$(printf "%02d" $((10#$package_version + 1)))
		sed -i "s/packageVersion:.*/packageVersion: $new_version/g" packages/rke2-canal/package.yaml
	fi
fi
if [ -n "$CALICO_VERSION" ]; then
	# CALICO_VERSION is the rancher image-build tag, e.g. v3.32.0-build20260511
	# The upstream projectcalico/calico release is just the semver, e.g. v3.32.0
	app_version=$(echo "$CALICO_VERSION" | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+')

	workdir=$(mktemp -d)
	crd_url="https://github.com/projectcalico/calico/releases/download/$app_version/crd.projectcalico.org.v1-$app_version.tgz"
	crd_tarball="$workdir/crd.projectcalico.org.v1-$app_version.tgz"

	echo "Downloading Calico CRDs from $crd_url"
	if ! wget --tries=3 --timeout=30 -O "$crd_tarball" "$crd_url"; then
		echo "ERROR: Failed to download Calico CRD tarball from $crd_url" >&2
		rm -rf "$workdir"
		exit 1
	fi
	tar --directory="$workdir" -xf "$crd_tarball"

	crd_src_dir="$workdir/crd.projectcalico.org.v1/templates/calico"
	crd_dst_dir="packages/rke2-canal/charts/templates/crds"

	# Sanity-check the extracted source before touching the destination.
	# `[ -d ]` follows symlinks, so a dangling symlink (as shipped in the
	# v3.32.0+ chart, where templates/calico -> ../../../libcalico-go/config/crd)
	# correctly fails this test.
	shopt -s nullglob
	src_yaml_files=( "$crd_src_dir"/*.yaml )
	shopt -u nullglob
	if [ ! -d "$crd_src_dir" ] || [ "${#src_yaml_files[@]}" -eq 0 ]; then
		echo "ERROR: Calico CRD source '$crd_src_dir' is missing, not a directory, or contains no .yaml files." >&2
		echo "       The upstream chart layout for $app_version may have changed; refusing to wipe $crd_dst_dir." >&2
		rm -rf "$workdir"
		exit 1
	fi

	needs_crd_update=false
	if ! diff -rq "$crd_src_dir/" "$crd_dst_dir/" > /dev/null 2>&1; then
		rm -f "$crd_dst_dir"/*.yaml
		cp "${src_yaml_files[@]}" "$crd_dst_dir"/
		needs_crd_update=true
	fi
	rm -rf "$workdir"

	current_calico_version=$(yq '.calico.cniImage.tag' packages/rke2-canal/charts/values.yaml)
	if [ "$current_calico_version" != "$CALICO_VERSION" ]; then
		echo "Updating calico image to $CALICO_VERSION"
		yq -i ".calico.cniImage.tag = \"$CALICO_VERSION\" |
			.calico.flexvolImage.tag = \"$CALICO_VERSION\" |
			.calico.nodeImage.tag = \"$CALICO_VERSION\" |
			.calico.kubeControllerImage.tag = \"$CALICO_VERSION\"" packages/rke2-canal/charts/values.yaml
		yq -i ".version = \"$CALICO_VERSION\" |
			.appVersion = \"$app_version\"" packages/rke2-canal/charts/Chart.yaml
		sed -i "s/packageVersion:.*/packageVersion: 00/g" packages/rke2-canal/package.yaml
	elif [ "$needs_crd_update" = "true" ]; then
		package_version=$(yq '.packageVersion' packages/rke2-canal/package.yaml)
		new_version=$(printf "%02d" $((10#$package_version + 1)))
		sed -i "s/packageVersion:.*/packageVersion: $new_version/g" packages/rke2-canal/package.yaml
	fi
fi
