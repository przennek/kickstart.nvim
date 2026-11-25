# The log (2026-11-24 16:40): an agent removed a file open in the background; then
# "E211: File … no longer available". Like IDEA's tab: an unchanged file deleted on disk is
# closed (the windows stay), one with your edits stays with a warning; a tool that saves
# through delete + write does not close it; a file changed on disk still reloads.
R=$(q 'getcwd()'); printf 'b0\n' > $R/b.txt; printf 'c0\n' > $R/c.txt; printf 'd0\n' > $R/d.txt
listed() { q "buflisted(bufnr('$1'))"; }
# (a) background file deleted
ex 'e b.txt'; sleep 0.5; ex 'e a.txt'; sleep 0.5
rm $R/b.txt; sleep 1.5
expect "a: deleted background file closed" "$(listed b.txt)" "0"
expect "a: no E211" "$(q "execute('messages')" | grep -c E211)" "0"
ex 'e b.txt'; sleep 0.8
expect "a: opening it again: new file, no E211" "$(q "execute('messages')" | grep -c E211)" "0"
ex 'e a.txt'; sleep 0.3
# (b) the file in the window deleted: window stays, shows another file
ex 'e c.txt'; sleep 0.5
rm $R/c.txt; sleep 1.5
expect "b: window still there" "$(q "winnr('\$')")" "1"
expect "b: c.txt closed" "$(listed c.txt)" "0"
expect "b: window shows another file" "$(q 'expand("%:t")')" "a.txt"
# (c) modified buffer: stays, warning, :w writes it back
ex 'e d.txt'; sleep 0.5; lit 'Ax'; k Escape
rm $R/d.txt; sleep 1.5
expect "c: modified buffer kept" "$(listed d.txt)" "1"
expect "c: text kept" "$(q 'getline(1)')" "d0x"
ex 'w'; sleep 0.5
expect "c: :w wrote it back" "$(cat $R/d.txt)" "d0x"
# (d) delete + write by a tool, quickly: stays open, reloaded
rm $R/d.txt; printf 'd1\n' > $R/d.txt; sleep 1.5
expect "d: still open" "$(listed d.txt)" "1"
expect "d: reloaded" "$(q 'getline(1)')" "d1"
# (e) changed on disk: reloaded as before
printf 'd2\n' > $R/d.txt; sleep 1.5; esc '\e[I'; sleep 0.5
expect "e: change reloaded" "$(q 'getline(1)')" "d2"
check deleted-on-disk
