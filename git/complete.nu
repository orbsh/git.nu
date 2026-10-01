use stat.nu *

export def cmpl-git-log [] {
    git log -n 32 --pretty=%h»¦«%s
    | lines
    | split column "»¦«" value description
    | { completions: $in, options: { sort: false, match_description: true } }
}

export def cmpl-git-log-all [] {
    git log --all -n 32 --pretty=%h»¦«%d»¦«%s
    | lines
    | split column "»¦«" value branch description
    | each {|x| $x | update description $"($x.branch) ($x.description)" }
    | { completions: $in, options: { sort: false, match_description: true } }
}

export def cmpl-git-branch-files [buffer: string] {
    let token = $buffer | split row ' '
    let branch = $token | get 1
    let files = $token | skip 2
    git ls-tree -r --name-only $branch
    | lines
    | where {|x| not ($x in $files)}
}

export def cmpl-git-branches [] {
    git-branches
}

export def cmpl-git-other-branches [] {
    let cur = git-current-branch
    git-branches | where $in != $cur
}

export def cmpl-git-remotes [] {
  ^git remote | lines | each { |line| $line | str trim }
}
