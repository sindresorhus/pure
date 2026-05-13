#!/usr/bin/env zsh

setopt clobber
set -euo pipefail

zmodload -F zsh/files b:zf_rm b:zf_mkdir

source "${0:A:h}/test-helper.zsh"

tmpdir="$PWD/.ai-temporary/git-dirty-test.$$"
zf_mkdir -p "$tmpdir"

cleanup() {
	zf_rm -rf -- "$tmpdir"
}
trap cleanup EXIT

setup_repo() {
	cd "$tmpdir"
	command git init -q
	command git config user.email "test@test.com"
	command git config user.name "Test"
	echo "initial" > file.txt
	command git add file.txt
	command git commit -q -m "initial"
}

check_dirty() {
	local dirty_output dirty_code
	dirty_output=$(prompt_pure_async_git_dirty "$@") && dirty_code=0 || dirty_code=$?
	typeset -g check_output=$dirty_output check_code=$dirty_code
}

setup_repo

# ── Default mode (no detailed flag) ──

# Clean repo.
check_dirty 1
assert_equal 0 $check_code "clean repo should return 0"
assert_empty "$check_output" "clean repo should have no output"

# Unstaged changes.
echo "modified" > file.txt
check_dirty 1
assert_equal 1 $check_code "dirty repo should return 1"
assert_empty "$check_output" "default mode should have no output"

# Staged changes.
command git add file.txt
check_dirty 1
assert_equal 1 $check_code "staged dirty should return 1"
assert_empty "$check_output" "default mode staged should have no output"

# Untracked files.
command git commit -q -m "second"
echo "untracked" > newfile.txt
check_dirty 1
assert_equal 1 $check_code "untracked dirty should return 1"
assert_empty "$check_output" "default mode untracked should have no output"

# PURE_GIT_UNTRACKED_DIRTY=0 ignores untracked.
check_dirty 0
assert_equal 0 $check_code "untracked with PURE_GIT_UNTRACKED_DIRTY=0 should be clean"
assert_empty "$check_output" "untracked with PURE_GIT_UNTRACKED_DIRTY=0 should have no output"
zf_rm -f newfile.txt

# PURE_GIT_UNTRACKED_DIRTY=0 still detects staged tracked changes.
echo "staged with ignored untracked" > file.txt
command git add file.txt
check_dirty 0
assert_equal 1 $check_code "staged with PURE_GIT_UNTRACKED_DIRTY=0 should return 1"
assert_empty "$check_output" "staged with PURE_GIT_UNTRACKED_DIRTY=0 should have no output"
command git commit -q -m "staged with ignored untracked"

# ── Detailed mode ──

# Clean repo.
check_dirty 1 1
assert_equal 0 $check_code "detailed: clean repo should return 0"
assert_empty "$check_output" "detailed: clean repo should have no output"

# Unstaged changes only.
echo "detailed-modified" > file.txt
check_dirty 1 1
assert_equal 1 $check_code "detailed: unstaged should return 1"
assert_equal "*" "$check_output" "detailed: unstaged only should show *"

# Staged changes only.
command git add file.txt
check_dirty 1 1
assert_equal 1 $check_code "detailed: staged should return 1"
assert_equal "+" "$check_output" "detailed: staged only should show +"

# Staged + intent-to-add.
echo "intent" > intent.txt
command git add -N intent.txt
check_dirty 1 1
assert_equal 1 $check_code "detailed: staged+intent-to-add should return 1"
assert_equal "*+" "$check_output" "detailed: staged+intent-to-add should show *+"
command git reset -q HEAD -- intent.txt
zf_rm -f intent.txt

# Staged + unstaged (same file).
echo "more changes" > file.txt
check_dirty 1 1
assert_equal 1 $check_code "detailed: staged+unstaged should return 1"
assert_equal "*+" "$check_output" "detailed: staged+unstaged should show *+"

# Untracked only (commit current changes first).
command git add file.txt
command git commit -q -m "third"
echo "new" > newfile.txt
check_dirty 1 1
assert_equal 1 $check_code "detailed: untracked should return 1"
assert_equal "?" "$check_output" "detailed: untracked only should show ?"

# All three: unstaged + staged + untracked.
echo "modified again" > file.txt
command git add file.txt
echo "even more" > file.txt
check_dirty 1 1
assert_equal 1 $check_code "detailed: all three should return 1"
assert_equal "*+?" "$check_output" "detailed: all three should show *+?"

# PURE_GIT_UNTRACKED_DIRTY=0 with only untracked files.
command git add file.txt
command git commit -q -m "fourth"
zf_rm -f newfile.txt
echo "untracked" > anotherfile.txt
check_dirty 0 1
assert_equal 0 $check_code "detailed: untracked with PURE_GIT_UNTRACKED_DIRTY=0 should be clean"
assert_empty "$check_output" "detailed: untracked with PURE_GIT_UNTRACKED_DIRTY=0 should have no output"

# PURE_GIT_UNTRACKED_DIRTY=0 with unstaged changes only.
echo "changed" > file.txt
check_dirty 0 1
assert_equal 1 $check_code "detailed: unstaged with PURE_GIT_UNTRACKED_DIRTY=0 should return 1"
assert_equal "*" "$check_output" "detailed: unstaged with PURE_GIT_UNTRACKED_DIRTY=0 should show *"

# PURE_GIT_UNTRACKED_DIRTY=0 with staged changes.
command git checkout -- file.txt
echo "staged" > staged.txt
command git add staged.txt
check_dirty 0 1
assert_equal 1 $check_code "detailed: staged with PURE_GIT_UNTRACKED_DIRTY=0 should return 1"
assert_equal "+" "$check_output" "detailed: staged with PURE_GIT_UNTRACKED_DIRTY=0 should show +"

# Deleted file (unstaged).
command git commit -q --allow-empty -m "prep"
command git checkout -- file.txt 2>/dev/null || true
zf_rm -f anotherfile.txt staged.txt
command git add -A
command git commit -q -m "clean slate"
echo "to delete" > deleteme.txt
command git add deleteme.txt
command git commit -q -m "add deleteme"
zf_rm -f deleteme.txt
check_dirty 1 1
assert_equal 1 $check_code "detailed: deleted unstaged should return 1"
assert_equal "*" "$check_output" "detailed: deleted unstaged should show *"

# Deleted file (staged).
command git rm -q deleteme.txt
check_dirty 1 1
assert_equal 1 $check_code "detailed: deleted staged should return 1"
assert_equal "+" "$check_output" "detailed: deleted staged should show +"

# Renamed file (staged).
command git reset -q HEAD -- deleteme.txt
command git checkout -- deleteme.txt 2>/dev/null || true
echo "to rename" > renameme.txt
command git add renameme.txt
command git commit -q -m "add renameme"
command git mv renameme.txt renamed.txt
check_dirty 1 1
assert_equal 1 $check_code "detailed: renamed staged should return 1"
assert_equal "+" "$check_output" "detailed: renamed staged should show +"

print "git-dirty tests passed"
