def 'precent' [] {
    ($in * 10000 | math round) / 100
}

def 'frequency' [-w: int] {
    let o = $in
    '' | fill -c '*' -w ($o * $w | math round)
}

def 'histogram-column' [column --len(-l):int = 50] {
    let o = $in
    let total = $o | get $column | math sum
    let max = $o | get $column | math max | $in / $total
    $o
    | each {|x|
        let c = $x | get $column | $in / $total
        $x
        | insert precent $"($c | precent)%"
        | insert frequency ($c / $max | frequency -w $len)
    }
}

def git_log [] {
    git log --pretty=%h»¦«%aN»¦«%s»¦«%aD
    | lines
    | split column "»¦«" sha1 committer desc merged_at
}

export def git-histogram-merger [] {
    git_log
    | group-by committer
    | items {|k, v| {committer: $k, count: ($v | length)} }
    | histogram-column count
}

def cmpl-author [] {
    git_log | group-by committer | columns
}

def cmpl-interval [] {
    [hour day month year]
}

export def git-histogram-activities [
    author:string@cmpl-author
    --interval(-i): string@cmpl-interval
    --builtin-histogram
] {
    let dfs = match $interval {
        'hour' => '%Y-%m-%d %H'
        'day' => '%Y-%m-%d'
        'month' => '%Y-%m'
        'year' => '%Y'
        _ => '%Y-%m-%d'
    }
    let d = git_log
    | group-by committer
    | get $author
    | get merged_at
    | into datetime
    | format date $dfs
    if $builtin_histogram {
        $d
        | histogram
        | rename date
        | sort-by date
    } else {
        $d
        | wrap date
        | sort-by date
        | group-by date
        | items {|k, v| {date: $k, count: ($v | length)} }
        | histogram-column count
    }

}
