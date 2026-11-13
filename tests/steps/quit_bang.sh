R=$(q 'getcwd()'); echo b0 > $R/b.txt; echo c0 > $R/c.txt
F() { KS=0.05 "$@"; }
mods() { q "len(getbufinfo({'bufmodified':1}))"; }
nw() { q "winnr('\$')"; }
# (b)
F k Escape; F lit ':vs b.txt'; F k Enter; sleep 0.5
F lit 'ihello'; F k Escape; F lit ':q!'; F k Enter
sleep 0.3
expect "b: window closed" "$(nw)" "1"
expect "b: disk unchanged" "$(cat $R/b.txt)" "b0"
expect "b: nothing modified" "$(mods)" "0"
sleep 2.2
expect "b: disk unchanged 2s later" "$(cat $R/b.txt)" "b0"
expect "b: nothing modified later" "$(mods)" "0"
# (c)
F lit ':vs'; F k Enter; sleep 0.3
F lit 'A!'; F k Escape; F lit ':q!'; F k Enter
sleep 0.2
expect "c: one window left" "$(nw)" "1"
expect "c: text still shown" "$(q 'getline(1)')" "hello!"
F lit ':vs c.txt'; F k Enter; sleep 0.5
expect "c: saved after leaving" "$(cat $R/a.txt)" "hello!"
# (d)
F lit 'ix'; F k Escape; F lit ':q'; F k Enter
sleep 0.3
expect "d: window closed" "$(nw)" "1"
expect "d: :q saved" "$(cat $R/c.txt)" "xc0"
# (e)
F lit ':vs new.txt'; F k Enter; sleep 0.5
F lit 'itext'; F k Escape; F lit ':q!'; F k Enter
sleep 3
expect "e: no file" "$(ls $R/new.txt 2>&1 | grep -c 'No such')" "1"
expect "e: nothing modified" "$(mods)" "0"
check quit-bang
# (f)
echo f0 > $R/a.txt; q "execute('edit! a.txt')" >/dev/null
F k Escape; F lit 'ihello'; F k Escape; F lit ':q!'; F k Enter
sleep 2
expect "f: nvim gone" "$(t has-session -t $SES 2>&1 | grep -c .)" "1"
expect "f: disk unchanged" "$(cat $R/a.txt)" "f0"
