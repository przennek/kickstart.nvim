-- Locations in console / terminal output (Enter opens them): javac / Maven, gcc-style,
-- Python tracebacks, Java stack traces. Run in the Java fixture. Prints OK / FAIL and quits.
local cl = require 'pc.console_links'
local W = vim.fn.getcwd()
local cases = {
  { '[ERROR] ' .. W .. '/src/main/java/example/shop/App.java:[9,28] cannot find symbol', 'App.java:9:28' },
  { 'src/main/java/example/shop/App.java:8:5: error: x', 'App.java:8:5' },
  { '  File "src/main/java/example/shop/App.java", line 3, in <module>', 'App.java:3:1' },
  { '\tat example.shop.OrderService.loyaltyDiscount(OrderService.java:15)', 'OrderService.java:15:1' },
  { 'BUILD SUCCESS', 'nil' },
  { 'see missing/File.java:3:1', 'nil' },
}
local bad = {}
for i, c in ipairs(cases) do
  local loc = cl.parse(c[1], W)
  local got = loc and (vim.fs.basename(loc[1]) .. ':' .. loc[2] .. ':' .. loc[3]) or 'nil'
  if got ~= c[2] then
    table.insert(bad, ('%d: got %s, wanted %s'):format(i, got, c[2]))
  end
end
io.stdout:write((#bad == 0 and 'OK console links' or ('FAIL console links: ' .. table.concat(bad, '; '))) .. '\n')
vim.cmd 'qa!'
