#!/bin/bash

# git_stats.sh
# Mostra estadístiques de Git per autor, per tipus de fitxer, i resum general

function check_git_repo() {
    if ! git rev-parse --is-inside-work-tree &> /dev/null; then
        echo "Aquest directori no és un repositori Git."
        exit 1
    fi
}

function collect_stats() {
    git log --all --pretty=format:'%an' --numstat | awk '
    NF == 1 {
        author = $1
    }
    NF == 3 {
        added[author] += $1
        removed[author] += $2
        commits[author]++
        total_added += $1
        total_removed += $2
        total_commits++
    }
    END {
        for (a in commits) {
            printf "%s|%d|%d|%d\n", a, commits[a], added[a], removed[a]
        }
        printf "__TOTALS__|%d|%d|%d\n", total_commits, total_added, total_removed
    }'
}

function collect_merges() {
    git log --all --merges --pretty=format:'%an' | sort | uniq -c | awk '
    {
        merges[$2] = $1
        total += $1
    }
    END {
        for (a in merges) {
            printf "%s|%d\n", a, merges[a]
        }
        printf "__TOTALS__|%d\n", total
    }'
}

function generate_author_stats() {
    declare -A commits added removed merges
    total_commits=0
    total_added=0
    total_removed=0
    total_merges=0

    while IFS='|' read -r author c a r; do
        if [[ "$author" == "__TOTALS__" ]]; then
            total_commits=$c
            total_added=$a
            total_removed=$r
        else
            commits["$author"]=$c
            added["$author"]=$a
            removed["$author"]=$r
        fi
    done < <(collect_stats)

    while IFS='|' read -r author m; do
        if [[ "$author" == "__TOTALS__" ]]; then
            total_merges=$m
        else
            merges["$author"]=$m
        fi
    done < <(collect_merges)

    printf "%-25s %10s %15s %15s %15s %15s\n" \
        "Autor" "Commits" "Afegides" "Tretas" "Merges" "Total"

    for author in "${!commits[@]}"; do
        [[ "$author" == "github-classroom[bot]" ]] && continue

        c=${commits[$author]}
        a=${added[$author]}
        r=${removed[$author]}
        m=${merges[$author]:-0}

        c_pct=$(awk -v x=$c -v t=$total_commits 'BEGIN { if (t==0) printf "0.0%%"; else printf "%.1f%%", (x/t)*100 }')
        a_pct=$(awk -v x=$a -v t=$total_added   'BEGIN { if (t==0) printf "0.0%%"; else printf "%.1f%%", (x/t)*100 }')
        r_pct=$(awk -v x=$r -v t=$total_removed 'BEGIN { if (t==0) printf "0.0%%"; else printf "%.1f%%", (x/t)*100 }')
        m_pct=$(awk -v x=$m -v t=$total_merges  'BEGIN { if (t==0) printf "0.0%%"; else printf "%.1f%%", (x/t)*100 }')

        total_pct=$(awk -v x=$c -v a=$a -v r=$r -v m=$m \
                          -v tc=$total_commits -v ta=$total_added -v tr=$total_removed -v tm=$total_merges \
                          'BEGIN {
                              sum = x + a + r + m
                              tsum = tc + ta + tr + tm
                              if (tsum == 0) printf "0.0%%"; else printf "%.1f%%", (sum / tsum) * 100
                          }')

        printf "%-25s %7d (%6s) %10d (%6s) %10d (%6s) %7d (%6s) %8s\n" \
            "$author" \
            "$c" "$c_pct" \
            "$a" "$a_pct" \
            "$r" "$r_pct" \
            "$m" "$m_pct" \
            "$total_pct"
    done | sort -k2 -nr
}

