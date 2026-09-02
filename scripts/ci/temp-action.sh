#!/usr/bin/env bash
set -euo pipefail

# Unified one-shot CI action slot.
#
# Rules:
# - Do not rename this file.
# - Do not create a new temporary workflow.
# - Put one-shot logic only between TEMP ACTION BEGIN/END.
# - The shared workflow restores this file from the default branch before it
#   commits generated changes, so task-specific logic does not survive as the
#   branch's final state.
# - Use TEMP_ACTION_TYPE, TEMP_ACTION_PURPOSE, and TEMP_ACTION_TARGET_BRANCH for
#   metadata only; behavior belongs in the task body below.

printf 'Temporary action: %s · %s · %s\n' \
  "${TEMP_ACTION_TYPE:-unspecified}" \
  "${TEMP_ACTION_PURPOSE:-unspecified}" \
  "${TEMP_ACTION_TARGET_BRANCH:-unspecified}"

# TEMP ACTION BEGIN
# Replace this block for the current one-shot task. Keep this baseline as a
# deliberate no-op so an accidental dispatch cannot mutate the repository.
echo 'No temporary action is configured; nothing to do.'
# TEMP ACTION END
