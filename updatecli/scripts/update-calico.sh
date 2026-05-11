#!/bin/bash
set -eu

source $(dirname $0)/create-issue.sh

ISSUE_TITLE="Updatecli failed for calico ${CALICO_VERSION}" 
trap report-error EXIT INT

if [ -n "$CALICO_VERSION" ]; then
	GOCACHE='/home/runner/.cache/go-build' GOPATH='/home/runner/go' PACKAGE='rke2-calico' make prepare
	GOCACHE='/home/runner/.cache/go-build' GOPATH='/home/runner/go' PACKAGE='rke2-calico-crd' make prepare
	current_calico_version=$(yq '.version' packages/rke2-calico-crd/charts/Chart.yaml)
	if [ "$current_calico_version" != "$CALICO_VERSION" ]; then
		echo "Updating Calico chart to $CALICO_VERSION"

		mkdir workdir
		wget -P workdir/ https://github.com/projectcalico/calico/releases/download/$CALICO_VERSION/tigera-operator-$CALICO_VERSION.tgz
		tar --directory=workdir -xf workdir/tigera-operator-$CALICO_VERSION.tgz tigera-operator/values.yaml
		current_tigera_operator_version=$(yq '.tigeraOperator.version' workdir/tigera-operator/values.yaml)
		rm -fr workdir

		yq -i ".version = \"$CALICO_VERSION\"" packages/rke2-calico/charts/Chart.yaml
		yq -i ".appVersion = \"$CALICO_VERSION\"" packages/rke2-calico/charts/Chart.yaml
		yq -i ".tigeraOperator.version = \"$current_tigera_operator_version\"" packages/rke2-calico/charts/values.yaml
		yq -i ".calicoctl.tag = \"$CALICO_VERSION\"" packages/rke2-calico/charts/values.yaml
		yq -i ".url = \"https://github.com/projectcalico/calico/releases/download/$CALICO_VERSION/tigera-operator-$CALICO_VERSION.tgz\" |
			.packageVersion = 00" packages/rke2-calico/package.yaml

		yq -i ".version = \"$CALICO_VERSION\"" packages/rke2-calico-crd/charts/Chart.yaml
		yq -i ".appVersion = \"$CALICO_VERSION\"" packages/rke2-calico-crd/charts/Chart.yaml
		yq -i ".url = \"https://github.com/projectcalico/calico/releases/download/$CALICO_VERSION/crd.projectcalico.org.v1-$CALICO_VERSION.tgz\" |
			.packageVersion = 00" packages/rke2-calico-crd/package.yaml

		find packages/rke2-calico/charts -name '*.orig' -delete
		find packages/rke2-calico-crd/charts -name '*.orig' -delete

		GOCACHE='/home/runner/.cache/go-build' GOPATH='/home/runner/go' PACKAGE='rke2-calico' make patch
		GOCACHE='/home/runner/.cache/go-build' GOPATH='/home/runner/go' PACKAGE='rke2-calico-crd' make patch
		make clean
	fi
fi
