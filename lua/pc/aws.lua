-- AWS connection, like the AWS Toolkit's credentials / region switcher:
--   <leader>A   menu: switch profile, switch region, SSO login / logout, who am I,
--               configure a new SSO profile (aws configure sso)
-- The choice sets AWS_PROFILE / AWS_REGION for everything started from Neovim (terminals,
-- Terraform, run configurations), shows in the status line and is remembered between sessions.
-- Terminals that were already open keep their old environment.

local M = {}

local STATE = vim.fn.stdpath 'data' .. '/aws.json'
local REGIONS = {
  'us-east-1', 'us-east-2', 'us-west-1', 'us-west-2',
  'eu-central-1', 'eu-west-1', 'eu-west-2', 'eu-north-1',
  'ap-southeast-1', 'ap-northeast-1',
}

local function save()
  local f = io.open(STATE, 'w')
  if f then
    f:write(vim.json.encode { profile = vim.env.AWS_PROFILE, region = vim.env.AWS_REGION })
    f:close()
  end
end

local function restore()
  local f = io.open(STATE)
  if not f then
    return
  end
  local ok, s = pcall(vim.json.decode, f:read '*a')
  f:close()
  if ok and type(s) == 'table' then
    vim.env.AWS_PROFILE = vim.env.AWS_PROFILE or s.profile
    vim.env.AWS_REGION = vim.env.AWS_REGION or s.region
  end
end

local function aws(args)
  return vim.system(vim.list_extend({ 'aws' }, args), { text = true, timeout = 20000 }):wait()
end

-- Commands that need a browser or a prompt run in the terminal window
local function in_terminal(cmd)
  require('toggleterm').exec(cmd, 8)
end

function M.status()
  local profile = vim.env.AWS_PROFILE
  if not profile or profile == '' then
    return ''
  end
  return ' ' .. profile .. (vim.env.AWS_REGION and (' ' .. vim.env.AWS_REGION) or '')
end

function M.switch_profile()
  local out = aws { 'configure', 'list-profiles' }
  local profiles = vim.split(vim.trim(out.stdout or ''), '\n', { trimempty = true })
  table.insert(profiles, 1, '(none)')
  vim.ui.select(profiles, { prompt = 'AWS profile' }, function(p)
    if not p then
      return
    end
    vim.env.AWS_PROFILE = p ~= '(none)' and p or nil
    if vim.env.AWS_PROFILE then
      local region = vim.trim(aws({ 'configure', 'get', 'region', '--profile', p }).stdout or '')
      if region ~= '' then
        vim.env.AWS_REGION = region
      end
    end
    save()
    vim.cmd.redrawstatus()
  end)
end

function M.switch_region()
  vim.ui.select(REGIONS, { prompt = 'AWS region' }, function(r)
    if r then
      vim.env.AWS_REGION = r
      save()
      vim.cmd.redrawstatus()
    end
  end)
end

function M.whoami()
  local out = aws { 'sts', 'get-caller-identity', '--output', 'json' }
  if out.code == 0 then
    local id = vim.json.decode(out.stdout)
    vim.notify(('Account %s\n%s'):format(id.Account, id.Arn))
  else
    vim.notify(vim.trim(out.stderr), vim.log.levels.WARN)
  end
end

function M.menu()
  local profile = vim.env.AWS_PROFILE or '(none)'
  local items = {
    { label = 'Profile: ' .. profile, run = M.switch_profile },
    { label = 'Region: ' .. (vim.env.AWS_REGION or '(default)'), run = M.switch_region },
    {
      label = 'SSO login',
      run = function()
        in_terminal('aws sso login' .. (vim.env.AWS_PROFILE and (' --profile ' .. vim.env.AWS_PROFILE) or ''))
      end,
    },
    {
      label = 'SSO logout',
      run = function()
        in_terminal 'aws sso logout'
      end,
    },
    { label = 'Who am I (sts get-caller-identity)', run = M.whoami },
    {
      label = 'Configure a new SSO profile…',
      run = function()
        in_terminal 'aws configure sso'
      end,
    },
  }
  vim.ui.select(items, {
    prompt = 'AWS',
    format_item = function(item)
      return item.label
    end,
  }, function(item)
    if item then
      item.run()
    end
  end)
end

restore()
vim.keymap.set('n', '<leader>A', M.menu, { desc = '[A]WS: profile / region / SSO' })

return M
