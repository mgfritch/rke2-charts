#!/usr/bin/env bash

BODY="Failed workflow run: ${UPDATECLI_GITHUB_WORKFLOW_URL}"

GITHUB_APP="rancher-issues-manager"
TARGET_REPOSITORY="rancher/rke2"

report-error() {
    exit_code=$?
    trap - EXIT INT

    if [[ $exit_code != 0 ]]; then
        #check if issue already exists
        issue=$(
            gh issue list
                -R ${TARGET_REPOSITORY} \
                --app ${GITHUB_APP} \
                --search "is:open ${ISSUE_TITLE}" \
                --json number --jq ".[].number" | sort -run | head -1
        )

        if [[ -z "$issue" ]]; then
            echo "Creating issue for: '${ISSUE_TITLE}'"
            gh issue create
                -R ${TARGET_REPOSITORY} \
                --title "${ISSUE_TITLE}" \
                --body "${BODY}"
        else
            echo "Issue $issue already exists for: '${ISSUE_TITLE}'"
            gh issue comment ${issue} \
                -R ${TARGET_REPOSITORY} \
                --body "${BODY}"
        fi
    fi

    exit $exit_code
}

export -f report-error
