use stat.nu *

export def git-init [remote] {
    git init --initial-branch main
    git add .
    git commit -m 'init'
    git remote add origin $remote
}

export def git-is-repo [] {
    (git rev-parse --is-inside-work-tree | complete).exit_code == 0
}

export def git-commit-changes [commit:string] {
    git diff-tree --no-commit-id --name-only -r $commit | lines
}

export def git-last-changes [] {
    let d = git log -n 9 --pretty=%h»¦«%s | lines | split column '»¦«' hash message
    for i in $d {
        let r = git-commit-changes $i.hash
        if ($r | is-not-empty) {
            return $r
        }
    }
    []
}

export def git-changes [] {
    do -i { git --no-optional-locks status --porcelain=1 | lines }
}

# Status overview of a batch of repos: uncommitted change count + ahead/behind vs upstream.
# Directory args are variadic (default: current dir); dirs that are not repos are listed too, with state=not-a-repo.
# ahead/behind are relative to the last fetch; add --fetch (network, one per repo) for accurate numbers.
export def git-repos-status [
    ...dirs:path
    --fetch (-f)   # fetch once per repo first
    --nested (-n)  # when a dir is not itself a repo, look one level down for its child dirs
] {
    let roots = if ($dirs | is-empty) { [$env.PWD] } else { $dirs }
    mut out = []
    for p in ($roots | each {|d| $d | path expand }) {
        let is_dir = ((do -i { $p | path type }) | default '') == 'dir'
        if not $is_dir {
            $out = $out | append { path: $p branch: null dirty: null ahead: null behind: null state: 'not-a-repo' }
            continue
        }
        cd $p
        if (git-is-repo) {
            $out = $out | append (git-repo-status-row $p $fetch)
            continue
        }
        if not $nested {
            $out = $out | append { path: $p branch: null dirty: null ahead: null behind: null state: 'not-a-repo' }
            continue
        }
        for c in (ls --all $p | where type == dir | get name) {
            let n = $c | path basename
            if ($n | str starts-with '.') or ($n in ['target' 'node_modules']) { continue }
            cd $c
            if (git-is-repo) {
                $out = $out | append (git-repo-status-row $c $fetch)
            }
        }
    }
    $out
}

# One row per repo (row factory for git-repos-status; parsing reuses _git_status from stat.nu)
def git-repo-status-row [p: path, do_fetch: bool] {
    cd $p
    let has_remote = do -i { git remote } | default [] | is-not-empty
    let fetch_code = if $do_fetch and $has_remote {
        (git fetch origin --quiet | complete).exit_code
    } else {
        0
    }
    let s = _git_status
    let upstream = $s.remote
    let commit = $s.commit_hash? | default ''
    {
        path:   $p
        branch: $s.branch
        dirty:  ([
            $s.idx_added_staged $s.idx_modified_staged $s.idx_deleted_staged
            $s.idx_renamed $s.idx_type_changed
            $s.wt_modified $s.wt_deleted $s.wt_renamed $s.wt_type_changed
            $s.wt_untracked $s.conflicts
        ] | math sum)
        ahead:  (if ($upstream | is-empty) { null } else { $s.ahead })
        behind: (if ($upstream | is-empty) { null } else { $s.behind })
        state:  (if ($commit | str starts-with '(') { 'no-commits' }
            else if ($s.branch == '(detached)') { 'detached' }
            else if (not $has_remote) { 'no-remote' }
            else if ($upstream | is-empty) { 'no-upstream' }
            else if ($fetch_code != 0) { 'fetch-failed' }
            else { '' })
    }
}

export def git-last-commit [] {
    let d = git log -n 9 --pretty=»»¦««%h»¦«%s»¦«%b
    | split row '»»¦««' | slice 1..
    | split column '»¦«' hash message body
    for i in $d {
        if (git-commit-changes $i.hash | is-not-empty) {
            return $i
        }
    }
}

export def git-cdup [] {
    let r = git rev-parse --show-cdup | complete
    if $r.exit_code == 0 {
        $r.stdout | str trim
    }
}

export def git-repo-path [] {
    let c = git-cdup
    if ($c | describe) == nothing { return }
    [$env.PWD (git-cdup)] | path join | path expand
}

export def git-sync [
    src dest
    --no-file
    --push
    --init: string
    --post-sync: closure
    --init-post-sync: closure
    --trans-msg: closure
] {
    let src = $src | path expand
    cd $src
    let l = git-last-commit
    let msg = if ($trans_msg | is-empty) {
        $"($l.message)\n\n($l.body)"
    } else {
        do $trans_msg $l
    }
    let dest = $dest | path expand
    if not ($dest | path exists) { mkdir $dest }
    cd $dest
    if not $no_file {
        rsync -a --delete --exclude='.git' $'($src)/' $dest
        if ($post_sync | is-not-empty) and (git-is-repo) {
            do $post_sync $src $dest $l
        }
        if ($init_post_sync | is-not-empty) {
            do $init_post_sync $src $dest $l
        }
    }
    if ($init | is-not-empty) and not (git-is-repo) {
        git init .
        git remote add origin $init
        git add .
        git commit -m $msg
        if $push {
            git push --set-upstream origin main
        }
    }
    if (git-changes | is-not-empty) {
        git add .
        git commit -m $msg
        if $push {
            git push
        }
    }
}

export def git-garbage-collect [] {
    git reflog expire --all --expire=now
    git gc --aggressive --prune=now
}

export def git-truncate-history [
    retain:int=10
    --message:string="Truncate history"
] {
    let h = git log --pretty=%H --reverse -n $retain | lines | first
    let s = _git_status
    git checkout -f --orphan temp $h
    git add .
    git commit -m $message
    git rebase --onto temp $h $s.branch
}

export def git-squash-last [
    num:int
] {
    let l = git log  --pretty=»»¦««%s»¦«%b -n $num
    | split row '»»¦««' | slice 1..
    | split column '»¦«' message body
    | each { $"($in.message)\n\n($in.body)" }
    | str join "\n===\n"
    git reset --soft $"HEAD~($num)"
    git commit --edit -m $l
}

export def git-purge-history [] {
    let wd = mktemp -d
    let paths = $wd | path join paths.txt
    git ls-files | save $paths
    cp .git/config $wd
    git filter-repo --paths-from-file $paths --prune-empty always --force
    mv ($wd | path join config) .git/config
    rm -rf $wd
}
