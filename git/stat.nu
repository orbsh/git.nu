# git status
export def gs [] {
    git status
}

export def git-top-level [] {
    git rev-parse --show-toplevel
}

export def git-current-branch [] {
    git branch --show-current
}

# List local branches reliably (pure names, no decorators)
export def git-branches [] {
    git branch --format '%(refname:short)' | lines
}

export def _git_status [] {
    # TODO: show-stash
    let raw_status = do -i { git --no-optional-locks status --porcelain=2 --branch | lines }

    let stashes = do -i { git stash list | lines | length }

    mut status = {
        idx_added_staged    : 0
        idx_modified_staged : 0
        idx_deleted_staged  : 0
        idx_renamed         : 0
        idx_type_changed    : 0
        wt_untracked        : 0
        wt_modified         : 0
        wt_deleted          : 0
        wt_type_changed     : 0
        wt_renamed          : 0
        ignored             : 0
        conflicts           : 0
        ahead               : 0
        behind              : 0
        stashes             : $stashes
        repo_name           : no_repository
        tag                 : no_tag
        branch              : no_branch
        remote              : ''
    }

    if ($raw_status | is-empty) { return $status }

    for s in $raw_status {
        let r = $s | split row ' '
        match $r.0 {
            '#' => {
                match ($r.1 | str substring 7..) {
                    'oid' => {
                        $status.commit_hash = $r.2 | str substring 0..<8
                    }
                    'head' => {
                        $status.branch = $r.2
                    }
                    'upstream' => {
                        $status.remote = $r.2
                    }
                    'ab' => {
                        $status.ahead = $r.2 | into int
                        $status.behind = $r.3 | into int | math abs
                    }
                }
            }
            '1'|'2' => {
                match ($r.1 | str substring 0..<1) {
                    'A' => {
                        $status.idx_added_staged += 1
                    }
                    'M' => {
                        $status.idx_modified_staged += 1
                    }
                    'R' => {
                        $status.idx_renamed += 1
                    }
                    'D' => {
                        $status.idx_deleted_staged += 1
                    }
                    'T' => {
                        $status.idx_type_changed += 1
                    }
                }
                match ($r.1 | str substring 1..<2) {
                    'M' => {
                        $status.wt_modified += 1
                    }
                    'R' => {
                        $status.wt_renamed += 1
                    }
                    'D' => {
                        $status.wt_deleted += 1
                    }
                    'T' => {
                        $status.wt_type_changed += 1
                    }
                }
            }
            '?' => {
                $status.wt_untracked += 1
            }
            'u' => {
                $status.conflicts += 1
            }
        }
    }

    $status
}

def git-parse-stat [o: list<string>] {
    mut r = { file:0, ins:0, del:0, change:[] }
    for i in $o {
        if ($i | is-empty) { continue }
        if ($i | find -r '[0-9]+ file.+change' | is-not-empty) {
            for j in ($i
                | split row ','
                | each {|x| $x | str trim | parse -r "(?<num>[0-9]+) (?<col>.+)" | first }
            ) {
                let col = if ($j.col | str starts-with 'file') {
                        'file'
                    } else {
                        $j.col | str substring ..<3
                    }
                let num = $j.num | into int
                $r = $r | upsert $col $num
            }
        } else {
            $r.change ++= [ ($i | split row '|' | first | str trim) ]
        }
    }
    $r
}

export def _git_log [
    --num(-n):int = 9
    --reverse(-r)
    --verbose(-v)
] {
    let s = $"»(random chars -l 4)«"
    let S = $"»(random chars -l 6)«"
    let p = $"($S)($s)%h($s)%s($s)%aN($s)%aE($s)%aD($s)%D($s)%b"
    mut a = [-n $num $"--pretty=($p)"]
    if $reverse { $a ++= [--reverse] }
    if $verbose { $a ++= [--stat] }
    git log ...$a
    | split row $S | slice 1..
    | append $s
    | reduce -f {c: { payload: [] }, r: [] } {|it, acc|
        if ($it | str starts-with $s) {
            let c = if $verbose {
                $acc.c | merge (git-parse-stat $acc.c.payload)
            } else {
                $acc.c
            }
            | reject payload

            $acc
            | upsert r ($acc.r | append $c)
            | update c (
                $it
                | split column $s _ sha message author email date refs body
                | first
                | reject _
                | insert payload []
            )
        } else {
            $acc | update c.payload {|x| $x.c.payload | append $it }
        }
    }
    | get r | slice 1..
    | each {|x|
        let refs = if ($x.refs | is-empty) {
            $x.refs
        } else {
            $x.refs | split row ", "
        }
        $x
        | update date { $x.date | into datetime }
        | update refs $refs
    }
}

export def remote_branches [] {
    git branch -r
    | lines
    | str trim
    | where {|x| not ($x | str starts-with 'origin/HEAD') }
}

export def git_main_branch [] {
    git remote show origin
    | lines
    | str trim
    | find --regex 'HEAD .*?[：: ].+'
    | first
    | str replace --regex 'HEAD .*?[：: ](.+)' '$1'
}