function generate_extension_summary_with_top_author() {
    echo
    echo "Extensió de fitxers + autor que ha afegit més línies:"
    echo

    # Primer preparem estadístiques de fitxers i extensions
    declare -A file_count total_lines top_author
    total_files=0

    # Comptar fitxers per extensió
    while read -r file; do
        filename=$(basename "$file")
        if [[ "$filename" == *.* ]]; then
            ext="${filename##*.}"
        else
            ext="[sense extensió]"
        fi
        ((file_count["$ext"]++))
        ((total_files++))
    done < <(git ls-files)

    # Comptar línies afegides per autor i extensió
    git log --all --numstat --pretty=format:"%an" | awk '
    function get_ext(filename) {
        if (filename ~ /\./) {
            return gensub(/^.*\.([^.\/]+)$/, "\\1", "g", filename)
        } else {
            return "[sense extensió]"
        }
    }

    NF == 1 {
        author = $1
        next
    }

    NF == 3 {
        added = $1
        file = $3
        if (added ~ /^[0-9]+$/ && author != "github-classroom[bot]") {
            ext = get_ext(file)
            key = ext "|" author
            added_lines[key] += added
            if (added_lines[key] > max[ext]) {
                max[ext] = added_lines[key]
                top_author[ext] = author
            }
        }
    }

    END {
        for (e in top_author) {
            printf "%s|%s\n", e, top_author[e]
        }
    }' > /tmp/top_authors.tmp

    # Mostrar resultat final
    printf "%-20s %10s %12s   %s\n" "Extensió" "Fitxers" "Percentatge" "Autor top"
    while IFS= read -r ext; do
        count=${file_count["$ext"]}
        pct=$(awk -v x=$count -v t=$total_files 'BEGIN { printf "%.1f%%", (x/t)*100 }')
        author=$(grep "^$ext|" /tmp/top_authors.tmp | cut -d'|' -f2)
        printf "%-20s %10d %12s   %s\n" "$ext" "$count" "$pct" "$author"
    done < <(printf "%s\n" "${!file_count[@]}" | sort -k1)
}

function generate_extension_summary_with_top_author() {
    echo
    echo "Extensió de fitxers + autor que ha afegit més línies + línies totals:"
    echo

    declare -A file_count loc_count
    total_files=0

    # Comptar fitxers i LOC per extensió
    while read -r file; do
        filename=$(basename "$file")
        if [[ "$filename" == *.* ]]; then
            ext="${filename##*.}"
        else
            ext="[sense extensió]"
        fi
        ((file_count["$ext"]++))
        ((total_files++))

        # Sumar LOC si és fitxer de text
        if [[ -f "$file" && -r "$file" ]]; then
            lines=$(wc -l < "$file" 2>/dev/null)
            [[ "$lines" =~ ^[0-9]+$ ]] && ((loc_count["$ext"] += lines))
        fi
    done < <(git ls-files)

    # Comptar línies afegides per autor i extensió
    git log --all --numstat --pretty=format:"%an" | awk '
    function get_ext(filename) {
        if (filename ~ /\./) {
            return gensub(/^.*\.([^.\/]+)$/, "\\1", "g", filename)
        } else {
            return "[sense extensió]"
        }
    }

    NF == 1 {
        author = $1
        next
    }

    NF == 3 {
        added = $1
        file = $3
        if (added ~ /^[0-9]+$/ && author != "github-classroom[bot]") {
            ext = get_ext(file)
            key = ext "|" author
            added_lines[key] += added
            if (added_lines[key] > max[ext]) {
                max[ext] = added_lines[key]
                top_author[ext] = author
            }
        }
    }

    END {
        for (e in top_author) {
            printf "%s|%s\n", e, top_author[e]
        }
    }' > /tmp/top_authors.tmp

    # Construir sortida temporal per ordenar
    > /tmp/ext_summary.tmp
    for ext in "${!file_count[@]}"; do
        count=${file_count["$ext"]}
        loc=${loc_count["$ext"]:-0}
        pct=$(awk -v x=$count -v t=$total_files 'BEGIN { printf "%.1f%%", (x/t)*100 }')
        author=$(grep "^$ext|" /tmp/top_authors.tmp | cut -d'|' -f2)
        printf "%s|%d|%s|%s|%d\n" "$ext" "$count" "$pct" "$author" "$loc" >> /tmp/ext_summary.tmp
    done

    # Mostrar capçalera i dades ordenades per nombre de fitxers
    printf "%-20s %10s %12s   %-25s %10s\n" "Extensió" "Fitxers" "Percentatge" "Autor top" "LOC"
    sort -t'|' -k2,2nr /tmp/ext_summary.tmp | while IFS='|' read -r ext count pct author loc; do
        printf "%-20s %10d %12s   %-25s %10d\n" "$ext" "$count" "$pct" "$author" "$loc"
    done
}




function main() {
    check_git_repo
    echo "Generant estadístiques de Git..."
    echo

    generate_author_stats
    generate_extension_summary_with_top_author

    # generate_file_extension_stats
    # generate_top_authors_per_extension
}

main "$@"
