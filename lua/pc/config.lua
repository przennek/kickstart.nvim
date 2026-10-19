-- NOTE:  For more options, you can see `:help option-list`

-- NOTE: Must happen before plugins are loaded (otherwise wrong leader will be used)
-- See `:help mapleader`
vim.g.mapleader = ' ' -- Set <space> as the leader key
vim.g.maplocalleader = ' '

-- white spaces
vim.opt.expandtab = true -- Convert tabs to spaces
vim.opt.shiftwidth = 4 -- Number of spaces to use for each step of (auto)indent
vim.opt.softtabstop = 4 -- Number of spaces that a <Tab> counts for while editing
vim.opt.tabstop = 4 -- Number of spaces that a <Tab> in the file counts for

vim.g.have_nerd_font = true

-- Java from SDKMAN for every tool started from Neovim (sonarlint, checkstyle, pmd, Maven in
-- terminals…), also when Neovim isn't started from a shell that ran sdkman-init
local sdkman_java = vim.fs.joinpath(vim.env.HOME, '.sdkman', 'candidates', 'java', 'current')
if vim.fn.executable 'java' == 0 and vim.uv.fs_stat(sdkman_java) then
  vim.env.JAVA_HOME = sdkman_java
  vim.env.PATH = sdkman_java .. '/bin:' .. vim.env.PATH
end

-- line numbers
-- Like .ideavimrc: relative numbers only (`set number` is commented out there)
vim.opt.number = false
vim.opt.relativenumber = true

-- Enable mouse mode, can be useful for resizing splits for example!
vim.opt.mouse = 'a'

-- Don't show the mode, since it's already in the status line
vim.opt.showmode = false

-- Sync clipboard between OS and Neovim.
--  Schedule the setting after `UiEnter` because it can increase startup-time.
--  Remove this option if you want your OS clipboard to remain independent.
--  See `:help 'clipboard'`
vim.schedule(function()
  vim.opt.clipboard = 'unnamedplus'
end)

-- Enable break indent
vim.opt.breakindent = true

-- Save undo history
vim.opt.undofile = true

-- Case-insensitive searching (use \C to match case); like .ideavimrc, no smartcase
vim.opt.ignorecase = true
vim.opt.smartcase = false

-- :s replaces all matches in a line by default (same as `set gdefault` in .ideavimrc)
vim.opt.gdefault = true

-- Back / Forward (Ctrl+O / Ctrl+I, Alt+H / Alt+L, Ctrl+Shift+P / N) behave like IDEA's
-- navigation history: jumping somewhere new after going back drops the "forward" part
vim.opt.jumpoptions = 'stack,view'

-- Keep signcolumn on by default
vim.opt.signcolumn = 'yes:2' -- two signs: git / diagnostics / breakpoints + hierarchy markers

-- Decrease update time
vim.opt.updatetime = 250

-- Decrease mapped sequence wait time
-- Displays which-key popup sooner
vim.opt.timeoutlen = 300

-- Configure how new splits should be opened
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Sets how neovim will display certain whitespace characters in the editor.
--  See `:help 'list'`
--  and `:help 'listchars'`
vim.opt.list = true
vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

-- Preview substitutions live, as you type!
vim.opt.inccommand = 'split'

-- Show which line your cursor is on
vim.opt.cursorline = true

-- Minimal number of screen lines to keep above and below the cursor.
vim.opt.scrolloff = 1 -- as in .ideavimrc

-- No soft wraps in the editor (IDEA: soft wraps only in the console)
vim.opt.wrap = false
